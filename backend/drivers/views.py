from django.db import transaction
from datetime import timedelta
from django.utils import timezone
from rest_framework import generics, permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from .models import DriverProfile, RideOffer
from passengers.models import AccountProfile, Ride
from passengers.views import RideSerializer


def _is_driver(request):
    return AccountProfile.objects.filter(user=request.user, role=AccountProfile.Role.DRIVER).exists()

class DriverProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverProfile
        fields = ['status', 'wallet_balance', 'reserved_balance']
        read_only_fields = ['wallet_balance', 'reserved_balance']

class RideOfferSerializer(serializers.ModelSerializer):
    class Meta:
        model = RideOffer
        fields = ['id', 'ride', 'amount', 'status', 'created_at']
        read_only_fields = ['id', 'status', 'created_at']

class DriverMeView(APIView):
    def get(self, request):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden acceder a este recurso.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        return Response({
            'status': profile.status,
            'wallet_balance': profile.wallet_balance,
            'reserved_balance': profile.reserved_balance,
            'available_balance': profile.wallet_balance - profile.reserved_balance,
            'points': profile.points,
            'tier': profile.tier,
            'vehicle_type': AccountProfile.objects.filter(user=request.user).values_list('vehicle_type', flat=True).first() or 'carro',
        })
    
    def patch(self, request):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden actualizar este estado.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        if 'status' in request.data:
            allowed = {DriverProfile.Status.OFFLINE, DriverProfile.Status.AVAILABLE}
            if request.data['status'] not in allowed:
                return Response({'detail': 'Estado no permitido desde el dispositivo.'}, status=status.HTTP_400_BAD_REQUEST)
            if profile.status == DriverProfile.Status.RESERVED_FOR_TRIP and request.data['status'] != DriverProfile.Status.AVAILABLE:
                return Response({'detail': 'No puedes desconectarte mientras tienes un viaje reservado.'}, status=status.HTTP_409_CONFLICT)
            profile.status = request.data['status']
            profile.save()
        return Response({'status': profile.status})

class DriverAvailableRidesView(APIView):
    def get(self, request):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden consultar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        rides = Ride.objects.filter(
            status__in=[Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING],
            created_at__gte=timezone.now() - timedelta(minutes=5),
        ).exclude(offers__driver=request.user).select_related('passenger').distinct()
        data = []
        for r in rides:
            data.append({
                'id': r.id,
                'origin': r.origin,
                'destination': r.destination,
                'offer_amount': r.offer_amount,
                'estimated_price': r.estimated_price,
                'final_fare': r.final_fare,
                'distance_km': float(r.distance_km),
                'duration_minutes': r.duration_minutes,
                'vehicle_type': r.vehicle_type,
                'origin_lat': float(r.origin_lat),
                'origin_lng': float(r.origin_lng),
                'destination_lat': float(r.destination_lat),
                'destination_lng': float(r.destination_lng),
                'passenger_lat': float(r.passenger_lat) if r.passenger_lat is not None else None,
                'passenger_lng': float(r.passenger_lng) if r.passenger_lng is not None else None,
                'driver_lat': float(r.driver_lat) if r.driver_lat is not None else None,
                'driver_lng': float(r.driver_lng) if r.driver_lng is not None else None,
                'passenger_location_label': r.passenger_location_label,
                'driver_location_label': r.driver_location_label,
                'passenger_name': r.passenger.get_full_name() or r.passenger.username,
                'status': r.status,
                'created_at': r.created_at,
                'remaining_seconds': max(0, 300 - int((timezone.now() - r.created_at).total_seconds())),
            })
        return Response(data)


class DriverRidesView(APIView):
    def get(self, request):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden consultar sus viajes.'}, status=status.HTTP_403_FORBIDDEN)
        rides = Ride.objects.filter(driver=request.user).select_related('passenger')[:30]
        return Response([
            {
                'id': ride.id,
                'origin': ride.origin,
                'destination': ride.destination,
                'origin_lat': float(ride.origin_lat),
                'origin_lng': float(ride.origin_lng),
                'destination_lat': float(ride.destination_lat),
                'destination_lng': float(ride.destination_lng),
                'passenger_name': ride.passenger.get_full_name() or ride.passenger.username,
                'vehicle_type': ride.vehicle_type,
                'driver_vehicle_brand': AccountProfile.objects.filter(user=request.user).values_list('vehicle_brand', flat=True).first() or None,
                'driver_vehicle_color': AccountProfile.objects.filter(user=request.user).values_list('vehicle_color', flat=True).first() or None,
                'driver_vehicle_plate': AccountProfile.objects.filter(user=request.user).values_list('vehicle_plate', flat=True).first() or None,
                'pickup_code': ride.pickup_code,
                'passenger_rating': ride.passenger_rating,
                'driver_rating': ride.driver_rating,
                'offer_amount': ride.offer_amount,
                'final_fare': ride.final_fare,
                'status': ride.status,
                'distance_km': float(ride.distance_km),
                'duration_minutes': ride.duration_minutes,
                'passenger_lat': float(ride.passenger_lat) if ride.passenger_lat is not None else None,
                'passenger_lng': float(ride.passenger_lng) if ride.passenger_lng is not None else None,
                'driver_lat': float(ride.driver_lat) if ride.driver_lat is not None else None,
                'driver_lng': float(ride.driver_lng) if ride.driver_lng is not None else None,
                'passenger_location_label': ride.passenger_location_label,
                'driver_location_label': ride.driver_location_label,
                'live_distance_km': RideSerializer(ride).data['live_distance_km'],
                'created_at': ride.created_at,
            }
            for ride in rides
        ])

