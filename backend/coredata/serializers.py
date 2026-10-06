from django.db.models import BigIntegerField, FloatField, Prefetch
from django.db.models.expressions import RawSQL
from rest_framework import serializers

from .models import DriverProfile, PassengerProfile, Ride, RideOffer, Usuario, Vehicle


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)


class RegisterSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    identifier = serializers.CharField(max_length=255)
    phone = serializers.CharField(max_length=20)
    role = serializers.ChoiceField(choices=(('passenger', 'Pasajero'), ('driver', 'Conductor')))
    password = serializers.CharField(write_only=True, min_length=8)
    document_number = serializers.CharField(max_length=20, required=False, allow_blank=True)
    vehicle_type = serializers.CharField(max_length=30, required=False, allow_blank=True)
    vehicle_plate = serializers.CharField(max_length=10, required=False, allow_blank=True)
    vehicle_brand = serializers.CharField(max_length=100, required=False, allow_blank=True)
    vehicle_color = serializers.CharField(max_length=30, required=False, allow_blank=True)

    def validate_identifier(self, value):
        value = value.strip().lower()
        if not value:
            raise serializers.ValidationError('El correo es obligatorio.')
        if Usuario.objects.filter(correo__iexact=value).exists():
            raise serializers.ValidationError('Ya existe una cuenta con ese correo o usuario.')
        return value

    def validate_name(self, value):
        if not value.strip():
            raise serializers.ValidationError('El nombre es obligatorio.')
        return value.strip()


class RideCreateSerializer(serializers.Serializer):
    origin = serializers.CharField(max_length=255)
    destination = serializers.CharField(max_length=255)
    vehicle_type = serializers.CharField(max_length=30, default='economy')
    offer_amount = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=1)
    estimated_price = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0)
    origin_lat = serializers.FloatField(min_value=-90, max_value=90)
    origin_lng = serializers.FloatField(min_value=-180, max_value=180)
    destination_lat = serializers.FloatField(min_value=-90, max_value=90)
    destination_lng = serializers.FloatField(min_value=-180, max_value=180)
    distance_km = serializers.FloatField(min_value=0)
    duration_minutes = serializers.IntegerField(min_value=0)

    def validate(self, attrs):
        attrs['origin'] = attrs['origin'].strip()
        attrs['destination'] = attrs['destination'].strip()
        if not attrs['origin'] or not attrs['destination']:
            raise serializers.ValidationError('El origen y el destino son obligatorios.')
        return attrs


class DriverProfileSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=DriverProfile.Status.choices, required=False)


class DriverStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=(
        DriverProfile.Status.OFFLINE,
        DriverProfile.Status.AVAILABLE,
    ))


class RideOfferCreateSerializer(serializers.Serializer):
    amount = serializers.IntegerField(min_value=1)


class WalletRechargeSerializer(serializers.Serializer):
    amount = serializers.IntegerField(min_value=5000)


