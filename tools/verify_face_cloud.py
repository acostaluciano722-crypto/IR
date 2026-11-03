"""Negative end-to-end facial-policy check; never enrolls a human or keeps data."""

import json
import secrets
import struct
import uuid
import zlib

from verify_supabase_cloud import api, request_supabase
from coredata.models import FaceEnrollment, PassengerProfile, SupabaseIdentity, UserProfilePhoto, Usuario
from django.db import connection


def multipart(fields, images, boundary):
    parts = []
    for name, value in fields.items():
        parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode())
    for name, value in images.items():
        parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="blank.png"\r\nContent-Type: image/png\r\n\r\n').encode() + value + b'\r\n')
    return b''.join(parts) + f'--{boundary}--\r\n'.encode()


def blank_png():
    """Generate a valid synthetic white RGB image using only the standard library."""
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    pixels = (b'\0' + b'\xff\xff\xff' * 256) * 256
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def run():
    identity = uuid.uuid4()
    auth_id = str(identity)
    email = f'ir-face-check-{identity.hex}@example.test'
    password = secrets.token_urlsafe(32)
    baseline = Usuario.objects.count()
    created = False
    report = {}
    try:
        request_supabase('/auth/v1/admin/users', method='POST', admin=True, body={
            'id': auth_id, 'email': email, 'password': password, 'email_confirm': True,
        })
        created = True
        session = request_supabase('/auth/v1/token?grant_type=password', method='POST', body={'email': email, 'password': password})
        token = session['access_token']
        status, _ = api('auth/profile/', token=token, method='POST', body={
            'name': 'Comprobacion temporal IR', 'phone': 'face-' + identity.hex[:12], 'role': 'passenger',
        })
        assert status == 201, f'Onboarding HTTP {status}'
        status, policy = api('profile/face/', token=token)
        assert status == 200 and policy['required'] and policy['available'], f'Facial policy HTTP {status}'
        assert policy['verification_due'] and not policy['enrolled']
        report['cloud_policy_required_and_service_available'] = True
        status, denied = api('rides/', token=token)
        assert status == 403 and denied['code'] == 'face_verification_required', f'Transport gate HTTP {status}'
        report['transport_protected_before_enrollment'] = True
        status, challenge = api('profile/face/challenge/', token=token, method='POST', body={'purpose': 'enroll'})
        assert status == 200
        image = blank_png()
        boundary = 'IRFaceCheck' + identity.hex
        body = multipart({
            'consent': 'true', 'consent_version': policy['consent_version'],
            'challenge_token': challenge['challenge_token'],
        }, {'document': image, 'selfie': image}, boundary)
        status, rejected = api('profile/face/enroll/', token=token, method='POST', raw=body, content_type=f'multipart/form-data; boundary={boundary}')
        assert status == 422 and rejected['code'] == 'document_face_not_found', f'Blank image rejection HTTP {status}'
        report['real_deepface_rejects_document_without_face'] = True
        status, replay = api('profile/face/enroll/', token=token, method='POST', raw=body, content_type=f'multipart/form-data; boundary={boundary}')
        assert status == 400 and replay['code'] == 'invalid_challenge', f'Challenge replay HTTP {status}'
        assert not FaceEnrollment.objects.filter(user_id=identity).exists()
        assert not UserProfilePhoto.objects.filter(user_id=identity).exists()
        report['one_use_challenge_and_no_failed_enrollment_saved'] = True
        with connection.cursor() as cursor:
            cursor.execute("SELECT relrowsecurity FROM pg_class JOIN pg_namespace ON pg_namespace.oid = relnamespace WHERE nspname = 'ir' AND relname = 'ir_face_enrollment'")
            assert cursor.fetchone() == (True,)
            cursor.execute("SELECT has_table_privilege('anon', 'ir.ir_face_enrollment', 'SELECT'), has_table_privilege('authenticated', 'ir.ir_face_enrollment', 'SELECT')")
            assert cursor.fetchone() == (False, False)
        report['hosted_templates_table_private_and_rls_enabled'] = True
        request_supabase('/auth/v1/logout', method='POST', token=token)
    finally:
        FaceEnrollment.objects.filter(user_id=identity).delete()
        for photo in UserProfilePhoto.objects.filter(user_id=identity):
            photo.image.delete(save=False)
            photo.delete()
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
