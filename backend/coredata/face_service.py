"""Private, bounded HTTP boundary to the isolated DeepFace CPU service."""

import base64
import json
import math
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from django.conf import settings
from rest_framework.exceptions import APIException


class FaceError(APIException):
    def __init__(self, code, detail, status=422):
        self.status_code = status
        super().__init__({'detail': detail, 'code': code})


MESSAGES = {
    'face_not_found': 'No encontramos un rostro claro. Acércate y mejora la iluminación.',
    'document_face_not_found': 'No encontramos la foto del rostro en el documento. Acerca la parte frontal y evita reflejos.',
    'multiple_faces': 'Debe aparecer solo tu rostro en la selfie.',
    'ambiguous_document': 'Encuadra el retrato principal del documento para que se vea con claridad.',
    'spoof_detected': 'No pudimos comprobar una captura real. Usa la cámara y evita mostrar una foto o pantalla.',
    'image_quality': 'La imagen está demasiado oscura, borrosa o alejada. Inténtalo con mejor luz.',
    'invalid_image': 'Usa una imagen JPG, PNG o WebP válida de hasta 5 MB.',
    'service_busy': 'Hay una comprobación en curso. Espera un momento e inténtalo de nuevo.',
    'service_unavailable': 'La comprobación facial no está disponible. Inténtalo de nuevo en unos minutos.',
}


def _service_url():
    base = settings.FACE_SERVICE_URL
    parsed = urlparse(base)
    if not base or not settings.FACE_SERVICE_TOKEN:
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password:
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    if parsed.scheme == 'http' and parsed.hostname not in {'face-inference', 'localhost', '127.0.0.1', 'host.docker.internal'}:
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    return base


def face_service_available():
    try:
        with urlopen(_service_url() + '/health', timeout=2) as response:
            return json.loads(response.read(4096)).get('ready') is True
    except (FaceError, OSError, URLError, ValueError):
        return False


def _embedding(value):
    if not isinstance(value, list) or len(value) != 128:
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    if any(isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) for item in value):
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    return value


def analyze_face(*, selfie, document=None, references=None):
    body = {'selfie': base64.b64encode(selfie).decode('ascii')}
    if document is not None:
        body['document'] = base64.b64encode(document).decode('ascii')
        path = '/v1/enroll'
    else:
        body['references'] = references
        path = '/v1/verify'
    request = Request(_service_url() + path, method='POST', data=json.dumps(body).encode(),
                      headers={'Content-Type': 'application/json', 'X-IR-Face-Token': settings.FACE_SERVICE_TOKEN})
    try:
        with urlopen(request, timeout=settings.FACE_SERVICE_TIMEOUT) as response:
            payload = response.read(1024 * 1024 + 1)
            if len(payload) > 1024 * 1024:
                raise ValueError('Oversized inference response')
            result = json.loads(payload)
    except HTTPError as error:
        try:
            code = json.loads(error.read(4096)).get('code')
        except (ValueError, AttributeError):
            code = None
        if code not in MESSAGES:
            code = 'service_unavailable'
        raise FaceError(code, MESSAGES[code], 503 if code in {'service_unavailable', 'service_busy'} else 422) from None
    except (OSError, URLError, ValueError):
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503) from None
    if not isinstance(result, dict) or not isinstance(result.get('verified'), bool):
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503)
    if not result['verified']:
        return {'verified': False}
    try:
        crop = base64.b64decode(result['crop'], validate=True)
        if not crop.startswith(b'\xff\xd8\xff') or len(crop) > 1024 * 1024:
            raise ValueError('Invalid crop')
        result['crop_bytes'] = crop
        result['embedding'] = _embedding(result['embedding'])
        if document is not None:
            result['document_embedding'] = _embedding(result['document_embedding'])
        if result.get('model') != 'SFace' or result.get('anti_spoofing') is not True:
            raise ValueError('Unexpected inference method')
    except (KeyError, TypeError, ValueError):
        raise FaceError('service_unavailable', MESSAGES['service_unavailable'], 503) from None
    return result
