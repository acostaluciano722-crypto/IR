from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('coredata', '0003_correct_external_column_state')]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.AlterField(
                    model_name='supportticket',
                    name='description',
                    field=models.TextField(db_column='descripcion', null=True, blank=True),
                ),
            ],
        ),
    ]
