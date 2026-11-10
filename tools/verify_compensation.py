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
from rest_framework.test import APIClient

from coredata.compensation_plan import PLAN_VERSION
from coredata.models import CompensationMember, DriverProfile


def run():
    with connection.cursor() as cursor:
        cursor.execute("SELECT c.relname, c.relrowsecurity FROM pg_class c JOIN pg_namespace n "
                       "ON n.oid=c.relnamespace WHERE n.nspname=current_schema() "
                       "AND c.relname LIKE 'ir_compensation_%%' AND c.relkind='r'")
        tables = cursor.fetchall()
        if len(tables) != 9 or not all(secured for _, secured in tables):
            raise RuntimeError('Faltan tablas de compensación o RLS.')
        cursor.execute("SELECT table_name, grantee FROM information_schema.table_privileges "
                       "WHERE table_schema=current_schema() AND table_name LIKE 'ir_compensation_%%' "
                       "AND grantee IN ('PUBLIC', 'anon', 'authenticated')")
        if cursor.fetchall():
            raise RuntimeError('Una tabla de compensación tiene privilegios directos del cliente.')
    if not MigrationRecorder.Migration.objects.filter(app='coredata', name='0009_compensation_plan').exists():
        raise RuntimeError('La migración no está registrada.')
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
                      'direct_client_grants': 0, 'original_pdf': 'ok',
                      'authenticated_domain_reads': 'ok' if driver else 'no_driver_available',
                      'temporary_data_retained': False, 'deployed_api': health,
                      'anonymous_access': 'blocked'}, ensure_ascii=True))


if __name__ == '__main__':
    run()
