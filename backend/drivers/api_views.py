import uuid
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from coredata.models import DriverProfile, DriverTransaction, Ride, RideOffer, Vehicle
from coredata.serializers import DriverStatusSerializer, RideSerializer, RideOfferCreateSerializer, WalletRechargeSerializer, offers_for_api, rides_for_api
from passengers.api_views import _add_points, _name, _profile


def _driver(user):
    return DriverProfile.objects.filter(user=user).first()


def _ride_queryset(queryset=None):
    return rides_for_api(queryset if queryset is not None else Ride.objects.all())


def _ride_for_response(ride):
    return _ride_queryset().get(pk=ride.pk)


def _reserve_amount(amount):
    return int((Decimal(amount) + Decimal('9')) // Decimal('10'))


def _aware_datetime(value):
    if timezone.is_naive(value):
        return timezone.make_aware(value, timezone.get_default_timezone())
    return value


def _require_driver(request):
    return _driver(request.user)


class DriverMeView(APIView):
    def get(self, request):
        profile = get_object_or_404(DriverProfile.objects.select_related('user', 'rank'), user=request.user)
        vehicle = Vehicle.objects.filter(driver=profile).order_by('id').first()
        return Response({
            'name': _name(request.user), 'status': profile.status,
            'wallet_balance': profile.wallet_balance or 0,
            'reserved_balance': profile.reserved_balance or 0,
            'available_balance': profile.available_balance,
            'points': profile.points or 0, 'tier': profile.tier,
            'rating': float(profile.rating or 0), 'rating_count': profile.rating_count or 0,
            'total_rides': profile.total_rides or 0,
            'vehicle_type': vehicle.category if vehicle and vehicle.category else 'carro',
        })

    def patch(self, request):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden actualizar este estado.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = DriverStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_status = serializer.validated_data['status']
        if profile.status == DriverProfile.Status.RESERVED_FOR_TRIP and new_status == DriverProfile.Status.OFFLINE:
            return Response({'detail': 'No puedes desconectarte mientras tienes un viaje reservado.'}, status=status.HTTP_409_CONFLICT)
        profile.status = new_status
        profile.save(update_fields=['status'])
        return Response({'status': profile.status})


class DriverAvailableRidesView(APIView):
    def get(self, request):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden consultar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        cutoff = timezone.now() - timedelta(minutes=5)
        rides = _ride_queryset(Ride.objects.filter(
            status__in=(Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING),
            created_at__isnull=False,
            created_at__gte=cutoff,
        ).exclude(offers__driver_profile=profile).distinct())
        now = timezone.now()
        results = RideSerializer(rides, many=True).data
        for ride_data, ride in zip(results, rides):
            ride_data['remaining_seconds'] = max(0, 300 - int((now - _aware_datetime(ride.created_at)).total_seconds()))
        return Response(results)


class DriverRidesView(APIView):
    def get(self, request):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden consultar sus viajes.'}, status=status.HTTP_403_FORBIDDEN)
        rides = _ride_queryset(Ride.objects.filter(driver_profile=profile).order_by('-created_at')[:30])
        return Response(RideSerializer(rides, many=True).data)


class RideOfferCreateView(APIView):
    def post(self, request, ride_id):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden ofertar.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = RideOfferCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        amount = serializer.validated_data['amount']
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset(Ride.objects.select_for_update(of=('self',))), api_id=ride_id
            )
            if not ride.created_at or timezone.now() >= _aware_datetime(ride.created_at) + timedelta(minutes=5):
                return Response({'detail': 'La ventana de esta solicitud expiró.'}, status=status.HTTP_409_CONFLICT)
            if ride.passenger_profile.user_id == request.user.pk or ride.status not in (
                Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING,
            ):
                return Response({'detail': 'Esta solicitud ya no admite ofertas.'}, status=status.HTTP_409_CONFLICT)
            profile = DriverProfile.objects.select_for_update().get(pk=profile.pk)
            if profile.status != DriverProfile.Status.AVAILABLE:
                return Response({'detail': 'Debes estar disponible para ofertar.'}, status=status.HTTP_409_CONFLICT)
            reserve = _reserve_amount(amount)
            if profile.available_balance < reserve:
                return Response({'detail': 'Saldo insuficiente para ofertar (requiere 10% de la tarifa).'}, status=status.HTTP_400_BAD_REQUEST)
            if RideOffer.objects.filter(ride=ride, driver_profile=profile, status=RideOffer.Status.PENDING).exists():
                return Response({'detail': 'Ya tienes una oferta vigente para esta solicitud.'}, status=status.HTTP_409_CONFLICT)
            offer = RideOffer.objects.create(
                id=uuid.uuid4(), ride=ride, driver_profile=profile, amount=amount,
                status=RideOffer.Status.PENDING, created_at=timezone.now(),
            )
            if ride.status in (Ride.Status.SEARCHING, Ride.Status.REQUESTED):
                ride.status = Ride.Status.NEGOTIATING
                ride.save(update_fields=['status'])
        offer = offers_for_api(RideOffer.objects.filter(pk=offer.pk)).get()
        return Response({'id': offer.api_id, 'amount': offer.amount, 'status': offer.status}, status=status.HTTP_201_CREATED)


