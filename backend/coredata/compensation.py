"""Transactional compensation services. Clients never supply PV or payable COP.

Lock order: singleton control -> ride (if any) -> driver. All financial writes,
network changes and PV ingestion share this order. Audit entries are append-only.
"""

import calendar
import uuid
from collections import deque
from datetime import UTC, datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Count, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from .compensation_plan import COP_PER_PV, MASTERIES, PERSONAL_GATE, PLAN_VERSION, grade_for, money, split_funds
from .network import NETWORK_VERSION, lock_control, position_for
from .models import (
    CompensationAward, CompensationBranchCredit,
    CompensationFunding, CompensationIncentive, CompensationMember, CompensationPV,
    CompensationPayout, CompensationPeriod, DriverProfile, DriverTransaction, UserBonus,
)

BOGOTA = ZoneInfo('America/Bogota')
ZERO = Decimal('0')


class CompensationError(ValueError):
    pass


def member_for(driver):
    existing = CompensationMember.objects.select_related('placement').filter(driver=driver).first()
    if existing:
        return existing
    with transaction.atomic():
        placement = position_for(driver.user)
        if placement.network_role != 'driver':
            raise CompensationError('El perfil no pertenece al árbol de conductores.')
        return CompensationMember.objects.get_or_create(driver=driver, defaults={'placement': placement})[0]


def _bounds(start, end):
    return (datetime.combine(start, time.min, BOGOTA),
            datetime.combine(end + timedelta(days=1), time.min, BOGOTA))


def personal_pv(member, *, before=None, start=None):
    queryset = CompensationPV.objects.filter(member=member)
    if before is not None:
        queryset = queryset.filter(occurred_at__lt=before)
    if start is not None:
        queryset = queryset.filter(occurred_at__gte=start)
    return queryset.aggregate(total=Sum('amount'))['total'] or ZERO


def branch_pv(member, start=None, before=None):
    queryset = CompensationBranchCredit.objects.filter(member=member)
    if start is not None:
        queryset = queryset.filter(event__occurred_at__gte=start)
    if before is not None:
        queryset = queryset.filter(event__occurred_at__lt=before)
    result = {row['side']: row['total'] for row in queryset.values('side').annotate(total=Sum('amount'))}
    return result.get('left', ZERO), result.get('right', ZERO)


