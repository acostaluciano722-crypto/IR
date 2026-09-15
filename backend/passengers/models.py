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

    def __str__(self):
        return self.user.get_full_name() or self.user.username


class Ride(models.Model):
    class Status(models.TextChoices):
        REQUESTED = 'requested', 'Solicitado'
        CANCELLED = 'cancelled', 'Cancelado'
        COMPLETED = 'completed', 'Completado'

    passenger = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='rides')
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
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.REQUESTED)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