class RideOfferAcceptView(APIView):
    def post(self, request, ride_id):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden aceptar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset(Ride.objects.select_for_update(of=('self',))), api_id=ride_id
            )
            if not ride.created_at or timezone.now() >= _aware_datetime(ride.created_at) + timedelta(minutes=5):
                return Response({'detail': 'La ventana de esta solicitud expiró.'}, status=status.HTTP_409_CONFLICT)
            if ride.passenger_profile.user_id == request.user.pk or ride.status not in (
                Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING,
            ):
                return Response({'detail': 'Esta solicitud ya no admite ofertas.'}, status=status.HTTP_409_CONFLICT)
            profile = DriverProfile.objects.select_for_update().get(pk=profile.pk)
            if profile.status != DriverProfile.Status.AVAILABLE:
                return Response({'detail': 'Debes estar disponible para aceptar.'}, status=status.HTTP_409_CONFLICT)
            if RideOffer.objects.filter(ride=ride, driver_profile=profile, status=RideOffer.Status.PENDING).exists():
                return Response({'detail': 'Ya tienes una oferta vigente para esta solicitud.'}, status=status.HTTP_409_CONFLICT)
            offer = RideOffer.objects.create(
                id=uuid.uuid4(), ride=ride, driver_profile=profile,
                amount=ride.offer_amount, status=RideOffer.Status.PENDING,
                created_at=timezone.now(),
            )
            if ride.status in (Ride.Status.SEARCHING, Ride.Status.REQUESTED):
                ride.status = Ride.Status.NEGOTIATING
                ride.save(update_fields=['status'])
        offer = offers_for_api(RideOffer.objects.filter(pk=offer.pk)).get()
        return Response({'id': offer.api_id, 'amount': offer.amount, 'status': offer.status}, status=status.HTTP_201_CREATED)


class RideRejectView(APIView):
    def post(self, request, ride_id):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden rechazar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        ride = get_object_or_404(_ride_queryset(), api_id=ride_id)
        if ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
            return Response({'detail': 'Esta solicitud ya no está disponible.'}, status=status.HTTP_409_CONFLICT)
        RideOffer.objects.get_or_create(
            ride=ride, driver_profile=profile,
            defaults={
                'id': uuid.uuid4(), 'amount': ride.offer_amount,
                'status': RideOffer.Status.REJECTED, 'created_at': timezone.now(),
            },
        )
        return Response({'status': 'rejected'})


class RideVerifyPickupCodeView(APIView):
    def post(self, request, ride_id):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden iniciar viajes.'}, status=status.HTTP_403_FORBIDDEN)
        code = str(request.data.get('code', '')).strip().upper()
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset(Ride.objects.select_for_update(of=('self',))),
                api_id=ride_id, driver_profile=profile,
            )
            if ride.status != Ride.Status.ARRIVED:
                return Response({'detail': 'El viaje no está listo para iniciar.'}, status=status.HTTP_409_CONFLICT)
            if not ride.pickup_code or code != ride.pickup_code:
                return Response({'detail': 'El código del pasajero no coincide.'}, status=status.HTTP_400_BAD_REQUEST)
            ride.status = Ride.Status.IN_PROGRESS
            ride.save(update_fields=['status'])
        return Response({'status': ride.status})


