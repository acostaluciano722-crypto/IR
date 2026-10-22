"""Tasks discovered by Celery in the installed coredata app."""

import uuid

from celery import shared_task
from django.core.cache import cache
from django.db import connection


@shared_task(name='coredata.infrastructure_probe')
def infrastructure_probe():
    """Verify the entire broker -> worker -> PostgreSQL/cache -> result path."""
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1')
        if cursor.fetchone()[0] != 1:
            raise RuntimeError('PostgreSQL no respondio correctamente.')
    key = f'worker-probe:{uuid.uuid4().hex}'
    cache.set(key, 'ok', timeout=15)
    try:
        if cache.get(key) != 'ok':
            raise RuntimeError('La cache no respondio correctamente.')
    finally:
        cache.delete(key)
    return {'worker': 'ok', 'database': 'ok', 'cache': 'ok'}
