"""Initialize only the HTTP service; workers reuse the same Django image."""

import os
import sys
import time


def serve():
    if not os.environ.get('DB_PASSWORD'):
        raise SystemExit('Falta DB_PASSWORD. Ejecuta run_docker.ps1 o configura .env.')

    import django
    from django.core.management import call_command
    from django.db import OperationalError, connections

    django.setup()
    for attempt in range(30):
        try:
            connections['default'].ensure_connection()
            break
        except OperationalError:
            if attempt == 29:
                raise
            print('Esperando PostgreSQL...', flush=True)
            time.sleep(2)

    call_command('migrate', interactive=False)
    call_command('check_database')
    call_command('collectstatic', interactive=False, verbosity=0)
    command = [
        'gunicorn', 'config.wsgi:application',
        '--bind', '0.0.0.0:8000',
        '--worker-class', 'gthread',
        '--workers', os.environ.get('GUNICORN_WORKERS', '2'),
        '--threads', os.environ.get('GUNICORN_THREADS', '4'),
        '--timeout', '60',
        '--access-logfile', '-',
        '--error-logfile', '-',
    ]
    os.execvp(command[0], command)


if __name__ == '__main__':
    if sys.argv[1:] == ['serve']:
        serve()
    elif sys.argv[1:]:
        os.execvp(sys.argv[1], sys.argv[1:])
    else:
        raise SystemExit('Falta el comando del contenedor.')
