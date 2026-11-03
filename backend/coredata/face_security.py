"""Own-user consent, encrypted references, challenge replay protection and expiry."""

import calendar
import json
import secrets

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings
from django.core import signing
from django.core.cache import cache
from django.utils import timezone
from redis.exceptions import RedisError

from coredata.face_service import FaceError

CHALLENGE_MAX_AGE = 180
EXEMPT_PATHS = {
    '/api/health/', '/api/auth/me/', '/api/auth/profile/', '/api/auth/legacy-migrate/',
    '/api/auth/link-legacy/', '/api/auth/login/', '/api/auth/register/',
}


def next_verification_date(verified_at):
    """Two calendar months in the product timezone, clamping e.g. Dec 31 to Feb 28."""
    local = timezone.localtime(verified_at)
    month_index = local.year * 12 + local.month - 1 + 2
    year, zero_month = divmod(month_index, 12)
    month = zero_month + 1
    day = min(local.day, calendar.monthrange(year, month)[1])
    return local.replace(year=year, month=month, day=day)


def _cipher():
    key = settings.FACE_TEMPLATE_KEY
    if not key:
        raise FaceError('service_unavailable', 'Falta configurar la protección del registro facial.', 503)
    try:
        return Fernet(key)
    except (ValueError, TypeError):
        raise FaceError('service_unavailable', 'Falta configurar la protección del registro facial.', 503) from None


def encrypt_template(template):
    return _cipher().encrypt(json.dumps(template, separators=(',', ':'), allow_nan=False).encode())


def decrypt_template(value):
    try:
        result = json.loads(_cipher().decrypt(bytes(value)))
        if not isinstance(result.get('selfies'), list) or not result['selfies']:
            raise ValueError('Missing reference')
        return result
    except (InvalidToken, ValueError, TypeError, KeyError):
        raise FaceError('reference_unavailable', 'No pudimos leer tu registro facial. Elimínalo y vuelve a registrarlo.', 409) from None


def create_challenge(user_id, purpose):
    return signing.dumps({'user': str(user_id), 'purpose': purpose, 'nonce': secrets.token_urlsafe(24)},
                         salt='ir.face.challenge.v1', compress=False)


def consume_challenge(token, user_id, purpose):
    try:
        payload = signing.loads(token, salt='ir.face.challenge.v1', max_age=CHALLENGE_MAX_AGE)
        if payload['user'] != str(user_id) or payload['purpose'] != purpose or not payload['nonce']:
            raise ValueError('Wrong challenge')
        claimed = cache.add('face-challenge-used:' + payload['nonce'], True, CHALLENGE_MAX_AGE + 15)
        if not claimed:
            raise ValueError('Reused challenge')
    except (signing.BadSignature, ValueError, TypeError, KeyError):
        raise FaceError('invalid_challenge', 'La captura caducó. Vuelve a tomar la selfie para continuar.', 400) from None
    except (OSError, RedisError):
        raise FaceError('service_unavailable', 'No pudimos preparar una captura segura. Vuelve a intentarlo.', 503) from None


def enforce_face_verification(request, user):
    """Authentication-level gate cannot be bypassed by a view permission override."""
    if not settings.FACE_VERIFICATION_REQUIRED or not request.path.startswith('/api/'):
        return
    if request.path in EXEMPT_PATHS or request.path.startswith('/api/profile/face/'):
        return
    from coredata.models import FaceEnrollment
    current = FaceEnrollment.objects.filter(user_id=user.pk, verification_due_at__gt=timezone.now()).exists()
    if not current:
        raise FaceError('face_verification_required', 'Completa la comprobación facial para continuar.', 403)
