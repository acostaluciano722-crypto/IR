import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier

from django.db import close_old_connections, connection, transaction
from django.db.migrations.executor import MigrationExecutor
from django.test import TestCase, TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient

from coredata.models import (
    BinaryPosition, CompensationControl, CompensationMember, CompensationPV,
    DriverProfile, PassengerProfile, Usuario,
)
from coredata.network import position_for, release_temporary_position


class BinaryNetworkTests(TestCase):
    def setUp(self):
        CompensationControl.objects.get_or_create(pk=1)

    def user(self, role):
        return Usuario.objects.create(id=uuid.uuid4(), rol=role, estado='active', fecha_creacion=timezone.now())

    def test_two_independent_trees_fill_by_level_from_left_to_right(self):
        for expected in range(1, 16):
            for role in ('passenger', 'driver'):
                position = position_for(self.user(role))
                self.assertEqual(position.number, expected)
                self.assertEqual(position.parent_number, expected // 2 or None)
                self.assertEqual(position.depth, expected.bit_length() - 1)
                self.assertEqual(position.side, '' if expected == 1 else ('left' if expected % 2 == 0 else 'right'))
        self.assertEqual(BinaryPosition.objects.filter(network_role='driver').count(), 15)
        self.assertEqual(BinaryPosition.objects.filter(network_role='passenger').count(), 15)

    def test_repeat_lookup_does_not_allocate_another_position_or_lock_the_queue(self):
        user = self.user('driver')
        original = position_for(user)
        with self.assertNumQueries(1):
            again = position_for(user)
        self.assertEqual(original.pk, again.pk)
        self.assertEqual(BinaryPosition.objects.count(), 1)

    def test_registration_failure_rolls_back_position_and_reuses_the_slot(self):
        user = self.user('passenger')
        with self.assertRaises(RuntimeError):
            with transaction.atomic():
                position_for(user)
                raise RuntimeError('Simulated failure')
        self.assertFalse(BinaryPosition.objects.exists())
        self.assertEqual(position_for(user).number, 1)

    def test_client_can_only_read_own_network_and_cannot_choose_a_position(self):
        passenger, driver = self.user('passenger'), self.user('driver')
        position_for(passenger)
        position_for(driver)
        client = APIClient()
        self.assertEqual(client.get('/api/network/').status_code, 401)
        client.force_authenticate(user=passenger)
        response = client.get('/api/network/', {'role': 'driver', 'user': str(driver.pk)})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['role'], 'passenger')
        self.assertEqual(response.data['position'], 1)
        self.assertEqual(client.post('/api/network/', {'position': 1}).status_code, 405)
        self.assertFalse(CompensationMember.objects.exists())
        self.assertFalse(CompensationPV.objects.exists())

    def test_invalid_role_and_reclassifying_an_existing_node_are_rejected(self):
        user = self.user('passenger')
        position_for(user)
        user.rol = 'driver'
        with self.assertRaises(ValueError):
            position_for(user)
        with self.assertRaises(ValueError):
            position_for(self.user('admin'))

    def test_registration_creates_the_position_even_without_opening_compensation(self):
        for role in ('driver', 'passenger', 'driver', 'passenger'):
            suffix = uuid.uuid4().hex[:8]
            response = self.client.post('/api/auth/register/', {
                'name': 'Orden de llegada', 'identifier': f'binary.{suffix}@example.test',
                'phone': suffix, 'role': role, 'password': 'Test-password-123',
                'document_number': suffix, 'vehicle_type': 'moto', 'vehicle_plate': suffix,
                'position': 1, 'sponsor': 'ignored-client-value',
            }, content_type='application/json')
            self.assertEqual(response.status_code, 201, response.content)
            user = Usuario.objects.get(pk=response.json()['user']['id'])
            self.assertEqual(BinaryPosition.objects.get(user=user).number,
                             BinaryPosition.objects.filter(network_role=role).count())
        self.assertEqual(CompensationMember.objects.count(), 2)

    def test_network_table_is_private_with_rls(self):
        with connection.cursor() as cursor:
            cursor.execute("SELECT relrowsecurity FROM pg_class WHERE oid='ir_binary_position'::regclass")
            self.assertTrue(cursor.fetchone()[0])

    def test_cloud_test_cleanup_cannot_remove_a_real_user_or_a_middle_position(self):
        first = self.user('passenger')
        first.correo = 'temporary-first@example.test'
        first.save()
        second = self.user('passenger')
        second.correo = 'temporary-last@example.test'
        second.save()
        position_for(first)
        position_for(second)
        with self.assertRaises(ValueError):
            release_temporary_position(first)
        release_temporary_position(second)
        self.assertEqual(BinaryPosition.objects.count(), 1)
        first.correo = 'real-account@example.com'
        with self.assertRaises(ValueError):
            release_temporary_position(first)


