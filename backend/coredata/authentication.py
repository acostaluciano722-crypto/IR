from datetime import timedelta

from django.core.signing import BadSignature, SignatureExpired, TimestampSigner
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed
from rest_framework import HTTP_HEADER_ENCODING

from .models import Usuario


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
        if len(header) != 2:
            raise AuthenticationFailed('El encabezado de autenticación no es válido.')
        try:
            token = header[1].decode(HTTP_HEADER_ENCODING)
            user_id = self.signer.unsign(token, max_age=self.max_age)
            user = Usuario.objects.get(pk=user_id)
        except (BadSignature, SignatureExpired, UnicodeError, Usuario.DoesNotExist, ValueError):
            raise AuthenticationFailed('La sesión expiró o no es válida.')
        if (user.estado or '').strip().lower() in {
            'inactive', 'inactivo', 'inactiva', 'blocked', 'bloqueado', 'suspended', 'suspendido',
        }:
            raise AuthenticationFailed('La cuenta no está activa.')
        return user, token

    def authenticate_header(self, request):
        return 'Token'