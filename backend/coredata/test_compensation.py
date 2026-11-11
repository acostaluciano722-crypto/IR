import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal
from unittest.mock import patch

from django.db import IntegrityError, connection, transaction
from django.test import SimpleTestCase, TestCase
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient, APIRequestFactory, force_authenticate

from coredata.compensation import (
    BOGOTA, CompensationError, _bounds, close_period, credit_due_payouts, mastery_level,
    member_for, record_funding, record_trip_pv, weekly_scores,
)
from coredata.compensation_plan import GRADES, MASTERIES, PLAN_VERSION, grade_for, split_funds
from coredata.models import (
    CompensationAward, CompensationBranchCredit, CompensationControl, CompensationFunding,
    CompensationIncentive, CompensationMember, CompensationPV, CompensationPayout,
    CompensationPeriod, DriverProfile, DriverTransaction, PassengerProfile, Ride, UserBonus, Usuario,
)
from coredata.serializers import RideSerializer, rides_for_action, rides_for_api
from coredata.compensation_views import CompensationMeView
from drivers.api_views import RideUpdateStatusView


class PlanRulesTests(SimpleTestCase):
    def test_every_pdf_grade_boundary(self):
        expected = [(10_000, 300_000, 1), (300_000, 700_000, 3), (900_000, 1_400_000, 5),
                    (1_500_000, 3_000_000, 8), (2_000_000, 6_000_000, 10),
                    (3_000_000, 12_000_000, 20), (4_000_000, 24_000_000, 30), (5_000_000, 50_000_000, 50)]
        for grade, (personal, weak, score) in zip(GRADES, expected):
            self.assertEqual((grade.personal_pv, grade.daily_weak_pv, grade.score), (personal, weak, score))
            self.assertEqual(grade_for(personal, weak, weak).name, grade.name)
            self.assertNotEqual(grade_for(personal, weak - 1, weak), grade)
            self.assertNotEqual(grade_for(personal - 1, weak, weak), grade)

    def test_nested_percentages_and_conservation_including_rounding(self):
        self.assertEqual(split_funds(10_000), {
            'envelope': Decimal('2500'), 'general': Decimal('1350'), 'drivers': Decimal('1080'),
            'passengers': Decimal('270'), 'mastery': Decimal('500'), 'education': Decimal('150'),
            'promotion': Decimal('500')})
        for cents in range(0, 1000):
            profit = Decimal(cents) / 100
            funds = split_funds(profit)
            self.assertLessEqual(funds['envelope'], profit / 4)
            self.assertEqual(sum(funds[k] for k in ['drivers', 'passengers', 'mastery', 'education', 'promotion']), funds['envelope'])
        self.assertEqual(sum(Decimal(m.rate) for m in MASTERIES), Decimal('0.20'))

    def test_invalid_money_is_rejected(self):
        for invalid in ['-1', 'NaN', 'Infinity']:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                split_funds(invalid)

    def test_bogota_day_boundary(self):
        lower, upper = _bounds(date(2026, 10, 1), date(2026, 10, 1))
        self.assertEqual(lower.utcoffset(), timedelta(hours=-5))
        self.assertEqual((upper - lower).days, 1)


