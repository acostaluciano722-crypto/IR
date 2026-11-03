from django.db import migrations


def secure_sessions(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cursor:
        cursor.execute('SELECT current_schema()')
        if cursor.fetchone()[0] == 'ir':
            cursor.execute('ALTER TABLE ir.django_session ENABLE ROW LEVEL SECURITY')
            cursor.execute('REVOKE ALL ON ir.django_session FROM anon, authenticated')


class Migration(migrations.Migration):
    dependencies = [
        ('coredata', '0006_supabase_identity'),
        ('sessions', '0001_initial'),
    ]
    operations = [migrations.RunPython(secure_sessions, migrations.RunPython.noop)]
