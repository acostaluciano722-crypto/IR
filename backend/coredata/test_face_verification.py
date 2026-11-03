import hashlib
import json
import tempfile
import uuid
from datetime import datetime, timedelta, timezone as datetime_timezone
from unittest.mock import patch
from zoneinfo import ZoneInfo

from cryptography.fernet import Fernet
from django.core.cache import cache
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, TestCase, override_settings
from django.utils import timezone

from coredata.authentication import SignedTokenAuthentication
from coredata.face_security import consume_challenge, create_challenge, decrypt_template, next_verification_date
from coredata.face_service import FaceError, analyze_face
from coredata.models import FaceEnrollment, PassengerProfile, UserProfilePhoto, Usuario


class FaceSecurityTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    def test_expiry_is_two_bogota_calendar_months_including_leap_and_utc_boundaries(self):
        bogota = ZoneInfo('America/Bogota')
        with timezone.override(bogota):
            for start, expected in [
                (datetime(2026, 12, 31, 22, tzinfo=bogota), datetime(2027, 2, 28, 22, tzinfo=bogota)),
                (datetime(2027, 12, 31, 22, tzinfo=bogota), datetime(2028, 2, 29, 22, tzinfo=bogota)),
                (datetime(2027, 1, 1, 3, tzinfo=datetime_timezone.utc), datetime(2027, 2, 28, 22, tzinfo=bogota)),
            ]:
                with self.subTest(start=start):
                    self.assertEqual(next_verification_date(start), expected)

    def test_challenges_are_bound_to_user_purpose_and_only_used_once(self):
        identity = uuid.uuid4()
        token = create_challenge(identity, 'enroll')
        for user, purpose in [(uuid.uuid4(), 'enroll'), (identity, 'verify')]:
            with self.assertRaises(FaceError):
                consume_challenge(token, user, purpose)
        consume_challenge(token, identity, 'enroll')
        with self.assertRaises(FaceError):
            consume_challenge(token, identity, 'enroll')

    @override_settings(FACE_SERVICE_URL='http://face-inference:5005', FACE_SERVICE_TOKEN='test-' * 8)
    @patch('coredata.face_service.urlopen')
    def test_service_error_and_invalid_output_never_become_verified(self, connection):
        connection.side_effect = TimeoutError()
        with self.assertRaises(FaceError) as unavailable:
            analyze_face(selfie=b'image', document=b'document')
        self.assertEqual(unavailable.exception.status_code, 503)
        connection.side_effect = None
        connection.return_value.__enter__.return_value.read.return_value = json.dumps({
            'verified': True, 'embedding': [0.1] * 128, 'document_embedding': [0.1] * 128,
            'crop': 'invalid', 'model': 'SFace', 'anti_spoofing': True,
        }).encode()
        with self.assertRaises(FaceError):
            analyze_face(selfie=b'image', document=b'document')