class CompensationTests(TestCase):
    def setUp(self):
        self.control, _ = CompensationControl.objects.get_or_create(pk=1)
        self.root = self.member()
        self.left = self.member()
        self.right = self.member()
        self.passenger_user = Usuario.objects.create(id=uuid.uuid4(), rol='passenger', estado='active')
        self.passenger = PassengerProfile.objects.create(id=uuid.uuid4(), user=self.passenger_user,
            points=0, total_rides=0, rating=0, rating_count=0)
        self.t0 = timezone.now() - timedelta(days=100)

    def member(self):
        user = Usuario.objects.create(id=uuid.uuid4(), rol='driver', estado='active')
        driver = DriverProfile.objects.create(id=uuid.uuid4(), user=user, points=0,
            total_rides=0, wallet_balance=20_000, reserved_balance=1000, bonus_balance=0, rating_count=0)
        return member_for(driver)

    def seed_pv(self, member, amount, when=None):
        return CompensationPV.objects.create(member=member, reference=str(uuid.uuid4()), amount=amount,
            occurred_at=when or self.t0, evidence='Fixture de volumen verificado', plan_version=PLAN_VERSION)

    def trip(self, member, fare='10000', status='validated'):
        return Ride.objects.create(id=uuid.uuid4(), driver_profile=member.driver,
            passenger_profile=self.passenger, status=status, final_fare=Decimal(fare),
            offer_amount=Decimal(fare), reserved_debit=1000, created_at=timezone.now())

    def approve(self):
        self.control.profit_definition = 'Fórmula contable de prueba con soporte.'
        self.control.approval_reference = 'Acta de prueba'
        self.control.weekly_distribution = 'sum_daily_scores'
        self.control.mastery_base = 'fund_25_percent'
        self.control.mastery_calendar = 'Calendario explícitamente aprobado en prueba.'
        self.control.promotion_terms = 'Una promoción por período; posiciones conservadas.'
        self.control.save()

    def funding(self, when):
        recharge = DriverTransaction.objects.create(id=uuid.uuid4(), driver_profile=self.root.driver,
            amount=20000, movement_type='recharge', status='completed', payment_reference='provider-confirmed-123',
            created_at=when)
        return record_funding(recharge.pk, '10000', 'Soporte contable prueba')

    def qualify(self, member, when, left=300000, right=300000):
        self.seed_pv(member, 10000, when - timedelta(days=1))
        for side, amount in [('left', left), ('right', right)]:
            event = self.seed_pv(self.left if side == 'left' else self.right, amount, when)
            CompensationBranchCredit.objects.create(event=event, member=member, side=side, amount=amount)

    def test_trip_10000_generates_exactly_10_pv_and_is_idempotent(self):
        ride = self.trip(self.left)
        first = record_trip_pv(ride)
        self.assertEqual(first.amount, Decimal('10'))
        self.assertEqual(record_trip_pv(ride).pk, first.pk)
        self.assertEqual(CompensationPV.objects.filter(ride=ride).count(), 1)
        self.left.driver.refresh_from_db()
        self.assertEqual(self.left.driver.points, 0)  # PV do not overwrite PI.

    def test_fractional_fare_preserves_pv_without_rounding_to_integer(self):
        self.assertEqual(record_trip_pv(self.trip(self.left, '10500.25')).amount, Decimal('10.50025'))

    def test_no_pv_for_unvalidated_or_cancelled_trip(self):
        for state in ['completed', 'cancelled', 'in_progress']:
            with self.subTest(state=state), self.assertRaises(CompensationError):
                record_trip_pv(self.trip(self.left, status=state))

    def test_gate_is_not_retroactive_and_credits_both_sides(self):
        record_trip_pv(self.trip(self.left), self.t0)
        self.assertFalse(self.root.branch_credits.exists())
        self.seed_pv(self.root, 10000, self.t0 + timedelta(seconds=1))
        record_trip_pv(self.trip(self.left), self.t0 + timedelta(seconds=2))
        record_trip_pv(self.trip(self.right), self.t0 + timedelta(seconds=3))
        self.assertEqual(list(self.root.branch_credits.order_by('side').values_list('side', 'amount')),
                         [('left', Decimal('10')), ('right', Decimal('10'))])

    def test_backdated_pv_cannot_change_prior_network_results(self):
        record_trip_pv(self.trip(self.left))
        with self.assertRaises(CompensationError):
            record_trip_pv(self.trip(self.left), self.t0)

    def test_positions_are_automatic_and_cannot_overlap(self):
        extra = self.member()
        self.assertEqual([m.placement.number for m in [self.root, self.left, self.right, extra]], [1, 2, 3, 4])
        self.assertEqual(extra.placement.parent_number, 2)
        self.assertEqual(member_for(extra.driver).pk, extra.pk)
        with self.assertRaises(IntegrityError), transaction.atomic():
            extra.placement.number = 2
            extra.placement.save()

    def test_full_trip_validation_debits_1000_from_20000_and_grants_10_pv_once(self):
        ride = rides_for_api(Ride.objects.filter(pk=self.trip(self.left, status='completed').pk)).get()
        factory = APIRequestFactory()
        def validate():
            request = factory.post('/', {'status': 'validated'}, format='json')
            force_authenticate(request, user=self.left.driver.user)
            return RideUpdateStatusView.as_view()(request, ride_id=ride.api_id)
        self.assertEqual(validate().status_code, 200)
        self.assertEqual(validate().status_code, 200)
        self.left.driver.refresh_from_db()
        self.assertEqual(self.left.driver.wallet_balance, 19000)
        self.assertEqual(self.left.driver.reserved_balance, 0)
        self.assertEqual(self.left.driver.total_rides, 1)
        self.assertEqual(CompensationPV.objects.get(ride=ride).amount, 10)
        self.assertEqual(DriverTransaction.objects.filter(ride=ride, movement_type='trip_fee').count(), 1)

    def test_sandbox_recargas_never_fund_compensation(self):
        self.approve()
        for state, reference in [('sandbox', ''), ('completed', 'sandbox123'), ('pending', 'provider')]:
            recharge = DriverTransaction.objects.create(id=uuid.uuid4(), amount=20000,
                movement_type='recharge', status=state, payment_reference=reference, created_at=timezone.now())
            with self.subTest(state=state), self.assertRaises(CompensationError):
                record_funding(recharge.pk, '10000', 'prueba')

    def test_no_funding_or_closes_without_approved_rules(self):
        with self.assertRaises(CompensationError):
            self.funding(self.t0)
        with self.assertRaises(CompensationError):
            close_period('weekly', date(2026, 9, 1), date(2026, 9, 7), date(2026, 9, 8))

    def test_weekly_goal_distribution_budget_replay_and_credit_once(self):
        self.approve()
        start, end = date(2026, 9, 1), date(2026, 9, 7)
        when = datetime(2026, 9, 2, 12, tzinfo=BOGOTA)
        self.funding(when)
        self.qualify(self.root, when)
        period = close_period('weekly', start, end, date(2026, 9, 8))
        self.assertEqual(period.budget, Decimal('1080'))
        self.assertEqual(period.distributed, Decimal('1080'))
        self.assertEqual(period.reserves['passengers'], '270.00')
        self.assertEqual(period.payouts.get().member_id, self.root.pk)
        self.assertEqual(close_period('weekly', start, end, date(2026, 9, 8)).pk, period.pk)
        self.assertEqual(credit_due_payouts(), 1)
        self.assertEqual(credit_due_payouts(), 0)
        self.root.driver.refresh_from_db()
        self.assertEqual(self.root.driver.bonus_balance, Decimal('1080'))
        self.assertEqual(UserBonus.objects.filter(user=self.root.driver.user).count(), 1)
        with self.assertRaises(CompensationError):
            close_period('weekly', date(2026, 9, 2), date(2026, 9, 8), date(2026, 9, 9))

    def test_no_goal_no_commission_or_redistribution(self):
        self.approve()
        self.funding(datetime(2026, 9, 2, 12, tzinfo=BOGOTA))
        period = close_period('weekly', date(2026, 9, 1), date(2026, 9, 7), date(2026, 9, 8))
        self.assertEqual(period.distributed, 0)
        self.assertEqual(period.reserves['unallocated'], '1080.00')
        self.assertFalse(period.payouts.exists())

    def test_weekly_scores_use_bogota_daily_totals_with_three_queries(self):
        when = datetime(2026, 9, 2, 23, 59, tzinfo=BOGOTA)
        self.qualify(self.root, when)
        with self.assertNumQueries(3):
            weights = weekly_scores([self.root], date(2026, 9, 1), date(2026, 9, 7))
        self.assertEqual(weights[self.root.pk], 1)

    def test_master_bronze_strict_900000_boundary_and_personal_supplement(self):
        lower, upper = _bounds(date(2026, 9, 1), date(2026, 9, 15))
        event = self.seed_pv(self.left, 3000000, lower + timedelta(days=1))
        CompensationBranchCredit.objects.create(member=self.root, event=event, side='left', amount=3000000)
        right_event = self.seed_pv(self.right, 900000, lower + timedelta(days=1))
        weak = CompensationBranchCredit.objects.create(member=self.root, event=right_event, side='right', amount=900000)
        self.seed_pv(self.root, 2100000, lower + timedelta(days=1))
        self.assertEqual(mastery_level(self.root, lower, upper), 0)
        weak.amount = Decimal('900000.00001')
        weak.save()
        self.assertEqual(mastery_level(self.root, lower, upper), 1)

    def test_mastery_retention_incentive_once_and_no_cascading_promotion(self):
        self.approve()
        when = datetime(2026, 9, 2, 12, tzinfo=BOGOTA)
        self.funding(when)
        self.qualify(self.root, when, 3000000, 3000000)
        first = close_period('mastery', date(2026, 9, 1), date(2026, 9, 15), date(2026, 9, 16))
        self.assertEqual(first.payouts.get().amount, Decimal('250'))
        self.assertEqual(first.mastery_awards.get().level, 1)
        close_period('mastery', date(2026, 9, 16), date(2026, 9, 30), date(2026, 10, 7))
        self.assertEqual(CompensationIncentive.objects.filter(member=self.root, level=1).count(), 1)
        self.assertEqual(CompensationAward.objects.filter(member=self.root, level=1).count(), 2)

    def test_own_account_only_and_client_cannot_post_pv_or_close(self):
        client = APIClient()
        self.assertEqual(client.get('/api/driver/compensation/').status_code, 401)
        client.force_authenticate(user=self.passenger_user)
        self.assertEqual(client.get('/api/driver/compensation/').status_code, 403)
        client.force_authenticate(user=self.left.driver.user)
        self.seed_pv(self.root, 90000)
        response = client.get('/api/driver/compensation/', {'member': str(self.root.pk)})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Decimal(response.data['personal_pv']), 0)
        self.assertEqual(client.post('/api/driver/compensation/', {'personal_pv': 999999}).status_code, 405)
        plan = client.get('/api/driver/compensation/plan/').data
        self.assertEqual(len(plan['grades']), 8)
        self.assertEqual(len(plan['masteries']), 7)
        self.assertEqual(plan['trip_fee_percent'], 10)

    def test_pdf_source_is_original_and_authenticated(self):
        client = APIClient()
        client.force_authenticate(user=self.root.driver.user)
        response = client.get('/api/driver/compensation/source/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(b''.join(response.streaming_content).startswith(b'%PDF-'))

    def test_postgres_tables_have_rls(self):
        if connection.vendor != 'postgresql':
            self.skipTest('PostgreSQL RLS verification')
        with connection.cursor() as cursor:
            cursor.execute("SELECT relrowsecurity FROM pg_class WHERE relname LIKE 'ir_compensation_%%' AND relkind='r'")
            flags = cursor.fetchall()
        self.assertEqual(len(flags), 9)
        self.assertTrue(all(row[0] for row in flags))

    def test_pv_and_legacy_debit_roll_back_together_on_failure(self):
        ride = rides_for_api(Ride.objects.filter(pk=self.trip(self.left, status='completed').pk)).get()
        request = APIRequestFactory().post('/', {'status': 'validated'}, format='json')
        force_authenticate(request, user=self.left.driver.user)
        with patch('drivers.api_views.record_trip_pv', side_effect=RuntimeError('Fallo de prueba')):
            with self.assertRaises(RuntimeError):
                RideUpdateStatusView.as_view()(request, ride_id=ride.api_id)
        self.left.driver.refresh_from_db()
        ride.refresh_from_db()
        self.assertEqual(self.left.driver.wallet_balance, 20000)
        self.assertEqual(self.left.driver.total_rides, 0)
        self.assertEqual(ride.status, 'completed')
        self.assertFalse(DriverTransaction.objects.filter(ride=ride).exists())

    def test_nested_descendant_credit_uses_side_of_first_branch(self):
        grandchild = self.member()
        self.seed_pv(self.root, 10000)
        self.seed_pv(self.left, 9999)
        event = record_trip_pv(self.trip(grandchild))
        self.assertEqual(list(event.branch_credits.values_list('member', 'side', 'amount')),
                         [(self.root.pk, 'left', Decimal('10'))])

    def test_future_payable_obligation_is_not_credited_early(self):
        self.approve()
        when = datetime(2026, 9, 2, 12, tzinfo=BOGOTA)
        self.funding(when)
        self.qualify(self.root, when)
        future = timezone.localdate() + timedelta(days=10)
        close_period('weekly', date(2026, 9, 1), date(2026, 9, 7), future)
        self.assertEqual(credit_due_payouts(), 0)
        self.assertIsNone(CompensationPayout.objects.get().credited_at)

    def test_profit_cannot_exceed_recharge_and_duplicate_source_is_rejected(self):
        self.approve()
        entry = self.funding(self.t0)
        self.assertEqual(record_funding(entry.recharge_id, 10000, entry.evidence).pk, entry.pk)
        for profit in [20001, 9999]:
            with self.assertRaises(CompensationError):
                record_funding(entry.recharge_id, profit, entry.evidence)
        self.assertEqual(CompensationFunding.objects.count(), 1)

    def test_higher_masteries_require_three_distinct_previous_awards(self):
        for month, day in [(7, 1), (7, 16)]:
            period = CompensationPeriod.objects.create(kind='mastery', start=date(2026, month, day),
                end=date(2026, month, 15 if day == 1 else 31), payable_on=date(2026, 8, 7),
                net_profit=0, budget=0, distributed=0, plan_version=PLAN_VERSION)
            CompensationAward.objects.create(member=self.root, period=period, level=3)
        # Four distinct Master Oro descendants, two per side, held before September.
        left_child = self.member()  # position 4
        self.member()  # position 5
        right_child = self.member()  # position 6
        for branch, child in [(self.left, left_child), (self.right, right_child)]:
            for person in [branch, child]:
                CompensationAward.objects.create(member=person, period=period, level=3)
        lower, upper = _bounds(date(2026, 9, 1), date(2026, 9, 15))
        self.assertEqual(mastery_level(self.root, lower, upper), 3)
        third = CompensationPeriod.objects.create(kind='mastery', start=date(2026, 8, 1),
            end=date(2026, 8, 15), payable_on=date(2026, 8, 16), net_profit=0,
            budget=0, distributed=0, plan_version=PLAN_VERSION)
        CompensationAward.objects.create(member=self.root, period=third, level=3)
        self.assertEqual(mastery_level(self.root, lower, upper), 4)

    def test_ancestor_credit_query_count_is_independent_of_tree_depth(self):
        members = [self.root, self.left, self.right]
        members.extend(self.member() for _ in range(60))
        for member in members:
            self.seed_pv(member, 10000)
        shallow, deep = self.trip(self.left), self.trip(members[-1])
        with CaptureQueriesContext(connection) as shallow_queries:
            first = record_trip_pv(shallow)
        with CaptureQueriesContext(connection) as deep_queries:
            second = record_trip_pv(deep)
        self.assertEqual(first.branch_credits.count(), 1)
        self.assertEqual(second.branch_credits.count(), 5)
        self.assertEqual(len(shallow_queries), len(deep_queries))

    def test_payment_batch_does_not_issue_per_member_writes(self):
        members = [self.root, self.left, self.right] + [self.member() for _ in range(3)]
        period = CompensationPeriod.objects.create(kind='weekly', start=date(2026, 9, 1),
            end=date(2026, 9, 7), payable_on=date(2026, 9, 8), net_profit=10000,
            budget=1080, distributed=600, plan_version=PLAN_VERSION)
        CompensationPayout.objects.bulk_create([
            CompensationPayout(member=member, period=period, amount=100) for member in members])
        with CaptureQueriesContext(connection) as queries:
            self.assertEqual(credit_due_payouts(), 6)
        self.assertLessEqual(len(queries), 10)
        self.assertEqual(UserBonus.objects.count(), 6)
        self.assertEqual(credit_due_payouts(), 0)
        self.assertEqual(list(DriverProfile.objects.filter(pk__in=[m.driver_id for m in members])
                              .values_list('bonus_balance', flat=True)), [100] * 6)

    def test_action_lookup_is_one_query_and_display_payload_is_unchanged(self):
        ride = self.trip(self.left)
        with self.assertNumQueries(1):
            action = rides_for_action(Ride.objects.filter(pk=ride.pk)).get()
            self.assertEqual(action.passenger_profile.user_id, self.passenger_user.pk)
        with CaptureQueriesContext(connection) as full_queries:
            display = rides_for_api(Ride.objects.filter(pk=ride.pk)).get()
            payload = RideSerializer(display).data
        self.assertGreater(len(full_queries), 1)
        self.assertEqual(payload['id'], action.api_id)
        self.assertEqual(payload['final_fare'], '10000.00')

    def test_compensation_snapshot_uses_eight_queries_without_writing(self):
        request = APIRequestFactory().get('/')
        force_authenticate(request, user=self.root.driver.user)
        with CaptureQueriesContext(connection) as queries:
            response = CompensationMeView.as_view()(request)
        self.assertEqual(response.status_code, 200)
        self.assertLessEqual(len(queries), 8)
        self.assertTrue(all('SELECT' in item['sql'] for item in queries))
        self.assertEqual(response.data['network']['position'], 1)

    def test_location_update_still_returns_the_full_live_payload(self):
        ride = rides_for_api(Ride.objects.filter(pk=self.trip(self.left).pk)).get()
        client = APIClient()
        client.force_authenticate(user=self.passenger_user)
        response = client.post(f'/api/rides/{ride.api_id}/location/',
            {'latitude': 10.42, 'longitude': -75.53}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['passenger_lat'], 10.42)
        self.assertEqual(response.data['passenger_lng'], -75.53)
        self.assertIn('offers', response.data)
        self.assertEqual(response.data['final_fare'], '10000.00')

    def test_ratings_keep_the_average_count_and_cannot_be_repeated(self):
        ride = rides_for_api(Ride.objects.filter(pk=self.trip(self.left).pk)).get()
        client = APIClient()
        client.force_authenticate(user=self.passenger_user)
        url = f'/api/rides/{ride.api_id}/rating/'
        self.assertEqual(client.post(url, {'rating': 5}, format='json').status_code, 200)
        self.assertEqual(client.post(url, {'rating': 1}, format='json').status_code, 409)
        self.left.driver.refresh_from_db()
        self.assertEqual(self.left.driver.rating, 5)
        self.assertEqual(self.left.driver.rating_count, 1)
