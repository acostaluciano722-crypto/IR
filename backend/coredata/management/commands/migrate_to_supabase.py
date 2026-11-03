"""Copy one consistent snapshot into an empty private schema, with verification."""

import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg import sql
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction


TABLES = (
    'rangos', 'zona_geografica', 'tarifa', 'usuario', 'perfil_pasajero',
    'perfil_conductor', 'vehiculo', 'documentos', 'viaje', 'ofertas',
    'transacciones', 'historial_puntos', 'tickets_de_soporte',
    'retiro_bonificacion', 'bonificacion_usuario', 'ir_profile_photo',
    'ir_driver_presence', 'ir_auth_identity',
)


class Command(BaseCommand):
    help = 'Ensaya o importa los datos del PostgreSQL Docker en el esquema ir vacio.'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true', help='Importar tras verificar que el destino esta vacio.')
        parser.add_argument('--source-container', default='ir_postgres_postgis')

    def handle(self, *args, **options):
        if settings.DB_SCHEMA != 'ir':
            raise CommandError('El destino debe usar DB_SCHEMA=ir y DATABASE_URL de Supabase.')
        container = options['source_container']
        inspected = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]
        env = dict(item.split('=', 1) for item in inspected['Config']['Env'] if '=' in item)
        binding = inspected['NetworkSettings']['Ports']['5432/tcp'][0]
        source_params = {
            'host': '127.0.0.1', 'port': binding['HostPort'],
            'dbname': env['POSTGRES_DB'], 'user': env['POSTGRES_USER'],
            'password': env['POSTGRES_PASSWORD'],
        }
        report = {}
        with psycopg.connect(**source_params) as source:
            source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
            source.execute("SET LOCAL TIME ZONE 'UTC'")
            source.execute('SET LOCAL extra_float_digits = 3')
            existing = {row[0] for row in source.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")}
            tables = [table for table in TABLES if table in existing]
            with transaction.atomic():
                with connection.cursor() as target:
                    target.execute('SELECT current_schema()')
                    if target.fetchone()[0] != 'ir':
                        raise CommandError('La conexion de destino no esta en el esquema ir.')
                    target.execute("SET LOCAL TIME ZONE 'UTC'")
                    target.execute('SET LOCAL extra_float_digits = 3')
                    for table in tables:
                        target.execute(sql.SQL('SELECT count(*) FROM ir.{}').format(sql.Identifier(table)))
                        target_count = target.fetchone()[0]
                        source_count = source.execute(sql.SQL('SELECT count(*) FROM public.{}').format(sql.Identifier(table))).fetchone()[0]
                        report[table] = {'source': source_count, 'target': target_count}
                        if options['apply'] and target_count:
                            raise CommandError(f'El destino {table} contiene datos. La importacion no sobrescribe ni mezcla registros.')
                    if options['apply']:
                        backup = Path(settings.BASE_DIR).parent / 'backups'
                        backup.mkdir(exist_ok=True)
                        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
                        with (backup / f'ir-before-supabase-{stamp}.dump').open('xb') as output:
                            subprocess.run(['docker', 'exec', container, 'pg_dump', '-U', env['POSTGRES_USER'],
                                            '-d', env['POSTGRES_DB'], '-Fc', '--no-owner', '--no-privileges'],
                                           stdout=output, check=True)
                        for table in tables:
                            columns = [row[0] for row in source.execute(
                                "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=%s AND is_generated='NEVER' ORDER BY ordinal_position", (table,))]
                            identifiers = sql.SQL(', ').join(map(sql.Identifier, columns))
                            source_table = sql.Identifier('public', table)
                            target_table = sql.Identifier('ir', table)
                            # All domain tables have a stable primary key in their first column.
                            select = sql.SQL('SELECT {} FROM {} ORDER BY {}').format(identifiers, source_table, sql.Identifier(columns[0]))
                            digest = hashlib.sha256()
                            with source.cursor().copy(sql.SQL('COPY ({}) TO STDOUT').format(select)) as reader:
                                with target.copy(sql.SQL('COPY {} ({}) FROM STDIN').format(target_table, identifiers)) as writer:
                                    for block in reader:
                                        payload = bytes(block)
                                        digest.update(payload)
                                        writer.write(payload)
                            copied = hashlib.sha256()
                            verify = sql.SQL('SELECT {} FROM {} ORDER BY {}').format(identifiers, target_table, sql.Identifier(columns[0]))
                            with target.copy(sql.SQL('COPY ({}) TO STDOUT').format(verify)) as reader:
                                for block in reader:
                                    copied.update(bytes(block))
                            if copied.digest() != digest.digest():
                                raise CommandError(f'No coincide la verificacion de {table}; se revierte toda la importacion.')
                            target.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='ir' AND table_name=%s AND is_identity='YES'", (table,))
                            for (column,) in target.fetchall():
                                target.execute('SELECT pg_get_serial_sequence(%s, %s)', (f'ir.{table}', column))
                                sequence = target.fetchone()[0]
                                target.execute(sql.SQL('SELECT max({}) FROM {}').format(sql.Identifier(column), target_table))
                                maximum = target.fetchone()[0]
                                source_sequence = source.execute(
                                    'SELECT pg_get_serial_sequence(%s, %s)', (f'public.{table}', column),
                                ).fetchone()[0]
                                last_value, is_called = source.execute(
                                    sql.SQL('SELECT last_value, is_called FROM {}').format(
                                        sql.Identifier(*source_sequence.split('.', 1)),
                                    ),
                                ).fetchone()
                                # Preserve consumed IDs even if their records were deleted.
                                sequence_value = max(last_value, maximum or 1)
                                sequence_called = is_called or (maximum is not None and maximum >= last_value)
                                target.execute('SELECT setval(%s::regclass, %s, %s)', (sequence, sequence_value, sequence_called))
                            report[table].update({'target': report[table]['source'], 'sha256': digest.hexdigest()})
        self.stdout.write(json.dumps({'applied': options['apply'], 'tables': report}, indent=2))
