from datetime import timedelta

from django.core.signing import BadSignature, SignatureExpired, TimestampSigner
from django.conf import settings
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import APIException, AuthenticationFailed
from rest_framework import HTTP_HEADER_ENCODING

from .models import SupabaseIdentity, Usuario
from .supabase import verify_access_token


INACTIVE_STATES = {'inactive', 'inactivo', 'inactiva', 'blocked', 'bloqueado', 'suspended', 'suspendido'}


class ProfileRequired(APIException):
    status_code = 409
    default_detail = 'Completa tu perfil para empezar a usar IR.'
    default_code = 'profile_required'


class LegacyLinkRequired(APIException):
    status_code = 409
    default_detail = {'detail': 'Vincula tu cuenta anterior de IR para conservar tus datos.',
                      'code': 'legacy_link_required'}


class SupabaseJWTAuthentication(BaseAuthentication):
    def authenticate(self, request):
        header = get_authorization_header(request).split()
        if not header or header[0].lower() != b'bearer':
            return None
        if len(header) != 2:
            raise AuthenticationFailed('El encabezado de acceso no es valido.')
        try:
            claims = verify_access_token(header[1].decode(HTTP_HEADER_ENCODING))
            identity = SupabaseIdentity.objects.select_related('user').get(auth_user_id=claims['sub'])
        except (UnicodeError, ValueError):
            raise AuthenticationFailed('El token de acceso no es valido.') from None
        except SupabaseIdentity.DoesNotExist:
            if claims.get('email') and Usuario.objects.filter(correo__iexact=claims['email']).exists():
                raise LegacyLinkRequired() from None
            raise ProfileRequired() from None
        if (identity.user.estado or '').strip().lower() in INACTIVE_STATES:
            raise AuthenticationFailed('La cuenta no esta activa.')
        from .face_security import enforce_face_verification
        enforce_face_verification(request, identity.user)
        return identity.user, claims

    def authenticate_header(self, request):
        return 'Bearer'


class SignedTokenAuthentication(BaseAuthentication):
    keyword = b'token'
    signer = TimestampSigner(salt='ir.api.auth')
    max_age = int(timedelta(days=7).total_seconds())

    def authenticate(self, request):
        header = get_authorization_header(request).split()
        if not header:
            return None
        if header[0].lower() != self.keyword:
            return None
        if not settings.ALLOW_LEGACY_AUTH:
            raise AuthenticationFailed('Inicia sesion de nuevo con Supabase.')
        if len(header) != 2:
            raise AuthenticationFailed('El encabezado de autenticación no es válido.')
        try:
            token = header[1].decode(HTTP_HEADER_ENCODING)
            user_id = self.signer.unsign(token, max_age=self.max_age)
            user = Usuario.objects.get(pk=user_id)
        except (BadSignature, SignatureExpired, UnicodeError, Usuario.DoesNotExist, ValueError):
            raise AuthenticationFailed('La sesión expiró o no es válida.')
        if (user.estado or '').strip().lower() in INACTIVE_STATES:
            raise AuthenticationFailed('La cuenta no está activa.')
        from .face_security import enforce_face_verification
        enforce_face_verification(request, user)
        return user, token

    def authenticate_header(self, request):
        return 'Token'
