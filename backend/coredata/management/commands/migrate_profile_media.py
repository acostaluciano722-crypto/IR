import json
from pathlib import Path

from django.conf import settings
from django.core.files.base import File
from django.core.management.base import BaseCommand, CommandError

from coredata.models import UserProfilePhoto
from coredata.storage import SupabaseStorage


class Command(BaseCommand):
    help = 'Copia fotos locales al bucket privado sin alterar las rutas guardadas.'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true')

    def handle(self, *args, **options):
        root = Path(settings.MEDIA_ROOT).resolve()
        storage = SupabaseStorage()
        report = {'available': 0, 'missing': 0, 'uploaded': 0}
        photos = list(UserProfilePhoto.objects.exclude(image=''))
        for photo in photos:
            path = (root / photo.image.name).resolve()
            if not path.is_relative_to(root):
                raise CommandError('Una foto apunta fuera de MEDIA_ROOT.')
            if not path.is_file():
                report['missing'] += 1
                continue
            report['available'] += 1
            if options['apply'] and not storage.exists(photo.image.name):
                with path.open('rb') as source:
                    storage._save(photo.image.name, File(source))
                report['uploaded'] += 1
        self.stdout.write(json.dumps(report))
        if report['missing']:
            self.stderr.write('Hay fotos referenciadas cuyos archivos no existen en backend/media. Recuperalas o vuelvelas a subir.')