class BinaryMigrationTests(TransactionTestCase):
    """Exercise the REAL historical migration with existing balances and PV."""

    def test_existing_users_are_sorted_by_registration_and_financial_records_survive(self):
        old_target = [('coredata', '0009_compensation_plan')]
        latest = [('coredata', '0011_query_indexes')]
        ids = []
        executor = MigrationExecutor(connection)
        executor.migrate(old_target)
        try:
            old_apps = executor.loader.project_state(old_target).apps
            old_member_model = old_apps.get_model('coredata', 'CompensationMember')
            now = timezone.now()
            # Creation/UUID order intentionally disagrees with registration dates.
            for role, days in [('driver', 1), ('passenger', 2), ('driver', 3), ('passenger', 4)]:
                user = Usuario.objects.create(id=uuid.uuid4(), rol=role, estado='active',
                    fecha_creacion=now - timedelta(days=days))
                ids.append(user.pk)
                if role == 'driver':
                    profile = DriverProfile.objects.create(id=uuid.uuid4(), user=user,
                        wallet_balance=54321, reserved_balance=0, points=123)
                    if days == 1:
                        original = old_member_model.objects.create(id=uuid.uuid4(), driver_id=profile.pk, side='')
                        old_apps.get_model('coredata', 'CompensationPV').objects.create(
                            id=uuid.uuid4(), member_id=original.pk, reference='preserve-migration-pv',
                            amount=5, occurred_at=now, evidence='Historical PV', plan_version='ir-conductores-pdf-v1')
                else:
                    PassengerProfile.objects.create(id=uuid.uuid4(), user=user, points=456)
            executor = MigrationExecutor(connection)
            executor.migrate(latest)
            for role in ('driver', 'passenger'):
                by_date = list(Usuario.objects.filter(pk__in=ids, rol=role).order_by('fecha_creacion').values_list('pk', flat=True))
                actual = list(BinaryPosition.objects.filter(user_id__in=ids, network_role=role)
                              .order_by('number').values_list('user_id', flat=True))
                self.assertEqual(actual, by_date)
            self.assertEqual(CompensationPV.objects.get(reference='preserve-migration-pv').member_id, original.pk)
            self.assertEqual(CompensationMember.objects.get(pk=original.pk).placement.number, 2)
            self.assertEqual(list(DriverProfile.objects.filter(user_id__in=ids).values_list('wallet_balance', flat=True)), [54321, 54321])
            self.assertEqual(list(PassengerProfile.objects.filter(user_id__in=ids).values_list('points', flat=True)), [456, 456])
        finally:
            MigrationExecutor(connection).migrate(latest)
            CompensationPV.objects.filter(member__driver__user_id__in=ids).delete()
            CompensationMember.objects.filter(driver__user_id__in=ids).delete()
            BinaryPosition.objects.filter(user_id__in=ids).delete()
            DriverProfile.objects.filter(user_id__in=ids).delete()
            PassengerProfile.objects.filter(user_id__in=ids).delete()
            Usuario.objects.filter(pk__in=ids).delete()


class BinaryConcurrentRegistrationTests(TransactionTestCase):
    def setUp(self):
        CompensationControl.objects.get_or_create(pk=1)

    def test_concurrent_signups_commit_unique_positions_in_registration_order(self):
        barrier = Barrier(6)
        prefix = f'binary.concurrent.{uuid.uuid4().hex}.'

        def register(index):
            close_old_connections()
            try:
                barrier.wait(timeout=15)
                suffix = uuid.uuid4().hex[:8]
                response = APIClient().post('/api/auth/register/', {
                    'name': 'Concurrent registration', 'identifier': f'{prefix}{index}@example.test',
                    'phone': suffix, 'role': 'driver' if index % 2 else 'passenger',
                    'password': 'Test-password-123', 'document_number': suffix,
                    'vehicle_type': 'moto', 'vehicle_plate': suffix,
                }, format='json')
                return response.status_code
            finally:
                close_old_connections()

        try:
            with ThreadPoolExecutor(max_workers=6) as pool:
                results = list(pool.map(register, range(6)))
            self.assertEqual(results, [201] * 6)
            for role in ('driver', 'passenger'):
                users = Usuario.objects.filter(correo__startswith=prefix, rol=role)
                positions = BinaryPosition.objects.filter(user__in=users).order_by('number')
                self.assertEqual(list(positions.values_list('number', flat=True)), [1, 2, 3])
                self.assertEqual(list(positions.values_list('user_id', flat=True)),
                                 list(users.order_by('fecha_creacion').values_list('pk', flat=True)))
        finally:
            user_ids = list(Usuario.objects.filter(correo__startswith=prefix).values_list('pk', flat=True))
            # Vehicles use a legacy DO_NOTHING relation; remove only this fixture's rows.
            from coredata.models import Vehicle
            CompensationMember.objects.filter(driver__user_id__in=user_ids).delete()
            BinaryPosition.objects.filter(user_id__in=user_ids).delete()
            Vehicle.objects.filter(driver__user_id__in=user_ids).delete()
            DriverProfile.objects.filter(user_id__in=user_ids).delete()
            PassengerProfile.objects.filter(user_id__in=user_ids).delete()
            Usuario.objects.filter(pk__in=user_ids).delete()
