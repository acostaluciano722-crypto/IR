from django.conf import settings
from django.db import models
from passengers.models import Ride


class DriverProfile(models.Model):
    class Status(models.TextChoices):
        OFFLINE = 'offline', 'Offline'
        AVAILABLE = 'available', 'Disponible'
        OFFERING = 'offering', 'Ofreciendo'
        RESERVED_FOR_TRIP = 'reserved_for_trip', 'Reservado para viaje'
        EN_ROUTE = 'en_route', 'En Ruta'
        ARRIVED = 'arrived', 'Llegó'
        IN_TRIP = 'in_trip', 'En Viaje'
        TEMPORARILY_UNAVAILABLE = 'temporarily_unavailable', 'Temporalmente no disponible'
        RESTRICTED = 'restricted', 'Restringido'

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='driver_profile')
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.OFFLINE)
    wallet_balance = models.PositiveIntegerField(default=0)
    reserved_balance = models.PositiveIntegerField(default=0)
    points = models.PositiveIntegerField(default=0)
    tier = models.CharField(max_length=40, default='Inicial')
    total_rides = models.PositiveIntegerField(default=0)
    rating_sum = models.PositiveIntegerField(default=0)
    rating_count = models.PositiveIntegerField(default=0)
    referral_code = models.CharField(max_length=20, blank=True, unique=True, null=True)
    referred_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='driver_referrals',
    )

    @property
    def rating(self):
        if self.rating_count == 0:
            return 5.0
        return round(self.rating_sum / self.rating_count, 1)

    def recalculate_tier(self):
        """Driver tier thresholds (ProMaster V2.0):
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
        from passengers.models import PointTransaction
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

    def __str__(self):
        return f"Driver {self.user.username} - {self.status}"


class RideOffer(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pendiente'
        ACCEPTED = 'accepted', 'Aceptada'
        REJECTED = 'rejected', 'Rechazada'

    ride = models.ForeignKey(Ride, on_delete=models.CASCADE, related_name='offers')
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='ride_offers')
    amount = models.PositiveIntegerField()
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Offer {self.amount} for ride {self.ride.id} by {self.driver.username}"
