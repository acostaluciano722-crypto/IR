from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.conf import settings
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from html import unescape
from math import atan2, cos, radians, sin, sqrt
import re
import secrets
from datetime import timedelta
from django.utils import timezone
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AccountProfile, PassengerProfile, Ride


def decode_polyline(encoded):
    points = []
    index = latitude = longitude = 0
    while index < len(encoded):
        result = shift = 0
        while True:
            byte = ord(encoded[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20:
                break
        latitude += ~(result >> 1) if result & 1 else result >> 1
        result = shift = 0
        while True:
            byte = ord(encoded[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20:
                break
        longitude += ~(result >> 1) if result & 1 else result >> 1
        points.append({'lat': latitude / 100000, 'lng': longitude / 100000})
    return points


def reverse_location_label(latitude, longitude):
    try:
        if settings.GOOGLE_MAPS_API_KEY:
            params = urlencode({
                'latlng': f'{latitude},{longitude}',
                'language': 'es',
                'region': 'co',
                'key': settings.GOOGLE_MAPS_API_KEY,
            })
            request = Request(f'https://maps.googleapis.com/maps/api/geocode/json?{params}')
        else:
            params = urlencode({
                'format': 'jsonv2',
                'lat': latitude,
                'lon': longitude,
                'zoom': 18,
                'addressdetails': 1,
            })
            request = Request(
                f'https://nominatim.openstreetmap.org/reverse?{params}',
                headers={'User-Agent': 'IR-mobility-app/1.0'},
            )
        with urlopen(request, timeout=4) as response:
            import json
            data = json.loads(response.read().decode('utf-8'))
        if settings.GOOGLE_MAPS_API_KEY:
            result = data.get('results', [{}])[0]
            return result.get('formatted_address') or 'Ubicación actual'
        return data.get('display_name') or 'Ubicación actual'
    except (URLError, TimeoutError, ValueError, IndexError):
        return 'Ubicación actual'


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)


class RegisterSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    identifier = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=20)
    role = serializers.ChoiceField(choices=AccountProfile.Role.choices)
    password = serializers.CharField(write_only=True, min_length=8)
    document_number = serializers.CharField(max_length=40, required=False, allow_blank=True)
    vehicle_type = serializers.CharField(max_length=30, required=False, allow_blank=True)
    vehicle_plate = serializers.CharField(max_length=12, required=False, allow_blank=True)


class RideSerializer(serializers.ModelSerializer):
    offers = serializers.SerializerMethodField()
    passenger_name = serializers.SerializerMethodField()
    passenger_lat = serializers.FloatField(read_only=True, allow_null=True)
    passenger_lng = serializers.FloatField(read_only=True, allow_null=True)
    driver_lat = serializers.FloatField(read_only=True, allow_null=True)
    driver_lng = serializers.FloatField(read_only=True, allow_null=True)
    driver_name = serializers.SerializerMethodField()
    driver_vehicle_type = serializers.SerializerMethodField()
    driver_vehicle_brand = serializers.SerializerMethodField()
    driver_vehicle_color = serializers.SerializerMethodField()
    driver_vehicle_plate = serializers.SerializerMethodField()

    class Meta:
        model = Ride
        fields = ['id', 'origin', 'destination', 'origin_lat', 'origin_lng', 'destination_lat', 'destination_lng', 'passenger_lat', 'passenger_lng', 'driver_lat', 'driver_lng', 'passenger_location_label', 'driver_location_label', 'live_distance_km', 'distance_km', 'duration_minutes', 'vehicle_type', 'offer_amount', 'estimated_price', 'final_fare', 'status', 'passenger_name', 'driver_name', 'driver_vehicle_type', 'driver_vehicle_brand', 'driver_vehicle_color', 'driver_vehicle_plate', 'pickup_code', 'passenger_rating', 'driver_rating', 'offers', 'created_at']
        read_only_fields = ['id', 'status', 'final_fare', 'passenger_name', 'offers', 'created_at']

    def validate_offer_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError('La propuesta debe ser mayor que cero.')
        return value

    def get_passenger_name(self, obj):
        return obj.passenger.get_full_name() or obj.passenger.username

    def _driver_profile(self, obj):
        if not obj.driver_id:
            return None
        return AccountProfile.objects.filter(user_id=obj.driver_id).first()

    def get_driver_name(self, obj):
        return (obj.driver.get_full_name() or obj.driver.username) if obj.driver_id else None

    def get_driver_vehicle_type(self, obj):
        profile = self._driver_profile(obj)
        return profile.vehicle_type if profile and profile.vehicle_type else None

    def get_driver_vehicle_brand(self, obj):
        profile = self._driver_profile(obj)
        return profile.vehicle_brand if profile and profile.vehicle_brand else None

    def get_driver_vehicle_color(self, obj):
        profile = self._driver_profile(obj)
        return profile.vehicle_color if profile and profile.vehicle_color else None

    def get_driver_vehicle_plate(self, obj):
        profile = self._driver_profile(obj)
        return profile.vehicle_plate if profile and profile.vehicle_plate else None

    def get_offers(self, obj):
        return [
            {
                'id': offer.id,
                'amount': offer.amount,
                'status': offer.status,
                'driver_id': offer.driver_id,
                'driver_name': offer.driver.get_full_name() or offer.driver.username,
                'created_at': offer.created_at,
            }
            for offer in obj.offers.select_related('driver').all()
        ]

    live_distance_km = serializers.SerializerMethodField()

    def get_live_distance_km(self, obj):
        if None in (obj.passenger_lat, obj.passenger_lng, obj.driver_lat, obj.driver_lng):
            return None
        latitude_delta = radians(float(obj.driver_lat) - float(obj.passenger_lat))
        longitude_delta = radians(float(obj.driver_lng) - float(obj.passenger_lng))
        haversine = sin(latitude_delta / 2) ** 2 + cos(radians(float(obj.passenger_lat))) * cos(radians(float(obj.driver_lat))) * sin(longitude_delta / 2) ** 2
        return round(6371 * 2 * atan2(sqrt(haversine), sqrt(1 - haversine)), 2)


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = authenticate(**serializer.validated_data)
        if not user:
            return Response({'detail': 'Credenciales invalidas.'}, status=status.HTTP_401_UNAUTHORIZED)
        account, _ = AccountProfile.objects.get_or_create(user=user)
        profile, _ = PassengerProfile.objects.get_or_create(user=user)
        driver_profile = None
        if account.role == AccountProfile.Role.DRIVER:
            from drivers.models import DriverProfile
            driver_profile, _ = DriverProfile.objects.get_or_create(user=user)
        token, _ = Token.objects.get_or_create(user=user)
        return Response({
            'token': token.key,
            'user': {
                'id': user.id,
                'name': user.get_full_name() or user.username,
                'username': user.username,
                'role': account.role,
                'points': driver_profile.points if driver_profile else profile.points,
                'tier': driver_profile.tier if driver_profile else profile.tier,
            },
        })


class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        username = data['identifier'].strip().lower()
        if User.objects.filter(username=username).exists():
            return Response({'detail': 'Ya existe una cuenta con ese correo o usuario.'}, status=status.HTTP_409_CONFLICT)
        user = User.objects.create_user(username=username, password=data['password'])
        names = data['name'].strip().split(' ', 1)
        user.first_name = names[0]
        user.last_name = names[1] if len(names) > 1 else ''
        user.save(update_fields=['first_name', 'last_name'])
        AccountProfile.objects.create(
            user=user,
            role=data['role'],
            phone=data['phone'],
            document_number=data.get('document_number', ''),
            vehicle_type=data.get('vehicle_type', ''),
            vehicle_plate=data.get('vehicle_plate', '').upper(),
        )
        profile, _ = PassengerProfile.objects.get_or_create(user=user)
        if data['role'] == AccountProfile.Role.DRIVER:
            from drivers.models import DriverProfile
            driver_profile, _ = DriverProfile.objects.get_or_create(user=user)
        else:
            driver_profile = None
        token, _ = Token.objects.get_or_create(user=user)
        return Response({'token': token.key, 'user': {
            'id': user.id,
            'name': user.get_full_name() or user.username,
            'username': user.username,
            'role': data['role'],
            'points': driver_profile.points if driver_profile else profile.points,
            'tier': driver_profile.tier if driver_profile else profile.tier,
        }}, status=status.HTTP_201_CREATED)


class PassengerMeView(APIView):
    def get(self, request):
        profile, _ = PassengerProfile.objects.get_or_create(user=request.user)
        return Response({
            'name': request.user.get_full_name() or request.user.username,
            'points': profile.points,
            'tier': profile.tier,
        })


class PlaceSearchView(APIView):
    def get(self, request):
        query = request.query_params.get('input', '').strip()
        if not query:
            return Response({'predictions': []})
        if not settings.GOOGLE_MAPS_API_KEY:
            return Response({'detail': 'Configura GOOGLE_MAPS_API_KEY en el entorno del backend.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        params = urlencode({
            'input': query,
            'language': 'es',
            'components': 'country:co',
            'key': settings.GOOGLE_MAPS_API_KEY,
        })
        request = Request(f'https://maps.googleapis.com/maps/api/place/autocomplete/json?{params}')
        try:
            with urlopen(request, timeout=8) as response:
                import json
                data = json.loads(response.read().decode('utf-8'))
        except (URLError, TimeoutError):
            return Response({'detail': 'No fue posible conectar con Google Places.'}, status=status.HTTP_502_BAD_GATEWAY)
        if data.get('status') not in ('OK', 'ZERO_RESULTS'):
            return Response({'detail': data.get('error_message', 'Google Places no respondió correctamente.')}, status=status.HTTP_502_BAD_GATEWAY)
        return Response({'predictions': [
            {'description': item['description'], 'place_id': item['place_id']}
            for item in data.get('predictions', [])
        ]})


class PlaceDetailsView(APIView):
    def get(self, request):
        place_id = request.query_params.get('place_id', '').strip()
        if not place_id:
            return Response({'detail': 'place_id es obligatorio.'}, status=status.HTTP_400_BAD_REQUEST)
        if not settings.GOOGLE_MAPS_API_KEY:
            return Response({'detail': 'Configura GOOGLE_MAPS_API_KEY en el entorno del backend.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        params = urlencode({'place_id': place_id, 'fields': 'name,formatted_address,geometry', 'language': 'es', 'key': settings.GOOGLE_MAPS_API_KEY})
        try:
            with urlopen(Request(f'https://maps.googleapis.com/maps/api/place/details/json?{params}'), timeout=8) as response:
                import json
                data = json.loads(response.read().decode('utf-8'))
        except (URLError, TimeoutError):
            return Response({'detail': 'No fue posible conectar con Google Places.'}, status=status.HTTP_502_BAD_GATEWAY)
        if data.get('status') != 'OK':
            return Response({'detail': data.get('error_message', 'No fue posible obtener el lugar.')}, status=status.HTTP_502_BAD_GATEWAY)
        result = data['result']
        location = result['geometry']['location']
        return Response({'name': result.get('name', ''), 'address': result.get('formatted_address', ''), 'lat': location['lat'], 'lng': location['lng']})


class RouteEstimateView(APIView):
    def get(self, request):
        if not settings.GOOGLE_MAPS_API_KEY:
            return Response({'detail': 'Configura GOOGLE_MAPS_API_KEY en el entorno del backend.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        try:
            origin = f"{float(request.query_params['origin_lat'])},{float(request.query_params['origin_lng'])}"
            destination = f"{float(request.query_params['destination_lat'])},{float(request.query_params['destination_lng'])}"
        except (KeyError, TypeError, ValueError):
            return Response({'detail': 'Coordenadas de origen y destino son obligatorias.'}, status=status.HTTP_400_BAD_REQUEST)
        params = urlencode({'origin': origin, 'destination': destination, 'mode': 'driving', 'language': 'es', 'overview': 'full', 'key': settings.GOOGLE_MAPS_API_KEY})
        try:
            with urlopen(Request(f'https://maps.googleapis.com/maps/api/directions/json?{params}'), timeout=8) as response:
                import json
                data = json.loads(response.read().decode('utf-8'))
        except (URLError, TimeoutError):
            return Response({'detail': 'No fue posible conectar con Google Directions.'}, status=status.HTTP_502_BAD_GATEWAY)
        if data.get('status') != 'OK' or not data.get('routes'):
            return Response({'detail': data.get('error_message', 'No fue posible calcular la ruta.')}, status=status.HTTP_502_BAD_GATEWAY)
        leg = data['routes'][0]['legs'][0]
        polyline = data['routes'][0].get('overview_polyline', {}).get('points', '')
        route_points = decode_polyline(polyline) if polyline else []
        steps = [
            {
                'instruction': re.sub('<[^>]+>', '', unescape(step.get('html_instructions', ''))),
                'distance_text': step['distance']['text'],
                'duration_text': step['duration']['text'],
                'maneuver': step.get('maneuver', 'straight'),
                'polyline': step.get('polyline', {}).get('points', ''),
                'end_lat': step['end_location']['lat'],
                'end_lng': step['end_location']['lng'],
            }
            for step in leg.get('steps', [])
        ]
        return Response({
            'distance_km': round(leg['distance']['value'] / 1000, 2),
            'duration_minutes': round(leg['duration']['value'] / 60),
            'distance_text': leg['distance']['text'],
            'duration_text': leg['duration']['text'],
            'polyline': polyline,
            'route_points': route_points,
            'steps': steps,
        })


class NearbyPlacesView(APIView):
    def get(self, request):
        if not settings.GOOGLE_MAPS_API_KEY:
            return Response({'detail': 'Configura GOOGLE_MAPS_API_KEY en el entorno del backend.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        try:
            latitude = float(request.query_params['lat'])
            longitude = float(request.query_params['lng'])
        except (KeyError, TypeError, ValueError):
            return Response({'detail': 'lat y lng son obligatorios.'}, status=status.HTTP_400_BAD_REQUEST)
        params = urlencode({'location': f'{latitude},{longitude}', 'radius': 1800, 'type': 'point_of_interest', 'language': 'es', 'key': settings.GOOGLE_MAPS_API_KEY})
        try:
            with urlopen(Request(f'https://maps.googleapis.com/maps/api/place/nearbysearch/json?{params}'), timeout=8) as response:
                import json
                data = json.loads(response.read().decode('utf-8'))
        except (URLError, TimeoutError):
            return Response({'detail': 'No fue posible conectar con Google Places.'}, status=status.HTTP_502_BAD_GATEWAY)
        if data.get('status') not in ('OK', 'ZERO_RESULTS'):
            return Response({'detail': data.get('error_message', 'Google Places no respondió correctamente.')}, status=status.HTTP_502_BAD_GATEWAY)
        places = []
        for place in data.get('results', []):
            location = place['geometry']['location']
            latitude_delta = radians(location['lat'] - latitude)
            longitude_delta = radians(location['lng'] - longitude)
            haversine = sin(latitude_delta / 2) ** 2 + cos(radians(latitude)) * cos(radians(location['lat'])) * sin(longitude_delta / 2) ** 2
            distance_meters = 6371000 * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
            places.append({
                'place_id': place['place_id'],
                'name': place['name'],
                'vicinity': place.get('vicinity', ''),
                'lat': location['lat'],
                'lng': location['lng'],
                'distance_meters': round(distance_meters),
            })
        places.sort(key=lambda place: place['distance_meters'])
        return Response({'places': places[:5]})


class RideListCreateView(generics.ListCreateAPIView):
    serializer_class = RideSerializer

    def get_queryset(self):
        return Ride.objects.filter(passenger=self.request.user)

    def perform_create(self, serializer):
        role = AccountProfile.objects.filter(user=self.request.user).values_list('role', flat=True).first()
        if role != AccountProfile.Role.PASSENGER:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Solo los pasajeros pueden solicitar viajes.')
        serializer.save(passenger=self.request.user, status=Ride.Status.SEARCHING)


class RideOfferRejectView(APIView):
    def post(self, request, ride_id, offer_id):
        from drivers.models import RideOffer

        offer = get_object_or_404(
            RideOffer,
            id=offer_id,
            ride__id=ride_id,
            ride__passenger=request.user,
            status=RideOffer.Status.PENDING,
        )
        offer.status = RideOffer.Status.REJECTED
        offer.save(update_fields=['status'])
        return Response(RideSerializer(offer.ride).data)


class RideLocationView(APIView):
    def post(self, request, ride_id):
        ride = get_object_or_404(Ride, id=ride_id)
        if request.user.id not in {ride.passenger_id, ride.driver_id}:
            return Response({'detail': 'No puedes actualizar la ubicación de este viaje.'}, status=status.HTTP_403_FORBIDDEN)
        try:
            latitude = round(float(request.data['latitude']), 6)
            longitude = round(float(request.data['longitude']), 6)
        except (KeyError, TypeError, ValueError):
            return Response({'detail': 'latitude y longitude son obligatorias.'}, status=status.HTTP_400_BAD_REQUEST)
        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            return Response({'detail': 'Las coordenadas no son válidas.'}, status=status.HTTP_400_BAD_REQUEST)
        if request.user.id == ride.passenger_id:
            ride.passenger_lat = latitude
            ride.passenger_lng = longitude
            ride.passenger_location_label = reverse_location_label(latitude, longitude)
            update_fields = ['passenger_lat', 'passenger_lng', 'passenger_location_label']
        else:
            ride.driver_lat = latitude
            ride.driver_lng = longitude
            ride.driver_location_label = reverse_location_label(latitude, longitude)
            update_fields = ['driver_lat', 'driver_lng', 'driver_location_label']
        ride.save(update_fields=update_fields)
        return Response(RideSerializer(ride).data)


class RideOfferSelectView(APIView):
    def post(self, request, ride_id, offer_id):
        from drivers.models import DriverProfile, RideOffer

        with transaction.atomic():
            ride = get_object_or_404(
                Ride.objects.select_for_update(),
                id=ride_id,
                passenger=request.user,
            )
            offer = get_object_or_404(
                RideOffer.objects.select_for_update().select_related('driver'),
                id=offer_id,
                ride=ride,
                status=RideOffer.Status.PENDING,
            )
            if ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
                return Response({'detail': 'La solicitud ya no está disponible.'}, status=status.HTTP_409_CONFLICT)

            profile = DriverProfile.objects.select_for_update().get(user=offer.driver)
            required_reserve = (offer.amount + 9) // 10
            available = profile.wallet_balance - profile.reserved_balance
            if available < required_reserve:
                return Response({'detail': 'El conductor ya no tiene saldo suficiente para reservar este viaje.'}, status=status.HTTP_409_CONFLICT)

            profile.reserved_balance += required_reserve
            profile.status = DriverProfile.Status.RESERVED_FOR_TRIP
            profile.save(update_fields=['reserved_balance', 'status'])
            ride.driver = offer.driver
            ride.final_fare = offer.amount
            ride.pickup_code = secrets.token_hex(3).upper()
            ride.status = Ride.Status.ACCEPTED
            ride.save(update_fields=['driver', 'final_fare', 'pickup_code', 'status'])
            offer.status = RideOffer.Status.ACCEPTED
            offer.save(update_fields=['status'])
            ride.offers.exclude(id=offer.id).filter(status=RideOffer.Status.PENDING).update(status=RideOffer.Status.REJECTED)

        return Response(RideSerializer(ride).data)


class RideRatingView(APIView):
    def post(self, request, ride_id):
        ride = get_object_or_404(Ride, id=ride_id)
        if request.user.id not in {ride.passenger_id, ride.driver_id}:
            return Response({'detail': 'No puedes calificar este viaje.'}, status=status.HTTP_403_FORBIDDEN)
        try:
            rating = int(request.data.get('rating', 0))
        except (TypeError, ValueError):
            rating = 0
        if rating < 1 or rating > 5:
            return Response({'detail': 'La calificación debe estar entre 1 y 5 estrellas.'}, status=status.HTTP_400_BAD_REQUEST)
        if request.user.id == ride.passenger_id:
            if ride.passenger_rating is not None:
                return Response({'detail': 'Ya calificaste este viaje.'}, status=status.HTTP_409_CONFLICT)
            ride.passenger_rating = rating
            from drivers.models import DriverProfile
            profile = get_object_or_404(DriverProfile, user_id=ride.driver_id)
            profile.rating_sum += rating
            profile.rating_count += 1
            profile.save(update_fields=['rating_sum', 'rating_count'])
            update_fields = ['passenger_rating']
        else:
            if ride.driver_rating is not None:
                return Response({'detail': 'Ya calificaste este viaje.'}, status=status.HTTP_409_CONFLICT)
            ride.driver_rating = rating
            update_fields = ['driver_rating']
        ride.save(update_fields=update_fields)
        return Response(RideSerializer(ride).data)


class RideCancelView(APIView):
    def post(self, request, ride_id):
        from drivers.models import DriverProfile, RideOffer

        with transaction.atomic():
            ride = get_object_or_404(
                Ride.objects.select_for_update(),
                id=ride_id,
                passenger=request.user,
            )
            cancellable = {
                Ride.Status.SEARCHING,
                Ride.Status.REQUESTED,
                Ride.Status.NEGOTIATING,
                Ride.Status.ACCEPTED,
                Ride.Status.DRIVER_SELECTED,
                Ride.Status.EN_ROUTE,
                Ride.Status.ARRIVED,
            }
            if ride.status not in cancellable:
                return Response(
                    {'detail': 'Este viaje ya no se puede cancelar.'},
                    status=status.HTTP_409_CONFLICT,
                )
            ride.status = Ride.Status.CANCELLED
            ride.save(update_fields=['status'])
            RideOffer.objects.filter(
                ride=ride, status=RideOffer.Status.PENDING
            ).update(status=RideOffer.Status.REJECTED)
            if ride.driver_id:
                profile = DriverProfile.objects.select_for_update().get(user_id=ride.driver_id)
                reserved = ((ride.final_fare or ride.offer_amount or ride.estimated_price) + 9) // 10
                profile.reserved_balance = max(0, profile.reserved_balance - reserved)
                if profile.status == DriverProfile.Status.RESERVED_FOR_TRIP:
                    profile.status = DriverProfile.Status.AVAILABLE
                profile.save(update_fields=['reserved_balance', 'status'])

        return Response(RideSerializer(ride).data)