class RideOfferCreateView(APIView):
    def post(self, request, ride_id):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden ofertar.'}, status=status.HTTP_403_FORBIDDEN)
        ride = get_object_or_404(Ride, id=ride_id)
        if timezone.now() >= ride.created_at + timedelta(minutes=5):
            return Response({'detail': 'La ventana de esta solicitud expiró.'}, status=status.HTTP_409_CONFLICT)
        if ride.passenger_id == request.user.id or ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
            return Response({'detail': 'Esta solicitud ya no admite ofertas.'}, status=status.HTTP_409_CONFLICT)
        driver_profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        if driver_profile.status != DriverProfile.Status.AVAILABLE:
            return Response({'detail': 'Debes estar disponible para ofertar.'}, status=status.HTTP_409_CONFLICT)
        try:
            amount = int(request.data.get('amount', 0))
        except (TypeError, ValueError):
            return Response({'detail': 'El monto debe ser un número entero.'}, status=status.HTTP_400_BAD_REQUEST)
        
        if amount <= 0:
            return Response({'detail': 'La oferta debe ser mayor que cero.'}, status=status.HTTP_400_BAD_REQUEST)
        required_reserve = (amount + 9) // 10
        profile = driver_profile
        if profile.wallet_balance - profile.reserved_balance < required_reserve:
            return Response({'detail': 'Saldo insuficiente para ofertar (requiere 10% de la tarifa).'}, status=status.HTTP_400_BAD_REQUEST)
        if RideOffer.objects.filter(ride=ride, driver=request.user, status=RideOffer.Status.PENDING).exists():
            return Response({'detail': 'Ya tienes una oferta vigente para esta solicitud.'}, status=status.HTTP_409_CONFLICT)
        
        offer = RideOffer.objects.create(
            ride=ride,
            driver=request.user,
            amount=amount,
            status=RideOffer.Status.PENDING
        )
        
        # update ride status
        if ride.status in (Ride.Status.SEARCHING, Ride.Status.REQUESTED):
            ride.status = Ride.Status.NEGOTIATING
            ride.save()
            
        return Response({'id': offer.id, 'amount': offer.amount, 'status': offer.status}, status=status.HTTP_201_CREATED)


class RideOfferAcceptView(APIView):
    def post(self, request, ride_id):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden aceptar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        ride = get_object_or_404(Ride, id=ride_id)
        if timezone.now() >= ride.created_at + timedelta(minutes=5):
            return Response({'detail': 'La ventana de esta solicitud expiró.'}, status=status.HTTP_409_CONFLICT)
        if ride.passenger_id == request.user.id or ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
            return Response({'detail': 'Esta solicitud ya no admite ofertas.'}, status=status.HTTP_409_CONFLICT)
        driver_profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        if driver_profile.status != DriverProfile.Status.AVAILABLE:
            return Response({'detail': 'Debes estar disponible para aceptar.'}, status=status.HTTP_409_CONFLICT)
        if RideOffer.objects.filter(ride=ride, driver=request.user, status=RideOffer.Status.PENDING).exists():
            return Response({'detail': 'Ya tienes una oferta vigente para esta solicitud.'}, status=status.HTTP_409_CONFLICT)

        offer = RideOffer.objects.create(
            ride=ride,
            driver=request.user,
            amount=ride.offer_amount,
            status=RideOffer.Status.PENDING,
        )
        if ride.status in (Ride.Status.SEARCHING, Ride.Status.REQUESTED):
            ride.status = Ride.Status.NEGOTIATING
            ride.save(update_fields=['status'])
        return Response({'id': offer.id, 'amount': offer.amount, 'status': offer.status}, status=status.HTTP_201_CREATED)


