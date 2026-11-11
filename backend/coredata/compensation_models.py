"""Django-managed, private audit records for the PDF compensation plan."""

import uuid

from django.db import models


class CompensationControl(models.Model):
    """Singleton also used to serialize ingestion, placement and financial closes."""

    id = models.PositiveSmallIntegerField(primary_key=True, default=1, editable=False)
    pv_definition = models.TextField(blank=True)
    profit_definition = models.TextField(blank=True)
    weekly_distribution = models.CharField(max_length=40, blank=True,
                                            choices=[('sum_daily_scores', 'Suma de puntuaciones diarias')])
    mastery_base = models.CharField(max_length=40, blank=True,
                                    choices=[('fund_25_percent', 'Fondo del 25% de utilidad neta')])
    mastery_calendar = models.TextField(blank=True)
    promotion_terms = models.TextField(blank=True)
    approval_reference = models.CharField(max_length=250, blank=True)
    last_pv_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'ir_compensation_control'


class BinaryPosition(models.Model):
    """Two independent, complete binary trees, indexed in registration order.

    Parent = number // 2; children = 2 * number and 2 * number + 1.
    No editable ancestor, sponsor or side can create a second topology.
    """

    user = models.OneToOneField('coredata.Usuario', on_delete=models.PROTECT,
                                 primary_key=True, related_name='binary_position')
    network_role = models.CharField(max_length=10, choices=[('driver', 'Conductor'), ('passenger', 'Pasajero')])
    number = models.PositiveBigIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ir_binary_position'
        constraints = [
            models.UniqueConstraint(fields=['network_role', 'number'], name='ir_network_number_unique'),
            models.CheckConstraint(condition=models.Q(number__gte=1), name='ir_network_number_positive'),
            models.CheckConstraint(condition=models.Q(network_role__in=['driver', 'passenger']),
                                   name='ir_network_role_valid'),
        ]

    @property
    def parent_number(self):
        return self.number // 2 or None

    @property
    def side(self):
        return '' if self.number == 1 else ('left' if self.number % 2 == 0 else 'right')

    @property
    def depth(self):
        return self.number.bit_length() - 1


