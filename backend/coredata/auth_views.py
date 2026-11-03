import uuid

from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import permissions, serializers
from rest_framework.authentication import get_authorization_header
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView

from coredata.authentication import INACTIVE_STATES
from coredata.models import DriverProfile, PassengerProfile, SupabaseIdentity, Usuario, Vehicle
from coredata.supabase import SupabaseRequestError, SupabaseUnavailable, request_supabase, verified_auth_user, verify_access_token


def user_for_api(user):
    from passengers.api_views import PassengerMeView
    driver = DriverProfile.objects.select_related('rank').filter(user=user).first()
    passenger = PassengerProfile.objects.select_related('rank').filter(user=user).first()
    profile = driver or passenger
    return {
        'id': str(user.pk), 'name': user.get_full_name(), 'username': user.correo,
        'role': user.rol, 'points': profile.points or 0 if profile else 0,
        'tier': profile.rank.nombre if profile and profile.rank_id else 'Inicial',
        'photo_url': PassengerMeView._photo_url_for_user(user),
    }


class CurrentUserView(APIView):
    def get(self, request):
        return Response(user_for_api(request.user))


class OnboardingSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=20)
    role = serializers.ChoiceField(choices=['passenger', 'driver'])
    document_number = serializers.CharField(max_length=20, required=False, allow_blank=True)
    vehicle_type = serializers.CharField(max_length=30, required=False, allow_blank=True)
    vehicle_plate = serializers.CharField(max_length=10, required=False, allow_blank=True)

    def validate(self, data):
        if Usuario.objects.filter(celular=data['phone']).exists():
            raise serializers.ValidationError({'phone': 'Este celular ya esta registrado.'})
        if data['role'] == 'driver':
            missing = {field: 'Completa este campo.' for field in ('document_number', 'vehicle_type', 'vehicle_plate') if not data.get(field)}
            if missing:
                raise serializers.ValidationError(missing)
        return data


class CompleteProfileView(APIView):
    # A verified Auth session can exist before its domain profile.
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        header = get_authorization_header(request).split()
        if len(header) != 2 or header[0].lower() != b'bearer':
            raise AuthenticationFailed('Inicia sesion antes de completar el perfil.')
        try:
            token = header[1].decode()
            claims = verify_access_token(token)
            auth_user = verified_auth_user(token)
            auth_id = uuid.UUID(claims['sub'])
        except (ValueError, UnicodeError):
            raise AuthenticationFailed('La sesion no es valida.') from None
        if auth_user['id'] != str(auth_id) or not auth_user.get('email_confirmed_at') or not auth_user.get('email'):
            raise AuthenticationFailed('Confirma tu correo antes de continuar.')
        existing = SupabaseIdentity.objects.select_related('user').filter(pk=auth_id).first()
        if existing:
            if (existing.user.estado or '').strip().lower() in INACTIVE_STATES:
                raise AuthenticationFailed('La cuenta no esta activa.')
            return Response(user_for_api(existing.user))
        email = auth_user['email'].strip().lower()
        if Usuario.objects.filter(correo__iexact=email).exists():
            return Response({'detail': 'Vincula tu cuenta anterior de IR para conservar tus datos.', 'code': 'legacy_link_required'}, status=409)
        serializer = OnboardingSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        names = data['name'].split(' ', 1)
        try:
            with transaction.atomic():
                user = Usuario.objects.create(
                    id=auth_id, nombres=names[0], apellidos=names[1] if len(names) > 1 else '',
                    correo=email, celular=data['phone'], rol=data['role'],
                    contrasena_hash=make_password(None), estado='active', fecha_creacion=timezone.now(),
                )
                if data['role'] == 'passenger':
                    PassengerProfile.objects.create(id=uuid.uuid4(), user=user, points=0, total_rides=0, rating=0, rating_count=0)
                else:
                    profile = DriverProfile.objects.create(
                        id=uuid.uuid4(), user=user, status=DriverProfile.Status.OFFLINE,
                        document_number=data['document_number'], points=0, total_rides=0,
                        wallet_balance=0, reserved_balance=0, rating=0, rating_count=0,
                    )
                    Vehicle.objects.create(
                        id=uuid.uuid4(), driver=profile, plate=data['vehicle_plate'].upper(),
                        category=data['vehicle_type'], status='active',
                    )
                SupabaseIdentity.objects.create(auth_user_id=auth_id, user=user)
        except IntegrityError:
            return Response({'detail': 'El perfil ya existe. Actualiza la pantalla para continuar.'}, status=409)
        return Response(user_for_api(user), status=201)