@transaction.atomic
def record_trip_pv(ride, occurred_at=None):
    """Called within trip validation; neither recharges nor sandbox cash create PV."""
    control = lock_control()
    reference = f'ride:{ride.pk}'
    existing = CompensationPV.objects.filter(reference=reference).first()
    if existing:
        return existing
    if ride.status != 'validated' or not ride.driver_profile_id:
        raise CompensationError('Solo un viaje validado genera PV.')
    fare = Decimal(str(ride.final_fare or 0))
    if not fare.is_finite() or fare <= 0:
        raise CompensationError('El viaje debe tener una tarifa final positiva.')
    now = occurred_at or timezone.now()
    if timezone.is_naive(now) or now > timezone.now() + timedelta(seconds=1):
        raise CompensationError('La fecha del viaje no es válida.')
    if control.last_pv_at and now < control.last_pv_at:
        raise CompensationError('No se pueden insertar PV anteriores al último evento contabilizado.')
    member = member_for(ride.driver_profile)
    event = CompensationPV.objects.create(
        member=member, ride=ride, reference=reference, amount=fare / COP_PER_PV,
        occurred_at=now, evidence=f'Viaje validado; tarifa COP {fare}; 1 PV por COP 1000.',
        plan_version=PLAN_VERSION,
    )
    sides, child_number = {}, member.placement.number
    while child_number > 1:
        sides[child_number // 2] = 'left' if child_number % 2 == 0 else 'right'
        child_number //= 2
    ancestors = list(CompensationMember.objects.filter(placement__network_role='driver',
        placement__number__in=sides).select_related('placement')) if sides else []
    totals = {row['member']: row['total'] for row in CompensationPV.objects
        .filter(member__in=ancestors).values('member').annotate(total=Sum('amount'))} if ancestors else {}
    # Gates apply at event time; earlier descendant PV are never recovered.
    credits = [CompensationBranchCredit(event=event, member=ancestor,
        side=sides[ancestor.placement.number], amount=event.amount)
        for ancestor in ancestors if totals.get(ancestor.pk, ZERO) >= PERSONAL_GATE]
    CompensationBranchCredit.objects.bulk_create(credits)
    control.last_pv_at = now
    control.save(update_fields=['last_pv_at', 'updated_at'])
    return event


@transaction.atomic
def record_funding(recharge_id, net_profit, evidence):
    control = lock_control()
    if not control.profit_definition.strip() or not control.approval_reference.strip():
        raise CompensationError('Define y aprueba la fórmula de utilidad neta antes de aportar fondos.')
    recharge = DriverTransaction.objects.get(pk=recharge_id)
    if (recharge.movement_type != 'recharge' or recharge.status != 'completed'
            or not recharge.created_at or not recharge.payment_reference
            or recharge.payment_reference.lower().startswith(('sandbox', 'dev', 'test', 'sim'))):
        raise CompensationError('Se necesita una recarga real, confirmada y con referencia verificable.')
    # Legacy columns are timestamp WITHOUT time zone; Django writes UTC to them.
    occurred_at = recharge.created_at
    if timezone.is_naive(occurred_at):
        occurred_at = timezone.make_aware(occurred_at, UTC)
    profit = money(net_profit)
    if profit > (recharge.amount or 0) or not evidence.strip():
        raise CompensationError('La utilidad debe estar soportada y no superar la recarga.')
    if CompensationPeriod.objects.filter(start__lte=occurred_at.astimezone(BOGOTA).date(),
                                        end__gte=occurred_at.astimezone(BOGOTA).date()).exists():
        raise CompensationError('La fecha de esta recarga ya pertenece a un cierre; requiere conciliación.')
    existing = CompensationFunding.objects.filter(recharge=recharge).first()
    if existing:
        if existing.net_profit != profit or existing.evidence != evidence:
            raise CompensationError('Esta recarga ya tiene una utilidad registrada diferente.')
        return existing
    return CompensationFunding.objects.create(recharge=recharge, net_profit=profit,
        occurred_at=occurred_at, evidence=evidence, plan_version=PLAN_VERSION)


def mastery_levels(members, start, before):
    """Three aggregate queries and a bottom-up tree pass, including deep networks.

    Use positions held before the period: new promotions never cascade inside
    the same close. Histograms count each descendant once at its highest level.
    """
    counts, held = {}, {}
    for row in CompensationAward.objects.filter(period__end__lt=start.date()).values(
            'member', 'level').annotate(total=Count('id')):
        counts[row['member'], row['level']] = row['total']
        held[row['member']] = max(held.get(row['member'], 0), row['level'])
    volumes = {(row['member'], row['side']): row['total'] for row in CompensationBranchCredit.objects
        .filter(event__occurred_at__gte=start, event__occurred_at__lt=before)
        .values('member', 'side').annotate(total=Sum('amount'))}
    personal = {row['member']: row['total'] for row in CompensationPV.objects
        .filter(occurred_at__gte=start, occurred_at__lt=before)
        .values('member').annotate(total=Sum('amount'))}
    by_number = {member.placement.number: member for member in members}
    parents = {member.pk: by_number[member.placement.parent_number].pk
               if member.placement.parent_number in by_number else None for member in members}
    children = {member.pk: {} for member in members}
    histograms = {member.pk: [0] * 8 for member in members}
    for member in members:
        if parents[member.pk]:
            children[parents[member.pk]][member.placement.side] = member.pk
        if held.get(member.pk):
            histograms[member.pk][held[member.pk]] = 1
    waiting = {pk: len(sides) for pk, sides in children.items()}
    leaves = deque(pk for pk, total in waiting.items() if total == 0)
    processed = 0
    while leaves:
        pk = leaves.popleft()
        processed += 1
        parent_id = parents[pk]
        if parent_id:
            histograms[parent_id] = [a + b for a, b in zip(histograms[parent_id], histograms[pk])]
            waiting[parent_id] -= 1
            if waiting[parent_id] == 0:
                leaves.append(parent_id)
    if processed != len(members):
        raise CompensationError('Se detectó un ciclo en la red.')
    levels = {}
    for member in members:
        pk = member.pk
        current = held.get(pk, 0)
        target = min(current + 1, 7)
        if target == 1:
            weak, strong = sorted((volumes.get((pk, 'left'), ZERO), volumes.get((pk, 'right'), ZERO)))
            qualified = strong >= 3_000_000 and (weak >= 3_000_000 or
                (weak > 900_000 and weak + personal.get(pk, ZERO) >= 3_000_000))
        else:
            qualified = all(sum(histograms.get(children[pk].get(side), [0] * 8)[target - 1:]) >= 2
                            for side in ('left', 'right'))
            if MASTERIES[target - 1].previous_awards:
                qualified &= counts.get((pk, target - 1), 0) >= 3
        levels[pk] = target if qualified else current
    return levels


def mastery_level(member, start, before):
    return mastery_levels(list(CompensationMember.objects.select_related('placement')), start, before)[member.pk]


def _weighted_shares(budget, weights):
    """Round down; do not transfer absent-member funds to a different category."""
    denominator = sum(weights.values())
    if not denominator:
        return {}
    return {pk: money(budget * Decimal(value) / Decimal(denominator))
            for pk, value in weights.items() if value > 0}


def weekly_scores(members, start, end):
    """Three aggregate queries regardless of the number of members."""
    lower, upper = _bounds(start, end)
    running = {row['member']: row['total'] for row in CompensationPV.objects
        .filter(occurred_at__lt=lower).values('member').annotate(total=Sum('amount'))}
    personal = {(row['member'], row['day']): row['total'] for row in CompensationPV.objects
        .filter(occurred_at__gte=lower, occurred_at__lt=upper)
        .annotate(day=TruncDate('occurred_at', tzinfo=BOGOTA))
        .values('member', 'day').annotate(total=Sum('amount'))}
    branches = {(row['member'], row['day'], row['side']): row['total']
        for row in CompensationBranchCredit.objects
        .filter(event__occurred_at__gte=lower, event__occurred_at__lt=upper)
        .annotate(day=TruncDate('event__occurred_at', tzinfo=BOGOTA))
        .values('member', 'day', 'side').annotate(total=Sum('amount'))}
    scores = {member.pk: 0 for member in members}
    for offset in range(7):
        day = start + timedelta(days=offset)
        for member in members:
            pk = member.pk
            running[pk] = running.get(pk, ZERO) + personal.get((pk, day), ZERO)
            grade = grade_for(running[pk], branches.get((pk, day, 'left'), ZERO),
                              branches.get((pk, day, 'right'), ZERO))
            scores[pk] += grade.score if grade else 0
    return scores


@transaction.atomic
def close_period(kind, start, end, payable_on):
    control = lock_control()
    existing = CompensationPeriod.objects.filter(kind=kind, start=start, end=end).first()
    if existing:
        if existing.payable_on != payable_on:
            raise CompensationError('El cierre existente tiene otra fecha de pago.')
        return existing
    if kind not in {'weekly', 'mastery'} or end < start:
        raise CompensationError('Tipo o fechas del período inválidos.')
    if kind == 'weekly' and (end - start).days != 6:
        raise CompensationError('El período semanal debe tener siete días.')
    if kind == 'mastery' and not (
        start.year == end.year and start.month == end.month and
        ((start.day == 1 and end.day == 15) or
         (start.day == 16 and end.day == calendar.monthrange(end.year, end.month)[1]))
    ):
        raise CompensationError('El período de maestría debe ser 1–15 o 16–fin de mes.')
    if end >= timezone.localdate(timezone.now(), BOGOTA) or payable_on < end:
        raise CompensationError('El período debe terminar antes de hoy y el pago no puede anteceder al cierre.')
    if CompensationPeriod.objects.filter(kind=kind, start__lte=end, end__gte=start).exists():
        raise CompensationError('El período se cruza con otro cierre del mismo fondo.')
    if CompensationPeriod.objects.filter(kind=kind, end__gte=start).exists():
        raise CompensationError('Los cierres de cada fondo deben procesarse en orden cronológico.')
    required = ['profit_definition', 'approval_reference']
    required += ['weekly_distribution'] if kind == 'weekly' else ['mastery_base', 'mastery_calendar', 'promotion_terms']
    missing = [field for field in required if not getattr(control, field).strip()]
    if missing:
        raise CompensationError('Faltan reglas aprobadas: ' + ', '.join(missing))
    if kind == 'weekly' and control.weekly_distribution != 'sum_daily_scores':
        raise CompensationError('La fórmula semanal configurada no está soportada.')
    if kind == 'mastery' and control.mastery_base != 'fund_25_percent':
        raise CompensationError('Debe aprobarse la base monetaria de las maestrías.')
    lower, upper = _bounds(start, end)
    funding = CompensationFunding.objects.filter(occurred_at__gte=lower, occurred_at__lt=upper)
    funds, mastery_budgets, funding_ids, net_profit = split_funds(0), [ZERO] * 7, [], ZERO
    # Stream scalar inputs; evidence text and ORM instances aren't needed here.
    # Split each source once and preserve the original per-source rounding.
    for pk, profit in funding.order_by('pk').values_list('pk', 'net_profit').iterator(chunk_size=1000):
        allocations = split_funds(profit)
        for key, value in allocations.items():
            funds[key] += value
        if kind == 'mastery':
            for index, mastery in enumerate(MASTERIES):
                mastery_budgets[index] += money(allocations['envelope'] * Decimal(mastery.rate))
        funding_ids.append(str(pk))
        net_profit += profit
    budget = funds['drivers' if kind == 'weekly' else 'mastery']
    members = list(CompensationMember.objects.select_related('placement').order_by('placement__number'))
    basis, levels, shares = {}, {}, {}
    if kind == 'weekly':
        weights = weekly_scores(members, start, end)
        basis = {pk: {'daily_score_sum': score} for pk, score in weights.items()}
        shares = _weighted_shares(budget, weights)
    else:
        levels = mastery_levels(members, lower, upper)
        for level, mastery in enumerate(MASTERIES, 1):
            eligible = {pk: 1 for pk, held in levels.items() if held == level}
            level_budget = mastery_budgets[level - 1]
            shares.update(_weighted_shares(level_budget, eligible))
        basis = {pk: {'mastery_level': level} for pk, level in levels.items()}
    distributed = sum(shares.values(), ZERO)
    if distributed > budget:
        raise CompensationError('El reparto excede el fondo permitido.')
    period = CompensationPeriod.objects.create(kind=kind, start=start, end=end,
        payable_on=payable_on, net_profit=net_profit,
        budget=budget, distributed=distributed,
        reserves={**{key: str(value) for key, value in funds.items()},
                  'unallocated': str(budget - distributed), 'funding_ids': funding_ids},
        policy_snapshot={**{key: getattr(control, key) for key in required},
                         'network_version': NETWORK_VERSION}, plan_version=PLAN_VERSION)
    if kind == 'mastery':
        qualified = [(member.pk, levels[member.pk]) for member in members if levels[member.pk]]
        CompensationAward.objects.bulk_create([
            CompensationAward(member_id=pk, period=period, level=level) for pk, level in qualified
        ], batch_size=1000)
        existing_incentives = set(CompensationIncentive.objects.values_list('member_id', 'level')) if qualified else set()
        CompensationIncentive.objects.bulk_create([
            CompensationIncentive(member_id=pk, level=level, description=MASTERIES[level - 1].incentive)
            for pk, level in qualified if (pk, level) not in existing_incentives
        ], batch_size=1000)
    CompensationPayout.objects.bulk_create([
        CompensationPayout(member_id=pk, period=period, amount=value, basis=basis[pk])
        for pk, value in shares.items() if value > 0
    ], batch_size=1000)
    return period


@transaction.atomic
def credit_due_payouts():
    """A repeatable command/task: mature liabilities into bonus balance once."""
    lock_control()
    today = timezone.localdate(timezone.now(), BOGOTA)
    payouts = list(CompensationPayout.objects.select_related('member', 'period')
                   .filter(credited_at__isnull=True, period__payable_on__lte=today)
                   .order_by('member__driver_id', 'pk'))
    if not payouts:
        return 0
    drivers = {driver.pk: driver for driver in DriverProfile.objects.select_for_update()
               .filter(pk__in={p.member.driver_id for p in payouts}).order_by('pk')}
    bonuses, now = [], timezone.now()
    for payout in payouts:
        driver = drivers[payout.member.driver_id]
        balance = (driver.bonus_balance or ZERO) + payout.amount
        # Legacy column is numeric(10,2); never overflow or partially credit.
        if balance > Decimal('99999999.99'):
            raise CompensationError('El saldo de bonos excede la capacidad de la cuenta; requiere conciliación.')
        driver.bonus_balance = balance
        payout.legacy_bonus = UserBonus(id=uuid.uuid4(), user_id=driver.user_id,
            network_role='driver', reason=f'Plan PDF {payout.period.kind}',
            generated_points=0, liquidated_amount=payout.amount,
            status='liquidated', closed_at=now)
        bonuses.append(payout.legacy_bonus)
        payout.credited_at = now
    UserBonus.objects.bulk_create(bonuses, batch_size=1000)
    DriverProfile.objects.bulk_update(list(drivers.values()), ['bonus_balance'], batch_size=1000)
    CompensationPayout.objects.bulk_update(payouts, ['legacy_bonus', 'credited_at'], batch_size=1000)
    return len(payouts)