class CompensationMember(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    driver = models.OneToOneField('coredata.DriverProfile', on_delete=models.PROTECT,
                                   related_name='compensation')
    placement = models.OneToOneField(BinaryPosition, on_delete=models.PROTECT,
                                     related_name='compensation_member')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ir_compensation_member'


class CompensationPV(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    member = models.ForeignKey(CompensationMember, on_delete=models.PROTECT, related_name='pv_events')
    reference = models.CharField(max_length=160, unique=True)
    amount = models.DecimalField(max_digits=20, decimal_places=5)
    ride = models.OneToOneField('coredata.Ride', on_delete=models.PROTECT, null=True, blank=True)
    occurred_at = models.DateTimeField(db_index=True)
    evidence = models.TextField()
    plan_version = models.CharField(max_length=40)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ir_compensation_pv'
        constraints = [models.CheckConstraint(condition=models.Q(amount__gt=0), name='ir_pv_positive')]
        indexes = [models.Index(fields=['member', 'occurred_at'], name='ir_pv_member_date')]


class CompensationBranchCredit(models.Model):
    event = models.ForeignKey(CompensationPV, on_delete=models.PROTECT, related_name='branch_credits')
    member = models.ForeignKey(CompensationMember, on_delete=models.PROTECT, related_name='branch_credits')
    side = models.CharField(max_length=5, choices=[('left', 'Izquierdo'), ('right', 'Derecho')])
    amount = models.DecimalField(max_digits=20, decimal_places=5)

    class Meta:
        db_table = 'ir_compensation_branch'
        constraints = [
            models.UniqueConstraint(fields=['event', 'member'], name='ir_branch_event_unique'),
            models.CheckConstraint(condition=models.Q(side__in=['left', 'right']), name='ir_credit_side_valid'),
            models.CheckConstraint(condition=models.Q(amount__gt=0), name='ir_branch_pv_positive'),
        ]


class CompensationFunding(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    recharge = models.OneToOneField('coredata.DriverTransaction', on_delete=models.PROTECT)
    net_profit = models.DecimalField(max_digits=18, decimal_places=2)
    occurred_at = models.DateTimeField(db_index=True)
    evidence = models.TextField()
    plan_version = models.CharField(max_length=40)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ir_compensation_funding'
        constraints = [models.CheckConstraint(condition=models.Q(net_profit__gte=0), name='ir_profit_nonnegative')]


class CompensationPeriod(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    kind = models.CharField(max_length=10, choices=[('weekly', 'Semanal'), ('mastery', 'Maestrías')])
    start = models.DateField()
    end = models.DateField()
    payable_on = models.DateField()
    net_profit = models.DecimalField(max_digits=18, decimal_places=2)
    budget = models.DecimalField(max_digits=18, decimal_places=2)
    distributed = models.DecimalField(max_digits=18, decimal_places=2)
    reserves = models.JSONField(default=dict)
    policy_snapshot = models.JSONField(default=dict)
    plan_version = models.CharField(max_length=40)
    closed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ir_compensation_period'
        constraints = [
            models.UniqueConstraint(fields=['kind', 'start', 'end'], name='ir_close_period_unique'),
            models.CheckConstraint(condition=models.Q(end__gte=models.F('start')), name='ir_period_dates_valid'),
            models.CheckConstraint(condition=models.Q(distributed__gte=0) & models.Q(budget__gte=models.F('distributed')),
                                   name='ir_period_budget_limit'),
        ]


class CompensationAward(models.Model):
    member = models.ForeignKey(CompensationMember, on_delete=models.PROTECT, related_name='mastery_awards')
    period = models.ForeignKey(CompensationPeriod, on_delete=models.PROTECT, related_name='mastery_awards')
    level = models.PositiveSmallIntegerField()

    class Meta:
        db_table = 'ir_compensation_award'
        constraints = [
            models.UniqueConstraint(fields=['member', 'period'], name='ir_mastery_once_per_period'),
            models.CheckConstraint(condition=models.Q(level__gte=1, level__lte=7), name='ir_mastery_level_valid'),
        ]


class CompensationPayout(models.Model):
    member = models.ForeignKey(CompensationMember, on_delete=models.PROTECT, related_name='payouts')
    period = models.ForeignKey(CompensationPeriod, on_delete=models.PROTECT, related_name='payouts')
    amount = models.DecimalField(max_digits=18, decimal_places=2)
    basis = models.JSONField(default=dict)
    legacy_bonus = models.OneToOneField('coredata.UserBonus', on_delete=models.PROTECT, null=True)
    credited_at = models.DateTimeField(null=True)

    class Meta:
        db_table = 'ir_compensation_payout'
        constraints = [
            models.UniqueConstraint(fields=['member', 'period'], name='ir_compensation_payout_unique'),
            models.CheckConstraint(condition=models.Q(amount__gt=0), name='ir_payout_positive'),
        ]


class CompensationIncentive(models.Model):
    member = models.ForeignKey(CompensationMember, on_delete=models.PROTECT, related_name='incentives')
    level = models.PositiveSmallIntegerField()
    description = models.TextField()
    status = models.CharField(max_length=15, default='pending', choices=[('pending', 'Pendiente de entrega'), ('delivered', 'Entregado')])
    awarded_at = models.DateTimeField(auto_now_add=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    delivery_reference = models.TextField(blank=True)

    class Meta:
        db_table = 'ir_compensation_incentive'
        constraints = [
            models.UniqueConstraint(fields=['member', 'level'], name='ir_incentive_once_per_mastery'),
            models.CheckConstraint(condition=models.Q(level__gte=1, level__lte=7), name='ir_incentive_level_valid'),
        ]
