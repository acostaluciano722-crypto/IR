from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('passengers', '0006_passengerprofile_referral_code_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='ride',
            name='passenger_lat',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name='ride',
            name='passenger_lng',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name='ride',
            name='driver_lat',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name='ride',
            name='driver_lng',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
    ]