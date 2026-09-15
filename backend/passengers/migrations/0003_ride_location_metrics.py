from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('passengers', '0002_ride_pricing')]

    operations = [
        migrations.AddField(model_name='ride', name='origin_lat', field=models.DecimalField(decimal_places=6, default=0, max_digits=9)),
        migrations.AddField(model_name='ride', name='origin_lng', field=models.DecimalField(decimal_places=6, default=0, max_digits=9)),
        migrations.AddField(model_name='ride', name='destination_lat', field=models.DecimalField(decimal_places=6, default=0, max_digits=9)),
        migrations.AddField(model_name='ride', name='destination_lng', field=models.DecimalField(decimal_places=6, default=0, max_digits=9)),
        migrations.AddField(model_name='ride', name='distance_km', field=models.DecimalField(decimal_places=2, default=0, max_digits=7)),
        migrations.AddField(model_name='ride', name='duration_minutes', field=models.PositiveIntegerField(default=0)),
    ]
