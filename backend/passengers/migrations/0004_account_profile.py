from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('passengers', '0003_ride_location_metrics'),
    ]

    operations = [
        migrations.CreateModel(
            name='AccountProfile',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('role', models.CharField(choices=[('passenger', 'Pasajero'), ('driver', 'Conductor')], default='passenger', max_length=20)),
                ('phone', models.CharField(blank=True, max_length=20)),
                ('document_number', models.CharField(blank=True, max_length=40)),
                ('vehicle_type', models.CharField(blank=True, max_length=30)),
                ('vehicle_plate', models.CharField(blank=True, max_length=12)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, to='auth.user')),
            ],
        ),
    ]