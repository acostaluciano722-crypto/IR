from django.db import migrations, models
import coredata.models


class Migration(migrations.Migration):
    dependencies = [('coredata', '0004_support_description_column')]

    operations = [
        migrations.CreateModel(
            name='UserProfilePhoto',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('user_id', models.UUIDField(db_index=True, unique=True)),
                ('image', models.FileField(upload_to=coredata.models.profile_photo_upload_to)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={'db_table': 'ir_profile_photo'},
        ),
        migrations.CreateModel(
            name='DriverPresence',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('driver_id', models.UUIDField(db_index=True, unique=True)),
                ('latitude', models.FloatField()),
                ('longitude', models.FloatField()),
                ('vehicle_type', models.CharField(default='carro', max_length=30)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={'db_table': 'ir_driver_presence'},
        ),
    ]
