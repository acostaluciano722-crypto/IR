from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('passengers', '0007_ride_live_locations'),
    ]

    operations = [
        migrations.AddField(
            model_name='ride',
            name='passenger_location_label',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='ride',
            name='driver_location_label',
            field=models.CharField(blank=True, max_length=255),
        ),
    ]