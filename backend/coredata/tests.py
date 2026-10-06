from django.test import SimpleTestCase
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.test import APIRequestFactory

from coredata.authentication import SignedTokenAuthentication
from coredata.serializers import DriverStatusSerializer, RideCreateSerializer, WalletRechargeSerializer


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