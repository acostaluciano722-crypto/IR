import json
import re
import secrets
import uuid
from datetime import timedelta
from html import unescape
from math import atan2, cos, radians, sin, sqrt
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.db import connection, transaction
from django.db.models import F
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.core.signing import TimestampSigner
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from coredata.models import (
    DriverProfile,
    DriverTransaction,
    PassengerProfile,
    PointHistory,
    Ride,
    RideOffer,
    Usuario,
    Vehicle,
)
from coredata.serializers import (
    LoginSerializer,
    RegisterSerializer,
    RideCreateSerializer,
    RideSerializer,
    offers_for_api,
    rides_for_api,
)


TOKEN_SIGNER = TimestampSigner(salt='ir.api.auth')


def _ride_queryset():
    return rides_for_api(Ride.objects.all())


def _ride_for_response(ride):
    return _ride_queryset().get(pk=ride.pk)


def _profile(user):
    return PassengerProfile.objects.filter(user=user).first()


def _driver(user):
    return DriverProfile.objects.filter(user=user).first()


def _name(user):
    return user.get_full_name() or user.username


def _add_points(profile, user, ride, amount, reason, role):
    if amount <= 0:
        return
    profile.points = (profile.points or 0) + amount
    profile.save(update_fields=['points'])
    PointHistory.objects.create(
        id=uuid.uuid4(), user=user, ride=ride, amount=amount,
        reason=reason[:50], created_at=timezone.now(), network_role=role,
    )


def _set_point(latitude, longitude, ride_id, side, label=''):
    column = 'ubicacion_pasajero' if side == 'passenger' else 'ubicacion_conductor'
    label_column = 'etiqueta_pasajero' if side == 'passenger' else 'etiqueta_conductor'
    with connection.cursor() as cursor:
        cursor.execute(
            f'UPDATE viaje SET {column} = ST_SetSRID(ST_MakePoint(%s, %s), 4326), {label_column} = %s WHERE id_viaje = %s',
            [longitude, latitude, label, ride_id],
        )


def _decode_polyline(encoded):
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


def _google_json(url, timeout_message):
    try:
        with urlopen(Request(url), timeout=8) as response:
            return json.loads(response.read().decode('utf-8')), None
    except (URLError, TimeoutError, ValueError):
        return None, Response({'detail': timeout_message}, status=status.HTTP_502_BAD_GATEWAY)


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        identifier = serializer.validated_data['username'].strip().lower()
        user = Usuario.objects.filter(correo__iexact=identifier).first()
        if not user or not user.check_password(serializer.validated_data['password']):
            return Response({'detail': 'Credenciales inválidas.'}, status=status.HTTP_401_UNAUTHORIZED)
        passenger = _profile(user)
        driver = _driver(user)
        token = TOKEN_SIGNER.sign(str(user.pk))
        profile = driver or passenger
        return Response({
            'token': token,
            'user': {
                'id': str(user.pk),
                'name': _name(user),
                'username': user.username,
                'role': user.rol,
                'points': profile.points if profile else 0,
                'tier': profile.tier if isinstance(profile, DriverProfile) else (profile.rank.nombre if profile and profile.rank_id else 'Inicial'),
            },
        })


class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        names = data['name'].split(' ', 1)
        now = timezone.now()
        with transaction.atomic():
            user = Usuario.objects.create(
                id=uuid.uuid4(), nombres=names[0], apellidos=names[1] if len(names) > 1 else '',
                correo=data['identifier'], celular=data['phone'],
                contrasena_hash=make_password(data['password']), rol=data['role'],
                estado='active', fecha_creacion=now,
            )
            if data['role'] == 'passenger':
                profile = PassengerProfile.objects.create(
                    id=uuid.uuid4(), user=user, points=0, total_rides=0,
                    rating_count=0, rating=0,
                )
            else:
                profile = DriverProfile.objects.create(
                    id=uuid.uuid4(), user=user, status=DriverProfile.Status.OFFLINE,
                    document_number=data.get('document_number', ''), total_rides=0,
                    points=0, wallet_balance=0, reserved_balance=0, rating=0,
                    rating_count=0,
                )
                Vehicle.objects.create(
                    id=uuid.uuid4(), driver=profile,
                    plate=data.get('vehicle_plate', '').upper(),
                    category=data.get('vehicle_type', ''),
                    brand_model=data.get('vehicle_brand', ''),
                    color=data.get('vehicle_color', ''), status='active',
                )
        token = TOKEN_SIGNER.sign(str(user.pk))
        tier = profile.tier if isinstance(profile, DriverProfile) else (profile.rank.nombre if profile.rank_id else 'Inicial')
        return Response({
            'token': token,
            'user': {
                'id': str(user.pk), 'name': _name(user), 'username': user.username,
                'role': user.rol, 'points': profile.points or 0, 'tier': tier,
            },
        }, status=status.HTTP_201_CREATED)


