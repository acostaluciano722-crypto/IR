from django.conf import settings
from django.db import models


class AccountProfile(models.Model):
    class Role(models.TextChoices):
        PASSENGER = 'passenger', 'Pasajero'
        DRIVER = 'driver', 'Conductor'

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.PASSENGER)
    phone = models.CharField(max_length=20, blank=True)
    document_number = models.CharField(max_length=40, blank=True)
    vehicle_type = models.CharField(max_length=30, blank=True)
    vehicle_plate = models.CharField(max_length=12, blank=True)


class PassengerProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    phone = models.CharField(max_length=20, blank=True)
    points = models.PositiveIntegerField(default=0)
    tier = models.CharField(max_length=40, default='Inicial')
    referral_code = models.CharField(max_length=20, blank=True, unique=True, null=True)
    referred_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='passenger_referrals',
    )
    total_rides = models.PositiveIntegerField(default=0)

    def __str__(self):
        return self.user.get_full_name() or self.user.username

    def recalculate_tier(self):
        """Recalculate tier based on accumulated points per ProMaster V2.0 rules.
        Inicial:     0 – 499
        Bronce:    500 – 1499
        Plata:    1500 – 3499
        Oro:      3500 – 6999
        Platino:  7000 – 11999
        Diamante: 12000+
        """
        p = self.points
        if p >= 12000:
            self.tier = 'Diamante'
        elif p >= 7000:
            self.tier = 'Platino'
        elif p >= 3500:
            self.tier = 'Oro'
        elif p >= 1500:
            self.tier = 'Plata'
        elif p >= 500:
            self.tier = 'Bronce'
        else:
            self.tier = 'Inicial'

    def add_points(self, amount, description=''):
        """Add points and recalculate tier. Returns the new total."""
        self.points += amount
        self.recalculate_tier()
        self.save()
        PointTransaction.objects.create(
            user=self.user,
            amount=amount,
            description=description,
            balance_after=self.points,
        )
        return self.points


class PointTransaction(models.Model):
    """Ledger of every point movement for passengers and drivers."""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='point_transactions')
    amount = models.IntegerField()  # positive = earned, negative = redeemed
    description = models.CharField(max_length=255)
    balance_after = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']


class Ride(models.Model):
    class Status(models.TextChoices):
        REQUESTED = 'requested', 'Solicitado'
        NEGOTIATING = 'negotiating', 'Negociando'
        DRIVER_SELECTED = 'driver_selected', 'Conductor Seleccionado'
        EN_ROUTE = 'en_route', 'En Ruta'
        ARRIVED = 'arrived', 'Llegó'
        IN_PROGRESS = 'in_progress', 'En Progreso'
        COMPLETED = 'completed', 'Completado'
        VALIDATED = 'validated', 'Validado'
        CANCELLED = 'cancelled', 'Cancelado'

    passenger = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='rides_as_passenger')
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='rides_as_driver')
    origin = models.CharField(max_length=255)
    destination = models.CharField(max_length=255)
    origin_lat = models.DecimalField(max_digits=9, decimal_places=6, default=0)
    origin_lng = models.DecimalField(max_digits=9, decimal_places=6, default=0)
    destination_lat = models.DecimalField(max_digits=9, decimal_places=6, default=0)
    destination_lng = models.DecimalField(max_digits=9, decimal_places=6, default=0)
    distance_km = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    duration_minutes = models.PositiveIntegerField(default=0)
    vehicle_type = models.CharField(max_length=30, default='economy')
    offer_amount = models.PositiveIntegerField(default=0)
    estimated_price = models.PositiveIntegerField(default=0)
    final_fare = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.REQUESTED)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