class RideRejectView(APIView):
    def post(self, request, ride_id):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden rechazar solicitudes.'}, status=status.HTTP_403_FORBIDDEN)
        ride = get_object_or_404(Ride, id=ride_id)
        if ride.status not in (Ride.Status.SEARCHING, Ride.Status.REQUESTED, Ride.Status.NEGOTIATING):
            return Response({'detail': 'Esta solicitud ya no está disponible.'}, status=status.HTTP_409_CONFLICT)
        RideOffer.objects.get_or_create(
            ride=ride,
            driver=request.user,
            defaults={'amount': ride.offer_amount, 'status': RideOffer.Status.REJECTED},
        )
        return Response({'status': 'rejected'})


class RideVerifyPickupCodeView(APIView):
    def post(self, request, ride_id):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden iniciar viajes.'}, status=status.HTTP_403_FORBIDDEN)
        code = str(request.data.get('code', '')).strip().upper()
        with transaction.atomic():
            ride = get_object_or_404(
                Ride.objects.select_for_update(),
                id=ride_id,
                driver=request.user,
            )
            if ride.status != Ride.Status.ACCEPTED:
                return Response({'detail': 'El viaje no está listo para iniciar.'}, status=status.HTTP_409_CONFLICT)
            if not ride.pickup_code or code != ride.pickup_code:
                return Response({'detail': 'El código del pasajero no coincide.'}, status=status.HTTP_400_BAD_REQUEST)
            ride.status = Ride.Status.EN_ROUTE
            ride.save(update_fields=['status'])
        return Response({'status': ride.status})


class RideUpdateStatusView(APIView):
    def post(self, request, ride_id):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden actualizar viajes.'}, status=status.HTTP_403_FORBIDDEN)
        new_status = request.data.get('status')
        if new_status not in [choice[0] for choice in Ride.Status.choices]:
            return Response({'detail': 'Estado inválido.'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            ride = get_object_or_404(Ride.objects.select_for_update(), id=ride_id, driver=request.user)
            if ride.status == Ride.Status.VALIDATED:
                return Response({'status': ride.status, 'final_fare': ride.final_fare})
            allowed_transitions = {
                Ride.Status.ACCEPTED: {Ride.Status.EN_ROUTE},
                Ride.Status.DRIVER_SELECTED: {Ride.Status.EN_ROUTE},
                Ride.Status.EN_ROUTE: {Ride.Status.ARRIVED},
                Ride.Status.ARRIVED: {Ride.Status.IN_PROGRESS},
                Ride.Status.IN_PROGRESS: {Ride.Status.COMPLETED},
                Ride.Status.COMPLETED: {Ride.Status.VALIDATED},
            }
            if new_status != Ride.Status.CANCELLED and new_status not in allowed_transitions.get(ride.status, set()):
                return Response({'detail': 'La transición de estado no es válida.'}, status=status.HTTP_409_CONFLICT)
            if new_status == Ride.Status.VALIDATED:
                from passengers.models import PassengerProfile

                profile = DriverProfile.objects.select_for_update().get(user=request.user)
                final_fare = ride.final_fare or ride.offer_amount or ride.estimated_price
                debit = (final_fare + 9) // 10
                if profile.reserved_balance < debit or profile.wallet_balance < debit:
                    return Response({'detail': 'La reserva de Bolsa IR no cubre el débito final.'}, status=status.HTTP_409_CONFLICT)
                profile.reserved_balance -= debit
                profile.wallet_balance -= debit
                profile.add_points(debit // 10, f'PI conductor por viaje validado #{ride.id}')
                passenger_profile, _ = PassengerProfile.objects.get_or_create(user=ride.passenger)
                passenger_profile.add_points(final_fare // 20, f'PI pasajero por viaje validado #{ride.id}')
                ride.final_fare = final_fare
                ride.save(update_fields=['final_fare'])
                profile.status = DriverProfile.Status.AVAILABLE
                profile.save(update_fields=['reserved_balance', 'wallet_balance', 'status'])
            ride.status = new_status
            ride.save(update_fields=['status'])
            return Response({'status': ride.status, 'final_fare': ride.final_fare})

class WalletRechargeView(APIView):
    def post(self, request):
        if not _is_driver(request):
            return Response({'detail': 'Solo los conductores pueden recargar Bolsa IR.'}, status=status.HTTP_403_FORBIDDEN)
        amount = int(request.data.get('amount', 0))
        if amount < 5000:
            return Response({'detail': 'Mínimo COP 5.000'}, status=status.HTTP_400_BAD_REQUEST)
        
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        profile.wallet_balance += amount
        profile.save()
        return Response({'wallet_balance': profile.wallet_balance})
