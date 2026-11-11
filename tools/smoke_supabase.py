"""Exercise real Auth/Storage against the disposable LOCAL Supabase stack only."""

import json
import os
import secrets
import sys
import uuid
from pathlib import Path
from urllib.request import urlopen

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env.supabase.local', override=True)
if os.environ.get('SUPABASE_URL') != 'http://127.0.0.1:54321':
    raise SystemExit('Esta comprobacion solo admite el entorno local de Supabase.')
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

import django
django.setup()

from django.contrib.auth.hashers import make_password
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from coredata.models import PassengerProfile, SupabaseIdentity, Usuario
from coredata.supabase import SupabaseRequestError, request_supabase


def run():
    identity = uuid.uuid4()
    email = f'local-auth-{identity.hex}@example.test'
    password = secrets.token_urlsafe(32)
    user = Usuario.objects.create(id=identity, correo=email, nombres='Prueba local',
        celular=f'local-{identity.hex[:10]}', rol='passenger', estado='active',
        contrasena_hash=make_password(password))
    PassengerProfile.objects.create(id=uuid.uuid4(), user=user, points=17, total_rides=3, rating=0, rating_count=0)
    auth_id = str(identity)
    report = {}
    try:
        client = Client()
        with override_settings(ALLOWED_HOSTS=['testserver']):
            response = client.post('/api/auth/legacy-migrate/', {'username': email, 'password': password}, content_type='application/json')
            if response.status_code != 202:
                raise RuntimeError('Legacy migration: ' + str(response.status_code) + ' ' + response.content.decode())
            auth_id = str(SupabaseIdentity.objects.get(user=user).auth_user_id)
            user.refresh_from_db()
            assert not user.check_password(password)
            report['legacy_id_preserved'] = user.pk == identity
            try:
                request_supabase('/auth/v1/token?grant_type=password', method='POST', body={'email': email, 'password': password})
                raise RuntimeError('La cuenta accedio sin confirmar su correo.')
            except SupabaseRequestError as error:
                assert error.code == 'email_not_confirmed', error.code
            report['confirmation_required'] = True
            request_supabase(f'/auth/v1/admin/users/{auth_id}', method='PUT', admin=True, body={'email_confirm': True})
            session = request_supabase('/auth/v1/token?grant_type=password', method='POST', body={'email': email, 'password': password})
            headers = {'HTTP_AUTHORIZATION': 'Bearer ' + session['access_token']}
            response = client.get('/api/auth/me/', **headers)
            assert response.status_code == 200, response.content
            assert response.json()['points'] == 17
            report['bearer_and_points'] = 'ok'
            photo = (ROOT / 'frontend/assets/icons/google_g.png').read_bytes()
            response = client.post('/api/profile/photo/', {'photo': SimpleUploadedFile('probe.png', photo, content_type='image/png')}, **headers)
            assert response.status_code == 200, response.content
            with urlopen(response.json()['photo_url'], timeout=10) as download:
                assert download.read() == photo
            report['private_storage_signed_download'] = 'ok'
            assert client.delete('/api/profile/photo/', **headers).status_code == 204
            report['storage_delete'] = 'ok'
            refreshed = request_supabase('/auth/v1/token?grant_type=refresh_token', method='POST', body={'refresh_token': session['refresh_token']})
            assert refreshed.get('access_token')
            report['session_refresh'] = 'ok'
            request_supabase('/auth/v1/logout', method='POST', token=refreshed['access_token'])
            report['sign_out'] = 'ok'
    finally:
        from coredata.network import release_temporary_position
        release_temporary_position(user)
        PassengerProfile.objects.filter(user=user).delete()
        SupabaseIdentity.objects.filter(user=user).delete()
        Usuario.objects.filter(pk=user.pk).delete()
        try:
            request_supabase(f'/auth/v1/admin/users/{auth_id}', method='DELETE', admin=True)
        except SupabaseRequestError:
            pass
    print(json.dumps(report))


if __name__ == '__main__':
    run()