class MigrationThrottle(AnonRateThrottle):
    rate = '5/minute'


class LegacyPasswordMigrationView(APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]
    throttle_classes = [MigrationThrottle]

    def post(self, request):
        if not settings.SUPABASE_AUTH_ENABLED or not settings.SUPABASE_SECRET_KEY:
            raise SupabaseUnavailable()
        identifier = str(request.data.get('username', '')).strip().lower()
        password = request.data.get('password', '')
        if not isinstance(password, str) or len(password) > 1024:
            raise AuthenticationFailed('Credenciales invalidas.')
        with transaction.atomic():
            user = Usuario.objects.select_for_update().filter(Q(correo__iexact=identifier) | Q(celular=identifier)).first()
            if not user or not user.check_password(password) or (user.estado or '').lower() in INACTIVE_STATES:
                # Run the default hasher for unknown users too.
                if not user:
                    make_password(password)
                raise AuthenticationFailed('Credenciales invalidas.')
            if SupabaseIdentity.objects.filter(user=user).exists():
                raise AuthenticationFailed('Usa el acceso de Supabase o recupera tu contraseña.')
            try:
                serializers.EmailField().run_validation(user.correo)
            except serializers.ValidationError:
                return Response({'detail': 'Esta cuenta necesita un correo valido antes de migrar. Contacta con soporte.'}, status=400)
            try:
                created = request_supabase('/auth/v1/admin/users', method='POST', admin=True, body={
                    'id': str(user.pk), 'email': user.correo, 'password': password,
                    'email_confirm': False, 'user_metadata': {'full_name': user.get_full_name()},
                })
            except SupabaseRequestError:
                # Recover only a previously created identity with the same immutable UUID.
                try:
                    created = request_supabase(f'/auth/v1/admin/users/{user.pk}', admin=True)
                except SupabaseRequestError:
                    return Response({'detail': 'No pudimos vincular la cuenta. Entra con Google o recupera tu contraseña y contacta con soporte para conservar tu perfil.'}, status=409)
                if created.get('email', '').lower() != user.correo.lower():
                    raise AuthenticationFailed('No pudimos verificar la cuenta anterior.')
            auth_id = created.get('id')
            if not auth_id or auth_id != str(user.pk):
                raise SupabaseUnavailable()
            SupabaseIdentity.objects.create(auth_user_id=auth_id, user=user)
            user.contrasena_hash = make_password(None)
            user.save(update_fields=['contrasena_hash'])
        # Flutter sends confirmation through the SDK, preserving its PKCE verifier.
        return Response({'detail': 'Revisa tu correo y confirma tu cuenta. Tus viajes, puntos y saldos se conservan.',
                         'confirmation_email': user.correo}, status=202)


class LinkLegacyAccountView(APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]
    throttle_classes = [MigrationThrottle]

    def post(self, request):
        header = get_authorization_header(request).split()
        if len(header) != 2 or header[0].lower() != b'bearer':
            raise AuthenticationFailed('Inicia sesion para vincular tu cuenta.')
        try:
            token = header[1].decode()
            claims = verify_access_token(token)
            auth_user = verified_auth_user(token)
            auth_id = uuid.UUID(claims['sub'])
        except (ValueError, UnicodeError):
            raise AuthenticationFailed('La sesion no es valida.') from None
        if auth_user['id'] != str(auth_id) or not auth_user.get('email_confirmed_at'):
            raise AuthenticationFailed('Confirma tu correo para continuar.')
        password = request.data.get('password', '')
        if not isinstance(password, str) or not password or len(password) > 1024:
            raise AuthenticationFailed('Escribe tu contraseña anterior de IR.')
        with transaction.atomic():
            user = Usuario.objects.select_for_update().filter(correo__iexact=auth_user.get('email', '')).first()
            if not user or not user.check_password(password) or (user.estado or '').lower() in INACTIVE_STATES:
                raise AuthenticationFailed('La contraseña anterior no es correcta.')
            if SupabaseIdentity.objects.filter(Q(user=user) | Q(auth_user_id=auth_id)).exists():
                return Response({'detail': 'La cuenta ya esta vinculada. Inicia sesion de nuevo.'}, status=409)
            SupabaseIdentity.objects.create(auth_user_id=auth_id, user=user)
            user.contrasena_hash = make_password(None)
            user.save(update_fields=['contrasena_hash'])
        return Response(user_for_api(user))
