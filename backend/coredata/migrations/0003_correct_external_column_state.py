from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('coredata', '0002_initial'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.AlterField(
                    model_name='ride',
                    name='payment_method',
                    field=models.CharField(blank=True, db_column='metodo_pago', max_length=50, null=True),
                ),
                migrations.AlterField(
                    model_name='vehicle',
                    name='plate',
                    field=models.CharField(blank=True, db_column='placa', max_length=10, null=True),
                ),
                migrations.AlterField(
                    model_name='vehicle',
                    name='category',
                    field=models.CharField(blank=True, db_column='categoria', max_length=30, null=True),
                ),
                migrations.AlterField(
                    model_name='drivertransaction',
                    name='amount',
                    field=models.DecimalField(blank=True, db_column='monto', decimal_places=2, max_digits=10, null=True),
                ),
            ],
        ),
    ]