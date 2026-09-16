from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('passengers', '0008_ride_location_labels'),
    ]

    operations = [
        migrations.AddField(
            model_name='accountprofile',
            name='vehicle_brand',
            field=models.CharField(blank=True, max_length=50),
        ),
        migrations.AddField(
            model_name='accountprofile',
            name='vehicle_color',
            field=models.CharField(blank=True, max_length=30),
        ),
        migrations.AddField(
            model_name='ride',
            name='pickup_code',
            field=models.CharField(blank=True, max_length=8),
        ),
    ]