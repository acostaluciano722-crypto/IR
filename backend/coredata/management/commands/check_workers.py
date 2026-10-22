import json

from celery.exceptions import CeleryError
from django.core.management.base import BaseCommand, CommandError
from kombu.exceptions import KombuError
from redis.exceptions import RedisError

from coredata.tasks import infrastructure_probe


class Command(BaseCommand):
    help = 'Envia una tarea real a Celery y comprueba PostgreSQL, Redis y el resultado.'

    def handle(self, *args, **options):
        try:
            result = infrastructure_probe.apply_async(retry=False)
            report = result.get(timeout=15)
            result.forget()
        except (CeleryError, KombuError, RedisError, OSError, RuntimeError) as error:
            raise CommandError('No se pudo completar la tarea de prueba en Celery.') from error
        self.stdout.write(json.dumps(report))
