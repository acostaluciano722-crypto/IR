"""Server-only Supabase HTTP boundary. Secrets never reach Flutter."""

import json
from functools import lru_cache
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import jwt
from django.conf import settings
from rest_framework.exceptions import APIException, AuthenticationFailed


class SupabaseUnavailable(APIException):
    status_code = 503
    default_detail = 'No pudimos conectar con el servicio de acceso. Intenta de nuevo.'


class SupabaseRequestError(Exception):
    def __init__(self, status, code):
        self.status = status
        self.code = code
        super().__init__(f'Supabase HTTP {status}: {code}')


def request_supabase(path, *, method='GET', body=None, token=None, admin=False,
                     raw=None, content_type='application/json', return_bytes=False):
    base = settings.SUPABASE_URL
    parsed = urlparse(base)
    if parsed.scheme != 'https' and parsed.hostname not in {'localhost', '127.0.0.1', 'host.docker.internal', 'supabase_kong_ir-supabase'}:
        raise SupabaseUnavailable('La conexion con Supabase debe usar HTTPS.')
    key = settings.SUPABASE_SECRET_KEY if admin else settings.SUPABASE_PUBLISHABLE_KEY
    if not base or not key:
        raise SupabaseUnavailable('Falta configurar Supabase en el servidor.')
    headers = {'apikey': key, 'Content-Type': content_type}
    if token or admin:
        headers['Authorization'] = f'Bearer {token or key}'
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    try:
        with urlopen(Request(base + path, data=data, headers=headers, method=method), timeout=8) as response:
            payload = response.read()
            if return_bytes:
                return payload
            return json.loads(payload) if payload else {}
    except HTTPError as error:
        try:
            payload = json.loads(error.read())
            code = payload.get('error_code') or payload.get('code') or 'request_failed'
        except (ValueError, AttributeError):
            code = 'request_failed'
        raise SupabaseRequestError(error.code, code) from None
    except (URLError, TimeoutError, ValueError):
        raise SupabaseUnavailable() from None


@lru_cache(maxsize=8)
def jwks_client(url):
    return jwt.PyJWKClient(url + '/auth/v1/.well-known/jwks.json', lifespan=300, timeout=5)


def verified_auth_user(token):
    try:
        user = request_supabase('/auth/v1/user', token=token)
    except SupabaseRequestError as error:
        if error.status in {401, 403}:
            raise AuthenticationFailed('La sesion expiro. Inicia sesion de nuevo.') from None
        raise SupabaseUnavailable() from None
    if not user.get('id') or user.get('is_anonymous') or user.get('role') != 'authenticated':
        raise AuthenticationFailed('Inicia sesion con una cuenta verificada.')
    return user


def verify_access_token(token):
    if not settings.SUPABASE_AUTH_ENABLED:
        raise AuthenticationFailed('Supabase Auth no esta configurado.')
    try:
        header = jwt.get_unverified_header(token)
        algorithm = header.get('alg')
        if algorithm == 'HS256':
            # Legacy projects verify on the Auth server; no shared signing secret is needed.
            user = verified_auth_user(token)
            return {'sub': user['id'], 'email': user.get('email'), 'role': user['role']}
        if algorithm not in {'ES256', 'RS256'} or not header.get('kid'):
            raise AuthenticationFailed('El token de acceso no es valido.')
        key = jwks_client(settings.SUPABASE_URL).get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token, key, algorithms=[algorithm], audience='authenticated',
            issuer=settings.SUPABASE_JWT_ISSUER, leeway=15,
            options={'require': ['exp', 'iat', 'sub', 'aud', 'iss']},
        )
        if claims.get('role') != 'authenticated' or claims.get('is_anonymous'):
            raise AuthenticationFailed('Inicia sesion con una cuenta verificada.')
        return claims
    except jwt.PyJWKClientConnectionError:
        raise SupabaseUnavailable() from None
    except jwt.PyJWTError:
        raise AuthenticationFailed('La sesion expiro o el token no es valido.') from None
