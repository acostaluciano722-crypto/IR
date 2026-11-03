"""Verify the configured IR cloud project using one temporary account, without email."""

import json
import os
import secrets
import sys
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env', override=True)
if os.environ.get('SUPABASE_URL') != 'https://nligmbbebusjewxrghps.supabase.co':
    raise SystemExit('La comprobacion requiere el proyecto IR configurado.')
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

import django
django.setup()

from coredata.models import PassengerProfile, SupabaseIdentity, UserProfilePhoto, Usuario
from coredata.supabase import SupabaseRequestError, request_supabase


def api(path, *, token=None, method='GET', body=None, raw=None, content_type='application/json'):
    headers = {'Content-Type': content_type}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    payload = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    request = Request('http://127.0.0.1:8000/api/' + path, data=payload, headers=headers, method=method)
    try:
        response = urlopen(request, timeout=20)
    except HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, json.loads(data) if data and response.headers.get_content_type() == 'application/json' else {}


def run():
    identity = uuid.uuid4()
    auth_id = str(identity)
    email = f'ir-cloud-check-{identity.hex}@example.test'
    password = secrets.token_urlsafe(32)
    baseline = Usuario.objects.count()
    created = False
    report = {}
    try:
        request_supabase('/auth/v1/admin/users', method='POST', admin=True, body={
            'id': auth_id, 'email': email, 'password': password, 'email_confirm': False,
        })
        created = True
        try:
            request_supabase('/auth/v1/token?grant_type=password', method='POST', body={'email': email, 'password': password})
        except SupabaseRequestError as error:
            assert error.code == 'email_not_confirmed', 'Unexpected confirmation policy'
        else:
            raise RuntimeError('Auth allowed access without confirmed email.')
        report['confirmation_required'] = True
        request_supabase(f'/auth/v1/admin/users/{auth_id}', method='PUT', admin=True, body={'email_confirm': True})
        session = request_supabase('/auth/v1/token?grant_type=password', method='POST', body={'email': email, 'password': password})
        token = session['access_token']
        assert api('auth/me/', token=token)[0] == 409, 'Onboarding was not requested'
        status, profile = api('auth/profile/', token=token, method='POST', body={
            'name': 'Verificacion Supabase', 'phone': 'cloud-' + identity.hex[:12], 'role': 'passenger',
        })
        assert status == 201 and profile.get('id') == auth_id, f'Onboarding HTTP {status}'
        status, profile = api('auth/me/', token=token)
        assert status == 200 and profile['points'] == 0 and profile['role'] == 'passenger', f'Profile HTTP {status}'
        report['cloud_login_and_backend_onboarding'] = 'ok'
        assert api('rides/', token=token)[0] == 200, 'Ride history query failed'
        assert api('passenger/me/', token=token)[0] == 200, 'Passenger profile query failed'
        assert api('driver/nearby/?lat=4.65&lng=-74.09', token=token)[0] == 200, 'Nearby driver query failed'
        report['mobility_queries'] = 'ok'
        parts = token.split('.')
        parts[2] = ('B' if parts[2][0] == 'A' else 'A') + parts[2][1:]
        assert api('auth/me/', token='.'.join(parts))[0] == 401, 'Tampered JWT was accepted'
        report['tampered_jwt_rejected'] = True
        photo = (ROOT / 'frontend/assets/icons/google_g.png').read_bytes()
        boundary = 'IRPhoto' + identity.hex
        upload = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="photo"; filename="probe.png"\r\n'
            'Content-Type: image/png\r\n\r\n'
        ).encode() + photo + f'\r\n--{boundary}--\r\n'.encode()
        status, result = api('profile/photo/', token=token, method='POST', raw=upload, content_type=f'multipart/form-data; boundary={boundary}')
        assert status == 200, f'Photo upload HTTP {status}'
        with urlopen(result['photo_url'], timeout=20) as download:
            assert download.read() == photo, 'Signed download did not match the upload'
        assert api('profile/photo/', token=token, method='DELETE')[0] == 204, 'Photo deletion failed'
        report['private_storage_upload_download_delete'] = 'ok'
        try:
            request_supabase('/rest/v1/usuario?select=id_usuario')
        except SupabaseRequestError as error:
            assert error.status in {401, 403, 404}, 'Unexpected Data API response'
        else:
            raise RuntimeError('The business table is exposed through the public Data API.')
        report['business_tables_private'] = True
        refreshed = request_supabase('/auth/v1/token?grant_type=refresh_token', method='POST', body={'refresh_token': session['refresh_token']})
        assert api('auth/me/', token=refreshed['access_token'])[0] == 200, 'Refreshed session failed'
        request_supabase('/auth/v1/logout', method='POST', token=refreshed['access_token'])
        report['refresh_and_logout'] = 'ok'
        auth_settings = request_supabase('/auth/v1/settings')
        report['google_provider_enabled'] = auth_settings.get('external', {}).get('google', False)
    finally:
        for photo_record in UserProfilePhoto.objects.filter(user_id=identity):
            photo_record.image.delete(save=False)
            photo_record.delete()
        PassengerProfile.objects.filter(user_id=identity).delete()
        SupabaseIdentity.objects.filter(auth_user_id=identity).delete()
        Usuario.objects.filter(pk=identity).delete()
        if created:
            request_supabase(f'/auth/v1/admin/users/{auth_id}', method='DELETE', admin=True)
        assert Usuario.objects.count() == baseline, 'Temporary data cleanup failed'
    report['temporary_account_removed'] = True
    print(json.dumps(report))


if __name__ == '__main__':
    run()