class RideSerializer(serializers.Serializer):
    id = serializers.IntegerField(source='api_id', read_only=True)
    origin = serializers.CharField(allow_null=True)
    destination = serializers.CharField(allow_null=True)
    origin_lat = serializers.FloatField(allow_null=True)
    origin_lng = serializers.FloatField(allow_null=True)
    destination_lat = serializers.FloatField(allow_null=True)
    destination_lng = serializers.FloatField(allow_null=True)
    passenger_lat = serializers.FloatField(allow_null=True)
    passenger_lng = serializers.FloatField(allow_null=True)
    driver_lat = serializers.FloatField(allow_null=True)
    driver_lng = serializers.FloatField(allow_null=True)
    passenger_location_label = serializers.CharField(allow_blank=True)
    driver_location_label = serializers.CharField(allow_blank=True)
    live_distance_km = serializers.SerializerMethodField()
    distance_km = serializers.SerializerMethodField()
    duration_minutes = serializers.SerializerMethodField()
    vehicle_type = serializers.CharField()
    offer_amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    estimated_price = serializers.DecimalField(max_digits=10, decimal_places=2, allow_null=True)
    final_fare = serializers.DecimalField(max_digits=10, decimal_places=2, allow_null=True)
    status = serializers.CharField(allow_null=True)
    passenger_name = serializers.SerializerMethodField()
    driver_name = serializers.SerializerMethodField()
    driver_vehicle_type = serializers.SerializerMethodField()
    driver_vehicle_brand = serializers.SerializerMethodField()
    driver_vehicle_color = serializers.SerializerMethodField()
    driver_vehicle_plate = serializers.SerializerMethodField()
    pickup_code = serializers.CharField(allow_null=True, allow_blank=True)
    passenger_rating = serializers.IntegerField(allow_null=True)
    driver_rating = serializers.IntegerField(allow_null=True)
    offers = serializers.SerializerMethodField()
    created_at = serializers.DateTimeField(allow_null=True)

    def get_passenger_name(self, obj):
        return obj.passenger_profile.user.get_full_name() if obj.passenger_profile_id and obj.passenger_profile.user_id else None

    def get_driver_name(self, obj):
        profile = obj.driver_profile
        return profile.user.get_full_name() if profile and profile.user_id else None

    def _vehicle(self, obj):
        profile = obj.driver_profile
        if not profile:
            return None
        vehicles = getattr(profile, '_prefetched_objects_cache', {}).get('vehicles')
        if vehicles is not None:
            return next(iter(vehicles), None)
        return profile.vehicles.order_by('id').first()

    def get_driver_vehicle_type(self, obj):
        vehicle = self._vehicle(obj)
        return vehicle.category if vehicle else None

    def get_driver_vehicle_brand(self, obj):
        vehicle = self._vehicle(obj)
        return vehicle.brand_model if vehicle else None

    def get_driver_vehicle_color(self, obj):
        vehicle = self._vehicle(obj)
        return vehicle.color if vehicle else None

    def get_driver_vehicle_plate(self, obj):
        vehicle = self._vehicle(obj)
        return vehicle.plate if vehicle else None

    def get_live_distance_km(self, obj):
        if None in (obj.passenger_lat, obj.passenger_lng, obj.driver_lat, obj.driver_lng):
            return None
        from math import atan2, cos, radians, sin, sqrt

        latitude_delta = radians(obj.driver_lat - obj.passenger_lat)
        longitude_delta = radians(obj.driver_lng - obj.passenger_lng)
        haversine = sin(latitude_delta / 2) ** 2 + cos(radians(obj.passenger_lat)) * cos(radians(obj.driver_lat)) * sin(longitude_delta / 2) ** 2
        return round(6371 * 2 * atan2(sqrt(haversine), sqrt(1 - haversine)), 2)

    def get_distance_km(self, obj):
        return round((obj.distance_meters or 0) / 1000, 2)

    def get_duration_minutes(self, obj):
        return round((obj.duration_seconds or 0) / 60)

    def get_offers(self, obj):
        offers = getattr(obj, '_prefetched_objects_cache', {}).get('offers')
        if offers is None:
            offers = obj.offers.select_related('driver_profile__user').annotate(
                api_id=RawSQL('"ofertas"."api_id"', [], output_field=BigIntegerField())
            )
        return [
            {
                'id': offer.api_id,
                'amount': offer.amount,
                'status': offer.status,
                'driver_id': str(offer.driver_profile.user_id) if offer.driver_profile_id else None,
                'driver_name': offer.driver_profile.user.get_full_name() if offer.driver_profile_id and offer.driver_profile.user_id else None,
                'created_at': offer.created_at,
            }
            for offer in offers
        ]


def rides_for_api(queryset):
    return queryset.select_related(
        'passenger_profile__user', 'driver_profile__user', 'origin_zone', 'destination_zone'
    ).prefetch_related(
        'driver_profile__vehicles',
        Prefetch(
            'offers',
            queryset=RideOffer.objects.select_related('driver_profile__user').annotate(
                api_id=RawSQL('"ofertas"."api_id"', [], output_field=BigIntegerField())
            ),
        ),
    ).annotate(
        api_id=RawSQL('"viaje"."api_id"', [], output_field=BigIntegerField()),
        origin_lat=RawSQL('ST_Y("viaje"."coordenada_origen")', [], output_field=FloatField()),
        origin_lng=RawSQL('ST_X("viaje"."coordenada_origen")', [], output_field=FloatField()),
        destination_lat=RawSQL('ST_Y("viaje"."coordenada_destino")', [], output_field=FloatField()),
        destination_lng=RawSQL('ST_X("viaje"."coordenada_destino")', [], output_field=FloatField()),
        passenger_lat=RawSQL('ST_Y("viaje"."ubicacion_pasajero")', [], output_field=FloatField()),
        passenger_lng=RawSQL('ST_X("viaje"."ubicacion_pasajero")', [], output_field=FloatField()),
        driver_lat=RawSQL('ST_Y("viaje"."ubicacion_conductor")', [], output_field=FloatField()),
        driver_lng=RawSQL('ST_X("viaje"."ubicacion_conductor")', [], output_field=FloatField()),
    )


def offers_for_api(queryset):
    return queryset.select_related('driver_profile__user').annotate(
        api_id=RawSQL('"ofertas"."api_id"', [], output_field=BigIntegerField())
    )