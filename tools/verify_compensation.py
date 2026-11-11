"""Verify the deployed compensation schema and read API without retaining test data."""

import hashlib
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

import django
django.setup()

from django.db import connection, transaction
from django.db.migrations.recorder import MigrationRecorder
from django.db.models import Count, F, Max, Min
from rest_framework.test import APIClient

from coredata.compensation_plan import PLAN_VERSION
from coredata.models import BinaryPosition, CompensationMember, DriverProfile, Usuario


def run():
    with connection.cursor() as cursor:
        cursor.execute("SELECT c.relname, c.relrowsecurity FROM pg_class c JOIN pg_namespace n "
                       "ON n.oid=c.relnamespace WHERE n.nspname=current_schema() "
                       "AND (c.relname LIKE 'ir_compensation_%%' OR c.relname='ir_binary_position') AND c.relkind='r'")
        tables = cursor.fetchall()
        if len(tables) != 10 or not all(secured for _, secured in tables):
            raise RuntimeError('Faltan tablas de compensación o RLS.')
        cursor.execute("SELECT table_name, grantee FROM information_schema.table_privileges "
                       "WHERE table_schema=current_schema() AND (table_name LIKE 'ir_compensation_%%' OR table_name='ir_binary_position') "
                       "AND grantee IN ('PUBLIC', 'anon', 'authenticated')")
        if cursor.fetchall():
            raise RuntimeError('Una tabla de compensación tiene privilegios directos del cliente.')
        cursor.execute('SELECT NOT EXISTS (SELECT 1 FROM ('
                       'SELECT u.fecha_creacion, LAG(u.fecha_creacion) OVER '
                       '(PARTITION BY p.network_role ORDER BY p.number) AS previous '
                       'FROM ir_binary_position p JOIN usuario u ON u.id_usuario=p.user_id '
                       'WHERE u.fecha_creacion IS NOT NULL) ordered '
                       'WHERE fecha_creacion < previous)')
        if not cursor.fetchone()[0]:
            raise RuntimeError('Las posiciones no respetan las fechas de registro conocidas.')
        cursor.execute("SELECT indexname FROM pg_indexes WHERE schemaname=current_schema() AND indexname IN "
                       "('ir_ride_passenger_created_idx','ir_ride_driver_created_idx','ir_transaction_driver_created_idx')")
        if len(cursor.fetchall()) != 3:
            raise RuntimeError('Faltan índices de historial.')
    if not MigrationRecorder.Migration.objects.filter(app='coredata', name='0009_compensation_plan').exists():
        raise RuntimeError('La migración no está registrada.')
    if not MigrationRecorder.Migration.objects.filter(app='coredata', name='0011_query_indexes').exists():
        raise RuntimeError('Las migraciones del árbol automático no están registradas.')
    networks = list(BinaryPosition.objects.values('network_role').annotate(
        total=Count('user'), first=Min('number'), last=Max('number')).order_by('network_role'))
    if any(row['first'] != 1 or row['last'] != row['total'] for row in networks):
        raise RuntimeError('Una red tiene posiciones repetidas o huecos.')
    if BinaryPosition.objects.exclude(network_role=F('user__rol')).exists():
        raise RuntimeError('Un integrante está ubicado en la red del otro rol.')
    if Usuario.objects.filter(rol__in=['driver', 'passenger'], binary_position__isnull=True).exists():
        raise RuntimeError('Un usuario registrado no tiene posición automática.')
    if CompensationMember.objects.exclude(placement_id=F('driver__user_id')).exists():
        raise RuntimeError('Un perfil de compensación está unido a otra cuenta.')
    source = ROOT / 'backend' / 'coredata' / 'resources' / 'compensation_plan.pdf'
    if hashlib.sha256(source.read_bytes()).hexdigest() != '4d576c2512f3f7527e6e696652cf3873936f8e4670e732776f650bca967c0192':
        raise RuntimeError('El PDF no coincide con el original recibido.')
    initial_members = CompensationMember.objects.count()
    driver = DriverProfile.objects.select_related('user').order_by('pk').first()
    if driver:
        with transaction.atomic():
            client = APIClient()
            client.force_authenticate(user=driver.user)
            response = client.get('/api/driver/compensation/', HTTP_HOST='localhost')
            if response.status_code != 200 or 'personal_pv' not in response.data:
                raise RuntimeError('La lectura de la cuenta de compensación falló.')
            plan = client.get('/api/driver/compensation/plan/', HTTP_HOST='localhost')
            if plan.status_code != 200 or len(plan.data['grades']) != 8 or len(plan.data['masteries']) != 7:
                raise RuntimeError('El catálogo no coincide con el plan.')
            network = client.get('/api/network/', HTTP_HOST='localhost')
            if network.status_code != 200 or network.data['role'] != 'driver':
                raise RuntimeError('La lectura del árbol de conductores falló.')
            transaction.set_rollback(True)
    if CompensationMember.objects.count() != initial_members:
        raise RuntimeError('La comprobación no revirtió su alta temporal.')
    with urlopen('http://127.0.0.1:8000/api/health/', timeout=20) as response:
        health = json.load(response)
    if health.get('database') != 'ok' or health.get('postgis') != 'ok':
        raise RuntimeError('La API en ejecución no está saludable.')
    try:
        urlopen('http://127.0.0.1:8000/api/driver/compensation/plan/', timeout=20)
    except HTTPError as error:
        if error.code != 401:
            raise RuntimeError(f'La ruta desplegada respondió HTTP {error.code}.') from None
    else:
        raise RuntimeError('La ruta de compensación permitió acceso anónimo.')
    print(json.dumps({'version': PLAN_VERSION, 'migration': 'ok', 'private_rls_tables': len(tables),
                      'independent_binary_networks': networks,
                      'known_registration_order': 'ok', 'history_indexes': 3,
                      'direct_client_grants': 0, 'original_pdf': 'ok',
                      'authenticated_domain_reads': 'ok' if driver else 'no_driver_available',
                      'temporary_data_retained': False, 'deployed_api': health,
                      'anonymous_access': 'blocked'}, ensure_ascii=True))


if __name__ == '__main__':
    run()
