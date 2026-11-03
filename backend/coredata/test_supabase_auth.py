import time
import uuid
from unittest.mock import patch

import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from django.contrib.auth.hashers import make_password
from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.exceptions import AuthenticationFailed

from coredata.models import PassengerProfile, SupabaseIdentity, Usuario
from coredata.supabase import verify_access_token


@override_settings(SUPABASE_AUTH_ENABLED=True, SUPABASE_URL='https://test.supabase.co',
                   SUPABASE_JWT_ISSUER='https://test.supabase.co/auth/v1')
class SupabaseJwtTests(SimpleTestCase):
    def setUp(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.claims = {
            'sub': str(uuid.uuid4()), 'aud': 'authenticated',
            'iss': 'https://test.supabase.co/auth/v1',
            'iat': int(time.time()), 'exp': int(time.time()) + 300,
            'role': 'authenticated', 'user_metadata': {'role': 'admin'},
        }

    def token(self, **changes):
        return jwt.encode({**self.claims, **changes}, self.key, algorithm='ES256', headers={'kid': 'test-key'})

    @patch('coredata.supabase.jwks_client')
    def test_valid_signature_is_verified_without_trusting_metadata(self, client):
        client.return_value.get_signing_key_from_jwt.return_value.key = self.key.public_key()
        self.assertEqual(verify_access_token(self.token())['role'], 'authenticated')

    @patch('coredata.supabase.jwks_client')
    def test_wrong_audience_issuer_and_expired_tokens_are_rejected(self, client):
        client.return_value.get_signing_key_from_jwt.return_value.key = self.key.public_key()
        for change in [{'aud': 'another-project'}, {'iss': 'https://evil.test'}, {'exp': 1}, {'is_anonymous': True}]:
            with self.subTest(change=change), self.assertRaises(AuthenticationFailed):
                verify_access_token(self.token(**change))

    @patch('coredata.supabase.jwks_client')
    def test_unsigned_tokens_never_fetch_a_signing_key(self, client):
        token = jwt.encode(self.claims, None, algorithm='none')
        with self.assertRaises(AuthenticationFailed):
            verify_access_token(token)
        client.assert_not_called()

    @patch('coredata.supabase.verified_auth_user')
    def test_legacy_hmac_token_is_checked_by_auth_server(self, get_user):
        get_user.return_value = {'id': self.claims['sub'], 'email': 'test@example.test', 'role': 'authenticated'}
        token = jwt.encode(self.claims, 'test-key-' * 8, algorithm='HS256')
        self.assertEqual(verify_access_token(token)['sub'], self.claims['sub'])
        get_user.assert_called_once_with(token)


@override_settings(SUPABASE_AUTH_ENABLED=True, ALLOW_LEGACY_AUTH=False,
                   SUPABASE_SECRET_KEY='test-server-key')
class SupabaseProfileTests(TestCase):
    def setUp(self):
        self.auth_id = str(uuid.uuid4())
        self.auth_user = {
            'id': self.auth_id, 'email': 'verified@example.test',
            'email_confirmed_at': '2026-10-23T00:00:00Z',
            'user_metadata': {'role': 'admin'},
        }
        self.claims_patch = patch('coredata.auth_views.verify_access_token', return_value={'sub': self.auth_id})
        self.user_patch = patch('coredata.auth_views.verified_auth_user', return_value=self.auth_user)
        self.claims_patch.start()
        self.user_patch.start()
        self.addCleanup(self.claims_patch.stop)
        self.addCleanup(self.user_patch.stop)

    def post(self, **changes):
        return self.client.post('/api/auth/profile/', {
            'name': 'Prueba Auth', 'phone': '3001234567', 'role': 'passenger', **changes,
        }, content_type='application/json', HTTP_AUTHORIZATION='Bearer verified-test-token')

    def test_verified_user_can_create_profile_and_role_cannot_change(self):
        self.assertEqual(self.post().status_code, 201)
        user = Usuario.objects.get(pk=self.auth_id)
        self.assertEqual(user.rol, 'passenger')
        self.assertFalse(user.check_password('anything'))
        self.assertTrue(SupabaseIdentity.objects.filter(pk=self.auth_id, user=user).exists())
        self.assertEqual(self.post(role='driver').status_code, 200)
        user.refresh_from_db()
        self.assertEqual(user.rol, 'passenger')
        self.assertEqual(PassengerProfile.objects.count(), 1)

    def test_admin_role_and_unconfirmed_email_are_rejected(self):
        self.assertEqual(self.post(role='admin').status_code, 400)
        self.auth_user['email_confirmed_at'] = None
        self.assertIn(self.post().status_code, {401, 403})
        self.assertEqual(Usuario.objects.count(), 0)

    def test_matching_email_does_not_silently_take_over_legacy_account(self):
        legacy = Usuario.objects.create(id=uuid.uuid4(), correo=self.auth_user['email'], celular='3000000001')
        self.assertEqual(self.post().status_code, 409)
        self.assertFalse(SupabaseIdentity.objects.filter(user=legacy).exists())

    def test_legacy_login_and_registration_cannot_mint_tokens(self):
        self.assertEqual(self.client.post('/api/auth/login/', {}).status_code, 410)
        self.assertEqual(self.client.post('/api/auth/register/', {}).status_code, 410)

    def test_verified_google_identity_requires_old_password_to_preserve_existing_account(self):
        user = Usuario.objects.create(id=uuid.uuid4(), correo=self.auth_user['email'],
                                      rol='passenger', estado='active', contrasena_hash=make_password('Previous-password-123'))
        PassengerProfile.objects.create(id=uuid.uuid4(), user=user, points=120, total_rides=4)
        bad = self.client.post('/api/auth/link-legacy/', {'password': 'wrong'}, content_type='application/json', HTTP_AUTHORIZATION='Bearer test')
        self.assertIn(bad.status_code, {401, 403})
        self.assertFalse(SupabaseIdentity.objects.filter(user=user).exists())
        response = self.client.post('/api/auth/link-legacy/', {'password': 'Previous-password-123'}, content_type='application/json', HTTP_AUTHORIZATION='Bearer test')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['id'], str(user.pk))
        self.assertEqual(response.json()['points'], 120)
        self.assertEqual(str(SupabaseIdentity.objects.get(user=user).auth_user_id), self.auth_id)

    @patch('coredata.auth_views.request_supabase')
    def test_legacy_password_migration_keeps_domain_id_and_requires_confirmation(self, api):
        user = Usuario.objects.create(id=uuid.uuid4(), correo='legacy@example.test',
                                      celular='3001234000', contrasena_hash=make_password('Legacy-password-123'), estado='active')
        api.side_effect = [{'id': str(user.pk)}, {}]
        response = self.client.post('/api/auth/legacy-migrate/', {
            'username': user.correo, 'password': 'Legacy-password-123',
        }, content_type='application/json')
        self.assertEqual(response.status_code, 202)
        self.assertEqual(SupabaseIdentity.objects.get(user=user).auth_user_id, user.pk)
        self.assertFalse(api.call_args_list[0].kwargs['body']['email_confirm'])
        user.refresh_from_db()
        self.assertFalse(user.check_password('Legacy-password-123'))