@override_settings(ALLOW_LEGACY_AUTH=True, FACE_VERIFICATION_REQUIRED=False)
class FaceApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.settings_override = override_settings(
            MEDIA_ROOT=self.directory.name, FACE_TEMPLATE_KEY=Fernet.generate_key().decode(),
            STORAGES={'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
                      'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'}},
        )
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        self.user = Usuario.objects.create(id=uuid.uuid4(), correo='face-check@example.test',
            nombres='Prueba', rol='passenger', estado='active', contrasena_hash='!')
        PassengerProfile.objects.create(id=uuid.uuid4(), user=self.user, points=17, total_rides=0, rating=0, rating_count=0)
        self.client.defaults['HTTP_AUTHORIZATION'] = 'Token ' + SignedTokenAuthentication.signer.sign(str(self.user.pk))
        self.result = {'verified': True, 'crop_bytes': b'\xff\xd8\xff' + b'avatar',
                       'embedding': [0.2] * 128, 'document_embedding': [0.1] * 128}
        self.analyze_patch = patch('coredata.face_views.analyze_face', return_value=self.result)
        self.analyze_mock = self.analyze_patch.start()
        self.addCleanup(self.analyze_patch.stop)
        self.health_patch = patch('coredata.face_views.face_service_available', return_value=True)
        self.health_patch.start()
        self.addCleanup(self.health_patch.stop)

    def capture(self, purpose='enroll', *, content=b'capture-one'):
        challenge = self.client.post('/api/profile/face/challenge/', {'purpose': purpose}, content_type='application/json')
        self.assertEqual(challenge.status_code, 200)
        data = {'selfie': SimpleUploadedFile('selfie.jpg', b'\xff\xd8\xff' + content),
                'challenge_token': challenge.json()['challenge_token']}
        if purpose == 'enroll':
            data.update({'document': SimpleUploadedFile('document.jpg', b'\xff\xd8\xff' + b'document'),
                         'consent': 'true', 'consent_version': '2026-11-03-v2'})
        return data

    def enroll(self):
        response = self.client.post('/api/profile/face/enroll/', self.capture())
        self.assertEqual(response.status_code, 201, response.content)
        return FaceEnrollment.objects.get(user=self.user)

    def test_requires_authenticated_user_and_explicit_current_consent(self):
        data = self.capture()
        data['consent'] = 'false'
        response = self.client.post('/api/profile/face/enroll/', data)
        self.assertEqual(response.status_code, 400)
        self.assertFalse(FaceEnrollment.objects.exists())
        self.analyze_mock.assert_not_called()
        self.client.defaults.clear()
        self.assertEqual(self.client.get('/api/profile/face/').status_code, 401)

    def test_initial_document_mismatch_does_not_create_profile_or_reference(self):
        self.analyze_mock.return_value = {'verified': False}
        response = self.client.post('/api/profile/face/enroll/', self.capture())
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()['code'], 'face_mismatch')
        self.assertFalse(FaceEnrollment.objects.exists())
        self.assertFalse(UserProfilePhoto.objects.exists())

    def test_matched_enrollment_encrypts_templates_and_saves_only_cropped_avatar(self):
        record = self.enroll()
        protected = decrypt_template(record.encrypted_template)
        self.assertEqual(protected['document'], [0.1] * 128)
        self.assertEqual(protected['selfies'], [[0.2] * 128])
        self.assertNotIn(b'document', bytes(record.encrypted_template))
        self.assertTrue(default_storage.exists(record.avatar_name))
        self.assertEqual(UserProfilePhoto.objects.get(user_id=self.user.pk).image.name, record.avatar_name)
        status = self.client.get('/api/profile/face/').json()
        self.assertEqual(status['state'], 'verified')
        self.assertNotIn('document', status)
        self.assertNotIn('embedding', status)
        self.assertEqual(PassengerProfile.objects.get(user=self.user).points, 17)

    def test_repeat_selfie_is_rejected_without_calling_inference_again(self):
        self.enroll()
        self.analyze_mock.reset_mock()
        response = self.client.post('/api/profile/face/verify/', self.capture('verify'))
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()['code'], 'selfie_replayed')
        self.analyze_mock.assert_not_called()

    def test_derived_avatar_cannot_be_replaced_by_an_unverified_gallery_upload(self):
        record = self.enroll()
        response = self.client.post('/api/profile/photo/', {
            'photo': SimpleUploadedFile('other.jpg', b'\xff\xd8\xffunverified', content_type='image/jpeg'),
        })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()['code'], 'verified_selfie_required')
        self.assertEqual(UserProfilePhoto.objects.get(user_id=self.user.pk).image.name, record.avatar_name)

    def test_failed_recheck_preserves_due_date_and_success_keeps_only_recent_templates(self):
        record = self.enroll()
        previous = record.last_verified_at
        self.analyze_mock.return_value = {'verified': False}
        response = self.client.post('/api/profile/face/verify/', self.capture('verify', content=b'non-match'))
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['verified'])
        record.refresh_from_db()
        self.assertEqual(record.last_verified_at, previous)
        self.analyze_mock.return_value = self.result
        for index in range(4):
            cache.clear()
            response = self.client.post('/api/profile/face/verify/', self.capture('verify', content=f'fresh-{index}'.encode()))
            self.assertEqual(response.status_code, 200, response.content)
            self.assertTrue(response.json()['verified'])
        record.refresh_from_db()
        self.assertEqual(len(decrypt_template(record.encrypted_template)['selfies']), 3)

    def test_own_user_only_and_revocation_removes_current_derived_avatar(self):
        other = Usuario.objects.create(id=uuid.uuid4(), nombres='Otra', estado='active')
        data = self.capture()
        data['user_id'] = str(other.pk)
        self.assertEqual(self.client.post('/api/profile/face/enroll/', data).status_code, 201)
        self.assertFalse(FaceEnrollment.objects.filter(user=other).exists())
        record = FaceEnrollment.objects.get(user=self.user)
        avatar = record.avatar_name
        response = self.client.delete('/api/profile/face/')
        self.assertEqual(response.status_code, 204)
        self.assertFalse(FaceEnrollment.objects.exists())
        self.assertFalse(UserProfilePhoto.objects.filter(user_id=self.user.pk).exists())
        self.assertFalse(default_storage.exists(avatar))

    @override_settings(FACE_VERIFICATION_REQUIRED=True)
    def test_server_gate_blocks_business_before_enrollment_and_after_due_date(self):
        self.assertEqual(self.client.get('/api/passenger/me/').status_code, 403)
        self.assertEqual(self.client.get('/api/auth/me/').status_code, 200)
        self.assertEqual(self.client.get('/api/profile/face/').status_code, 200)
        record = self.enroll()
        self.assertEqual(self.client.get('/api/passenger/me/').status_code, 200)
        record.verification_due_at = timezone.now() - timedelta(seconds=1)
        record.save(update_fields=['verification_due_at'])
        response = self.client.get('/api/passenger/me/')
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()['code'], 'face_verification_required')
        self.assertEqual(self.client.get('/api/profile/face/').json()['state'], 'due')
