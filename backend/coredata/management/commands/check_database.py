import json

from django.apps import apps
from django.core.management.base import BaseCommand, CommandError
from django.db import DatabaseError, connection


class Command(BaseCommand):
    help = 'Verifica PostgreSQL/PostGIS y muestra la base real y los datos guardados.'

    def handle(self, *args, **options):
        if connection.vendor != 'postgresql':
            raise CommandError('La API requiere PostgreSQL con PostGIS.')
        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT current_database(), current_schema(), PostGIS_Version()')
                database, schema, postgis = cursor.fetchone()
                tables = set(connection.introspection.table_names(cursor))
                counts = {}
                for model in apps.get_app_config('coredata').get_models():
                    table = model._meta.db_table
                    if table not in tables:
                        raise CommandError(f'Falta la tabla {table}.')
                    columns = {
                        column.name
                        for column in connection.introspection.get_table_description(cursor, table)
                    }
                    required = {field.column for field in model._meta.local_fields}
                    if table == 'viaje':
                        required.update({
                            'api_id', 'coordenada_origen', 'coordenada_destino',
                            'ubicacion_pasajero', 'ubicacion_conductor',
                        })
                    elif table == 'ofertas':
                        required.add('api_id')
                    missing = required - columns
                    if missing:
                        raise CommandError(f'Faltan columnas en {table}: {sorted(missing)}')
                    counts[table] = model.objects.count()
        except DatabaseError as error:
            raise CommandError('No se pudo verificar PostgreSQL/PostGIS. Revisa la conexion y las migraciones.') from error
        self.stdout.write(json.dumps({
            'database': database,
            'schema': schema,
            'host': connection.settings_dict['HOST'],
            'port': connection.settings_dict['PORT'],
            'postgis': postgis,
            'rows': counts,
        }, indent=2))
