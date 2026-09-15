from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('passengers', '0001_initial')]

    operations = [
        migrations.AddField(model_name='ride', name='offer_amount', field=models.PositiveIntegerField(default=0)),
        migrations.AddField(model_name='ride', name='estimated_price', field=models.PositiveIntegerField(default=0)),
    ]
