from django.contrib.auth.models import User
from django.urls import reverse
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from passengers.models import AccountProfile, Ride
from .models import DriverProfile, RideOffer


class RideOfferFlowTests(APITestCase):
	def setUp(self):
		self.passenger = User.objects.create_user('passenger', password='password123')
		AccountProfile.objects.create(user=self.passenger, role=AccountProfile.Role.PASSENGER)
		self.driver = User.objects.create_user('driver', password='password123')
		AccountProfile.objects.create(user=self.driver, role=AccountProfile.Role.DRIVER)
		DriverProfile.objects.create(
			user=self.driver,
			status=DriverProfile.Status.AVAILABLE,
			wallet_balance=100000,
		)
		self.ride = Ride.objects.create(
			passenger=self.passenger,
			origin='Origen',
			destination='Destino',
			offer_amount=12000,
			estimated_price=15000,
			status=Ride.Status.SEARCHING,
		)

	def authenticate(self, user):
		self.client.credentials(HTTP_AUTHORIZATION=f'Token {Token.objects.create(user=user).key}')

	def test_driver_accepts_original_price_as_pending_offer(self):
		self.authenticate(self.driver)

		response = self.client.post(reverse('driver-ride-accept', args=[self.ride.id]))

		self.assertEqual(response.status_code, 201)
		offer = RideOffer.objects.get(ride=self.ride, driver=self.driver)
		self.assertEqual(offer.amount, 12000)
		self.assertEqual(offer.status, RideOffer.Status.PENDING)
		self.ride.refresh_from_db()
		self.assertEqual(self.ride.status, Ride.Status.NEGOTIATING)

	def test_passenger_selects_offer_and_sets_final_fare(self):
		offer = RideOffer.objects.create(
			ride=self.ride,
			driver=self.driver,
			amount=13500,
		)
		self.authenticate(self.passenger)

		response = self.client.post(reverse('select-ride-offer', args=[self.ride.id, offer.id]))

		self.assertEqual(response.status_code, 200)
		self.ride.refresh_from_db()
		offer.refresh_from_db()
		self.assertEqual(self.ride.status, Ride.Status.ACCEPTED)
		self.assertEqual(self.ride.driver_id, self.driver.id)
		self.assertEqual(self.ride.final_fare, 13500)
		self.assertEqual(len(self.ride.pickup_code), 6)
		self.assertEqual(offer.status, RideOffer.Status.ACCEPTED)

	def test_driver_must_verify_passenger_code_before_starting(self):
		offer = RideOffer.objects.create(
			ride=self.ride,
			driver=self.driver,
			amount=13500,
		)
		self.authenticate(self.passenger)
		self.client.post(reverse('select-ride-offer', args=[self.ride.id, offer.id]))
		self.ride.refresh_from_db()
		self.authenticate(self.driver)

		invalid = self.client.post(
			reverse('driver-ride-verify-code', args=[self.ride.id]),
			{'code': 'XXXXXX'},
			format='json',
		)
		self.assertEqual(invalid.status_code, 400)
		self.ride.refresh_from_db()
		self.assertEqual(self.ride.status, Ride.Status.ACCEPTED)

		valid = self.client.post(
			reverse('driver-ride-verify-code', args=[self.ride.id]),
			{'code': self.ride.pickup_code},
			format='json',
		)
		self.assertEqual(valid.status_code, 200)
		self.ride.refresh_from_db()
		self.assertEqual(self.ride.status, Ride.Status.EN_ROUTE)

	def test_each_party_can_update_location_and_distance_is_returned(self):
		self.authenticate(self.passenger)
		passenger_response = self.client.post(
			reverse('ride-location', args=[self.ride.id]),
			{'latitude': 10.400000, 'longitude': -75.500000},
			format='json',
		)
		self.assertEqual(passenger_response.status_code, 200)

		self.ride.driver = self.driver
		self.ride.status = Ride.Status.ACCEPTED
		self.ride.save(update_fields=['driver', 'status'])
		self.authenticate(self.driver)
		driver_response = self.client.post(
			reverse('ride-location', args=[self.ride.id]),
			{'latitude': 10.410000, 'longitude': -75.500000},
			format='json',
		)

		self.assertEqual(driver_response.status_code, 200)
		self.assertEqual(float(driver_response.data['passenger_lat']), 10.4)
		self.assertEqual(float(driver_response.data['driver_lat']), 10.41)
		self.assertGreater(driver_response.data['live_distance_km'], 0)

	def test_cancelling_assigned_ride_releases_driver_reservation(self):
		self.ride.driver = self.driver
		self.ride.final_fare = 25000
		self.ride.status = Ride.Status.ACCEPTED
		self.ride.save(update_fields=['driver', 'final_fare', 'status'])
		profile = DriverProfile.objects.get(user=self.driver)
		profile.status = DriverProfile.Status.RESERVED_FOR_TRIP
		profile.reserved_balance = 2500
		profile.save(update_fields=['status', 'reserved_balance'])
		self.authenticate(self.passenger)

		response = self.client.post(reverse('cancel-ride', args=[self.ride.id]))

		self.assertEqual(response.status_code, 200)
		profile.refresh_from_db()
		self.assertEqual(profile.status, DriverProfile.Status.AVAILABLE)
		self.assertEqual(profile.reserved_balance, 0)
