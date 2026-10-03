from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('passengers', '0010_ride_ratings')]

    operations = [
        migrations.AddField(
            model_name='passengerprofile',
            name='rating_sum',
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='passengerprofile',
            name='rating_count',
            field=models.PositiveIntegerField(default=0),
        ),
    ]