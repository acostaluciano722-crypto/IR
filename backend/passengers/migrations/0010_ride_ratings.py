from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('passengers', '0009_accountprofile_vehicle_brand_and_more')]

    operations = [
        migrations.AddField(model_name='ride', name='passenger_rating', field=models.PositiveSmallIntegerField(blank=True, null=True)),
        migrations.AddField(model_name='ride', name='driver_rating', field=models.PositiveSmallIntegerField(blank=True, null=True)),
    ]