class RideUpdateStatusView(APIView):
    def post(self, request, ride_id):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden actualizar viajes.'}, status=status.HTTP_403_FORBIDDEN)
        new_status = request.data.get('status')
        valid_statuses = {value for value, _ in Ride.Status.choices}
        if new_status not in valid_statuses:
            return Response({'detail': 'Estado inválido.'}, status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            ride = get_object_or_404(
                _ride_queryset(Ride.objects.select_for_update(of=('self',))),
                api_id=ride_id, driver_profile=profile,
            )
            if ride.status == Ride.Status.VALIDATED:
                return Response({'status': ride.status, 'final_fare': ride.final_fare})
            allowed = {
                Ride.Status.ACCEPTED: {Ride.Status.EN_ROUTE},
                Ride.Status.DRIVER_SELECTED: {Ride.Status.EN_ROUTE},
                Ride.Status.EN_ROUTE: {Ride.Status.ARRIVED},
                Ride.Status.ARRIVED: {Ride.Status.IN_PROGRESS},
                Ride.Status.IN_PROGRESS: {Ride.Status.COMPLETED},
                Ride.Status.COMPLETED: {Ride.Status.VALIDATED},
            }
            if new_status != Ride.Status.CANCELLED and new_status not in allowed.get(ride.status, set()):
                return Response({'detail': 'La transición de estado no es válida.'}, status=status.HTTP_409_CONFLICT)
            if new_status == Ride.Status.VALIDATED:
                profile = DriverProfile.objects.select_for_update().get(pk=profile.pk)
                fare = ride.final_fare or ride.offer_amount or ride.estimated_price or 0
                debit = ride.reserved_debit or _reserve_amount(fare)
                if (profile.reserved_balance or 0) < debit or (profile.wallet_balance or 0) < debit:
                    return Response({'detail': 'La reserva de Bolsa IR no cubre el débito final.'}, status=status.HTTP_409_CONFLICT)
                profile.total_rides = (profile.total_rides or 0) + 1
                profile.reserved_balance -= debit
                profile.wallet_balance -= debit
                profile.status = DriverProfile.Status.AVAILABLE
                profile.save(update_fields=['total_rides', 'reserved_balance', 'wallet_balance', 'status'])
                _add_points(profile, request.user, ride, int(debit // 10), f'PI conductor viaje {ride.pk}', 'driver')
                passenger = _profile(ride.passenger_profile.user)
                if passenger:
                    passenger.total_rides = (passenger.total_rides or 0) + 1
                    passenger.save(update_fields=['total_rides'])
                    _add_points(passenger, ride.passenger_profile.user, ride, int(fare // 20), f'PI pasajero viaje {ride.pk}', 'passenger')
                ride.final_fare = fare
                ride.save(update_fields=['final_fare'])
            ride.status = new_status
            ride.save(update_fields=['status'])
        return Response({'status': ride.status, 'final_fare': ride.final_fare})


class WalletRechargeView(APIView):
    def post(self, request):
        profile = _require_driver(request)
        if not profile:
            return Response({'detail': 'Solo los conductores pueden recargar Bolsa IR.'}, status=status.HTTP_403_FORBIDDEN)
        amount_serializer = WalletRechargeSerializer(data=request.data)
        amount_serializer.is_valid(raise_exception=True)
        amount = Decimal(amount_serializer.validated_data['amount'])
        with transaction.atomic():
            profile = DriverProfile.objects.select_for_update().get(pk=profile.pk)
            profile.wallet_balance = (profile.wallet_balance or 0) + amount
            profile.save(update_fields=['wallet_balance'])
            DriverTransaction.objects.create(
                id=uuid.uuid4(), driver_profile=profile, amount=amount,
                movement_type='recharge', created_at=timezone.now(), status='completed',
            )
        return Response({'wallet_balance': profile.wallet_balance})
