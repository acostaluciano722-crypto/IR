from django.db import migrations


def backfill_total_rides(apps, schema_editor):
    PassengerProfile = apps.get_model('passengers', 'PassengerProfile')
    DriverProfile = apps.get_model('drivers', 'DriverProfile')
    Ride = apps.get_model('passengers', 'Ride')

    for profile in PassengerProfile.objects.all():
        profile.total_rides = Ride.objects.filter(
            passenger_id=profile.user_id,
            status='validated',
        ).count()
        profile.save(update_fields=['total_rides'])

    for profile in DriverProfile.objects.all():
        profile.total_rides = Ride.objects.filter(
            driver_id=profile.user_id,
            status='validated',
        ).count()
        profile.save(update_fields=['total_rides'])


class Migration(migrations.Migration):
    dependencies = [
        ('passengers', '0011_passengerprofile_rating'),
        ('drivers', '0002_driverprofile_points_driverprofile_rating_count_and_more'),
    ]

    operations = [migrations.RunPython(backfill_total_rides, migrations.RunPython.noop)]