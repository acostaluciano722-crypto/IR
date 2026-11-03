import mimetypes
from io import BytesIO
from urllib.parse import quote

from django.conf import settings
from django.core.files.base import File
from django.core.files.storage import Storage
from django.utils.deconstruct import deconstructible

from coredata.supabase import SupabaseRequestError, request_supabase


@deconstructible
class SupabaseStorage(Storage):
    """Private profile bucket; domain authorization stays in Django."""

    def _path(self, name):
        if name.startswith('/') or '..' in name.split('/') or '\\' in name:
            raise ValueError('Ruta de archivo no valida.')
        return quote(settings.SUPABASE_STORAGE_BUCKET, safe='') + '/' + quote(name, safe='/')

    def _save(self, name, content):
        mime = mimetypes.guess_type(name)[0] or 'application/octet-stream'
        request_supabase('/storage/v1/object/' + self._path(name), method='POST',
                         admin=True, raw=content.read(), content_type=mime)
        return name

    def _open(self, name, mode='rb'):
        payload = request_supabase('/storage/v1/object/authenticated/' + self._path(name),
                                   admin=True, return_bytes=True)
        return File(BytesIO(payload), name=name)

    def exists(self, name):
        try:
            request_supabase('/storage/v1/object/' + self._path(name), method='HEAD', admin=True)
            return True
        except SupabaseRequestError as error:
            if error.status in {400, 404}:
                return False
            raise

    def delete(self, name):
        self._path(name)
        request_supabase('/storage/v1/object/' + quote(settings.SUPABASE_STORAGE_BUCKET, safe=''),
                         method='DELETE', body={'prefixes': [name]}, admin=True)

    def url(self, name):
        try:
            result = request_supabase('/storage/v1/object/sign/' + self._path(name), method='POST',
                                      admin=True, body={'expiresIn': 3600})
        except SupabaseRequestError as error:
            if error.status in {400, 404}:
                raise FileNotFoundError(name) from None
            raise
        signed = result.get('signedURL')
        if not signed or not signed.startswith('/object/sign/'):
            raise ValueError('Supabase no devolvio una URL de archivo valida.')
        return settings.SUPABASE_URL + '/storage/v1' + signed