class PassengerMeView(APIView):
    def get(self, request):
        profile = get_object_or_404(PassengerProfile.objects.select_related('rank'), user=request.user)
        return Response({
            'name': _name(request.user), 'points': profile.points or 0,
            'tier': profile.rank.nombre if profile.rank_id else 'Inicial',
            'rating': float(profile.rating or 0), 'rating_count': profile.rating_count or 0,
            'total_rides': profile.total_rides or 0,
        })


class PlaceSearchView(APIView):
    def get(self, request):
        query = request.query_params.get('input', '').strip()
        if not query:
            return Response({'predictions': []})
        if not settings.GOOGLE_MAPS_API_KEY:
            return Response({'detail': 'Configura GOOGLE_MAPS_API_KEY en el entorno del backend.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        params = urlencode({'input': query, 'language': 'es', 'components': 'country:co', 'key': settings.GOOGLE_MAPS_API_KEY})
        data, error = _google_json(f'https://maps.googleapis.com/maps/api/place/autocomplete/json?{params}', 'No fue posible conectar con Google Places.')
        if error:
            return error
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
        data, error = _google_json(f'https://maps.googleapis.com/maps/api/place/details/json?{params}', 'No fue posible conectar con Google Places.')
        if error:
            return error
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
        data, error = _google_json(f'https://maps.googleapis.com/maps/api/directions/json?{params}', 'No fue posible conectar con Google Directions.')
        if error:
            return error
        if data.get('status') != 'OK' or not data.get('routes'):
            return Response({'detail': data.get('error_message', 'No fue posible calcular la ruta.')}, status=status.HTTP_502_BAD_GATEWAY)
        route = data['routes'][0]
        leg = route['legs'][0]
        polyline = route.get('overview_polyline', {}).get('points', '')
        steps = [{
            'instruction': re.sub('<[^>]+>', '', unescape(step.get('html_instructions', ''))),
            'distance_text': step['distance']['text'], 'duration_text': step['duration']['text'],
            'maneuver': step.get('maneuver', 'straight'),
            'polyline': step.get('polyline', {}).get('points', ''),
            'end_lat': step['end_location']['lat'], 'end_lng': step['end_location']['lng'],
        } for step in leg.get('steps', [])]
        return Response({
            'distance_km': round(leg['distance']['value'] / 1000, 2),
            'duration_minutes': round(leg['duration']['value'] / 60),
            'distance_text': leg['distance']['text'], 'duration_text': leg['duration']['text'],
            'polyline': polyline, 'route_points': _decode_polyline(polyline) if polyline else [], 'steps': steps,
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
        data, error = _google_json(f'https://maps.googleapis.com/maps/api/place/nearbysearch/json?{params}', 'No fue posible conectar con Google Places.')
        if error:
            return error
        if data.get('status') not in ('OK', 'ZERO_RESULTS'):
            return Response({'detail': data.get('error_message', 'Google Places no respondió correctamente.')}, status=status.HTTP_502_BAD_GATEWAY)
        places = []
        for place in data.get('results', []):
            location = place['geometry']['location']
            latitude_delta = radians(location['lat'] - latitude)
            longitude_delta = radians(location['lng'] - longitude)
            haversine = sin(latitude_delta / 2) ** 2 + cos(radians(latitude)) * cos(radians(location['lat'])) * sin(longitude_delta / 2) ** 2
            distance = 6371000 * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
            places.append({'place_id': place['place_id'], 'name': place['name'], 'vicinity': place.get('vicinity', ''), 'lat': location['lat'], 'lng': location['lng'], 'distance_meters': round(distance)})
        return Response({'places': sorted(places, key=lambda place: place['distance_meters'])[:5]})


class RideListCreateView(generics.ListCreateAPIView):
    serializer_class = RideSerializer

    def get_queryset(self):
        profile = _profile(self.request.user)
        if not profile:
            return Ride.objects.none()
        return _ride_queryset().filter(passenger_profile=profile)

    def create(self, request, *args, **kwargs):
        serializer = RideCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = _profile(request.user)
        if not profile:
            return Response({'detail': 'Solo los pasajeros pueden solicitar viajes.'}, status=status.HTTP_403_FORBIDDEN)
        values = serializer.validated_data
        with transaction.atomic():
            ride = Ride.objects.create(
                id=uuid.uuid4(), passenger_profile=profile, status=Ride.Status.SEARCHING,
                created_at=timezone.now(), origin=values['origin'], destination=values['destination'],
                vehicle_type=values['vehicle_type'], offer_amount=values['offer_amount'],
                estimated_price=values['estimated_price'], distance_meters=round(values['distance_km'] * 1000),
                duration_seconds=values['duration_minutes'] * 60,
            )
            with connection.cursor() as cursor:
                cursor.execute(
                    'UPDATE viaje SET coordenada_origen = ST_SetSRID(ST_MakePoint(%s, %s), 4326), coordenada_destino = ST_SetSRID(ST_MakePoint(%s, %s), 4326) WHERE id_viaje = %s',
                    [values['origin_lng'], values['origin_lat'], values['destination_lng'], values['destination_lat'], ride.pk],
                )
        return Response(RideSerializer(_ride_for_response(ride)).data, status=status.HTTP_201_CREATED)


class RideOfferRejectView(APIView):
    def post(self, request, ride_id, offer_id):
        ride = get_object_or_404(_ride_queryset(), api_id=ride_id, passenger_profile__user=request.user)
        offer = get_object_or_404(
            offers_for_api(RideOffer.objects.filter(ride=ride)), api_id=offer_id,
            status=RideOffer.Status.PENDING,
        )
        offer.status = RideOffer.Status.REJECTED
        offer.save(update_fields=['status'])
        return Response(RideSerializer(_ride_for_response(ride)).data)


class RideLocationView(APIView):
    def post(self, request, ride_id):
        ride = get_object_or_404(_ride_queryset(), api_id=ride_id)
        if request.user.pk not in {ride.passenger_profile.user_id if ride.passenger_profile_id else None, ride.driver_profile.user_id if ride.driver_profile_id else None}:
            return Response({'detail': 'No puedes actualizar la ubicación de este viaje.'}, status=status.HTTP_403_FORBIDDEN)
        try:
            latitude = round(float(request.data['latitude']), 6)
            longitude = round(float(request.data['longitude']), 6)
        except (KeyError, TypeError, ValueError):
            return Response({'detail': 'latitude y longitude son obligatorias.'}, status=status.HTTP_400_BAD_REQUEST)
        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            return Response({'detail': 'Las coordenadas no son válidas.'}, status=status.HTTP_400_BAD_REQUEST)
        side = 'passenger' if request.user.pk == ride.passenger_profile.user_id else 'driver'
        label = 'Ubicación actual'
        _set_point(latitude, longitude, ride.pk, side, label)
        return Response(RideSerializer(_ride_for_response(ride)).data)


class RideOfferSelectView(APIView):
    def post(self, request, ride_id, offer_id):
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset().select_for_update(of=('self',)), api_id=ride_id,
                passenger_profile__user=request.user,
            )
            offer = get_object_or_404(
                offers_for_api(RideOffer.objects.select_for_update(of=('self',)).filter(ride=ride)),
                api_id=offer_id, status=RideOffer.Status.PENDING,
            )
            if ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
                return Response({'detail': 'La solicitud ya no está disponible.'}, status=status.HTTP_409_CONFLICT)
            profile = get_object_or_404(DriverProfile.objects.select_for_update(), pk=offer.driver_profile_id)
            reserve = int((offer.amount + 9) // 10)
            if profile.available_balance < reserve:
                return Response({'detail': 'El conductor ya no tiene saldo suficiente para reservar este viaje.'}, status=status.HTTP_409_CONFLICT)
            profile.reserved_balance = (profile.reserved_balance or 0) + reserve
            profile.status = DriverProfile.Status.RESERVED_FOR_TRIP
            profile.save(update_fields=['reserved_balance', 'status'])
            ride.driver_profile = profile
            ride.final_fare = offer.amount
            ride.reserved_debit = reserve
            ride.pickup_code = secrets.token_hex(3).upper()
            ride.status = Ride.Status.ACCEPTED
            ride.save(update_fields=['driver_profile', 'final_fare', 'reserved_debit', 'pickup_code', 'status'])
            offer.status = RideOffer.Status.ACCEPTED
            offer.save(update_fields=['status'])
            ride.offers.filter(status=RideOffer.Status.PENDING).exclude(pk=offer.pk).update(status=RideOffer.Status.REJECTED)
        return Response(RideSerializer(_ride_for_response(ride)).data)


class RideRatingView(APIView):
    def post(self, request, ride_id):
        try:
            rating = int(request.data.get('rating', 0))
        except (TypeError, ValueError):
            rating = 0
        if not 1 <= rating <= 5:
            return Response({'detail': 'La calificación debe estar entre 1 y 5 estrellas.'}, status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            ride = get_object_or_404(_ride_queryset().select_for_update(of=('self',)), api_id=ride_id)
            passenger_side = ride.passenger_profile.user_id == request.user.pk if ride.passenger_profile_id else False
            driver_side = ride.driver_profile.user_id == request.user.pk if ride.driver_profile_id else False
            if not passenger_side and not driver_side:
                return Response({'detail': 'No puedes calificar este viaje.'}, status=status.HTTP_403_FORBIDDEN)
            if ride.status not in (Ride.Status.COMPLETED, Ride.Status.VALIDATED):
                return Response({'detail': 'Solo se pueden calificar viajes completados.'}, status=status.HTTP_409_CONFLICT)
            rating_field = 'passenger_rating' if passenger_side else 'driver_rating'
            if getattr(ride, rating_field) is not None:
                return Response({'detail': 'Ya calificaste este viaje.'}, status=status.HTTP_409_CONFLICT)
            profile = ride.driver_profile if passenger_side else ride.passenger_profile
            count = profile.rating_count or 0
            previous = float(profile.rating or 0)
            profile.rating = round((previous * count + rating) / (count + 1), 2)
            profile.rating_count = count + 1
            profile.save(update_fields=['rating', 'rating_count'])
            setattr(ride, rating_field, rating)
            ride.save(update_fields=[rating_field])
        return Response(RideSerializer(_ride_for_response(ride)).data)


class RideCancelView(APIView):
    def post(self, request, ride_id):
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset().select_for_update(of=('self',)), api_id=ride_id,
                passenger_profile__user=request.user,
            )
            cancellable = {
                Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING,
                Ride.Status.ACCEPTED, Ride.Status.DRIVER_SELECTED, Ride.Status.EN_ROUTE,
                Ride.Status.ARRIVED,
            }
            if ride.status not in cancellable:
                return Response({'detail': 'Este viaje ya no se puede cancelar.'}, status=status.HTTP_409_CONFLICT)
            if ride.driver_profile_id and ride.reserved_debit:
                profile = DriverProfile.objects.select_for_update().get(pk=ride.driver_profile_id)
                profile.reserved_balance = max(0, (profile.reserved_balance or 0) - ride.reserved_debit)
                profile.status = DriverProfile.Status.AVAILABLE
                profile.save(update_fields=['reserved_balance', 'status'])
            ride.status = Ride.Status.CANCELLED
            ride.save(update_fields=['status'])
            ride.offers.filter(status=RideOffer.Status.PENDING).update(status=RideOffer.Status.REJECTED)
        return Response(RideSerializer(_ride_for_response(ride)).data)
