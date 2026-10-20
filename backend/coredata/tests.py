from django.test import SimpleTestCase, TestCase
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.test import APIRequestFactory

from coredata.authentication import SignedTokenAuthentication
from coredata.serializers import DriverStatusSerializer, RideCreateSerializer, WalletRechargeSerializer
from coredata.models import DriverProfile, PassengerProfile, Usuario, Vehicle


class RegistrationPersistenceTests(TestCase):
    def register(self, role):
        return self.client.post('/api/auth/register/', {
            'name': 'Prueba Persistencia', 'identifier': f'{role}@example.test',
            'phone': '3000000000', 'role': role, 'password': 'Test-password-123',
            'document_number': '123456789', 'vehicle_type': 'moto',
            'vehicle_plate': 'abc123', 'vehicle_brand': 'Marca prueba', 'vehicle_color': 'Negro',
        }, content_type='application/json')

    def test_passenger_registration_and_login_use_saved_profile(self):
        response = self.register('passenger')
        self.assertEqual(response.status_code, 201, response.content)
        user = Usuario.objects.get(correo='passenger@example.test')
        self.assertTrue(user.check_password('Test-password-123'))
        self.assertEqual(user.celular, '3000000000')
        self.assertTrue(PassengerProfile.objects.filter(user=user).exists())
        login = self.client.post('/api/auth/login/', {
            'username': user.correo, 'password': 'Test-password-123',
        }, content_type='application/json')
        self.assertEqual(login.status_code, 200)
        self.assertEqual(login.json()['user']['id'], str(user.pk))

    def test_driver_registration_saves_profile_and_vehicle(self):
        response = self.register('driver')
        self.assertEqual(response.status_code, 201, response.content)
        user = Usuario.objects.get(correo='driver@example.test')
        profile = DriverProfile.objects.get(user=user)
        self.assertEqual(profile.document_number, '123456789')
        vehicle = Vehicle.objects.get(driver=profile)
        self.assertEqual(vehicle.plate, 'ABC123')
        self.assertEqual(vehicle.brand_model, 'Marca prueba')
        self.assertEqual(vehicle.category, 'moto')
        self.assertEqual(vehicle.color, 'Negro')

    def test_duplicate_registration_does_not_create_another_profile(self):
        self.assertEqual(self.register('passenger').status_code, 201)
        self.assertEqual(self.register('passenger').status_code, 400)
        self.assertEqual(Usuario.objects.count(), 1)
        self.assertEqual(PassengerProfile.objects.count(), 1)


class RideCreateSerializerTests(SimpleTestCase):
    def payload(self):
        return {
            'origin': ' Origen ',
            'destination': ' Destino ',
            'vehicle_type': 'economy',
            'offer_amount': 15000,
            'estimated_price': 18000,
            'origin_lat': 10.4,
            'origin_lng': -75.5,
            'destination_lat': 10.41,
            'destination_lng': -75.51,
            'distance_km': 2.1,
            'duration_minutes': 8,
        }

    def test_validates_and_trims_address_labels(self):
        serializer = RideCreateSerializer(data=self.payload())

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data['origin'], 'Origen')
        self.assertEqual(serializer.validated_data['destination'], 'Destino')

    def test_rejects_out_of_range_coordinates(self):
        payload = self.payload()
        payload['origin_lat'] = 91
        serializer = RideCreateSerializer(data=payload)

        self.assertFalse(serializer.is_valid())
        self.assertIn('origin_lat', serializer.errors)


class RequestValidationTests(SimpleTestCase):
    def test_driver_can_only_select_device_statuses(self):
        serializer = DriverStatusSerializer(data={'status': 'available'})
        self.assertTrue(serializer.is_valid(), serializer.errors)

        serializer = DriverStatusSerializer(data={'status': 'restricted'})
        self.assertFalse(serializer.is_valid())

    def test_wallet_recharge_has_minimum_amount(self):
        serializer = WalletRechargeSerializer(data={'amount': 4999})
        self.assertFalse(serializer.is_valid())

        serializer = WalletRechargeSerializer(data={'amount': 5000})
        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_rejects_malformed_signed_token(self):
        request = APIRequestFactory().get('/', HTTP_AUTHORIZATION='Token invalid')

        with self.assertRaises(AuthenticationFailed):
            SignedTokenAuthentication().authenticate(request)
