import hashlib
from types import SimpleNamespace

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import DatabaseError, IntegrityError, transaction
from django.utils import timezone
from rest_framework import permissions, serializers
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle
from rest_framework.views import APIView

from coredata.face_security import (
    CHALLENGE_MAX_AGE, consume_challenge, create_challenge, decrypt_template,
    encrypt_template, next_verification_date,
)
from coredata.face_service import FaceError, analyze_face, face_service_available
from coredata.models import FaceEnrollment, UserProfilePhoto, profile_photo_upload_to
from coredata.serializers import ProfilePhotoSerializer


class FaceThrottle(UserRateThrottle):
    scope = 'face_verification'
    rate = '6/minute'


class FaceChallengeThrottle(UserRateThrottle):
    scope = 'face_challenge'
    rate = '12/minute'


class FaceCaptureSerializer(serializers.Serializer):
    selfie = serializers.FileField()
    challenge_token = serializers.CharField(max_length=1500)

    def validate_selfie(self, value):
        return ProfilePhotoSerializer().validate_photo(value)


class FaceEnrollmentSerializer(FaceCaptureSerializer):
    document = serializers.FileField()
    consent = serializers.BooleanField()
    consent_version = serializers.CharField(max_length=40)

    def validate_document(self, value):
        return ProfilePhotoSerializer().validate_photo(value)


def _parse_capture(request, *, enrollment=False):
    serializer = (FaceEnrollmentSerializer if enrollment else FaceCaptureSerializer)(data=request.data)
    try:
        serializer.is_valid(raise_exception=True)
    except serializers.ValidationError as error:
        if enrollment and any(field in error.detail for field in ('consent', 'consent_version')):
            raise FaceError('consent_required', 'Acepta el uso de tus imágenes para comprobar la coincidencia facial.', 400) from None
        if 'challenge_token' in error.detail:
            raise FaceError('invalid_challenge', 'Vuelve a preparar la captura para continuar.', 400) from None
        raise FaceError('invalid_image', 'Usa imágenes JPG, PNG o WebP válidas de hasta 5 MB cada una.', 400) from None
    data = serializer.validated_data
    if enrollment and (not data['consent'] or data['consent_version'] != settings.FACE_CONSENT_VERSION):
        raise FaceError('consent_required', 'Acepta el uso de tus imágenes para comprobar la coincidencia facial.', 400)
    consume_challenge(data['challenge_token'], request.user.pk, 'enroll' if enrollment else 'verify')
    return data


def _photo_url(user_id):
    photo = UserProfilePhoto.objects.filter(user_id=user_id).first()
    if not photo or not photo.image:
        return None
    try:
        return photo.image.url
    except FileNotFoundError:
        return None


def face_status(user, *, enrollment=None, available=None):
    record = enrollment if enrollment is not None else FaceEnrollment.objects.filter(user_id=user.pk).first()
    due = not record or record.verification_due_at <= timezone.now()
    return {
        'enrolled': bool(record),
        'state': 'not_enrolled' if not record else ('due' if due else 'verified'),
        'available': (bool(settings.FACE_TEMPLATE_KEY) and face_service_available()) if available is None else available,
        'required': settings.FACE_VERIFICATION_REQUIRED,
        'verification_due': due,
        'consent_version': settings.FACE_CONSENT_VERSION,
        'enrolled_at': record.enrolled_at.isoformat() if record else None,
        'last_verified_at': record.last_verified_at.isoformat() if record else None,
        'verification_due_at': record.verification_due_at.isoformat() if record else None,
        'photo_url': _photo_url(user.pk),
        'method': 'document_then_selfies',
        'limitations': 'Compara rostros y aplica detección básica de suplantación. No certifica la autenticidad del documento ni la identidad civil.',
    }


def _store_avatar(user_id, crop):
    name = profile_photo_upload_to(SimpleNamespace(user_id=user_id), 'face.jpg')
    try:
        return default_storage.save(name, ContentFile(crop))
    except Exception:
        raise FaceError('service_unavailable', 'No pudimos guardar tu foto. Inténtalo de nuevo.', 503) from None


def _discard_avatar(name):
    if name:
        try:
            default_storage.delete(name)
        except Exception:
            # A failed new-file cleanup must never expose image bytes or credentials.
            pass


def _set_avatar(user_id, new_name):
    photo, _ = UserProfilePhoto.objects.select_for_update().get_or_create(user_id=user_id)
    old_name = photo.image.name if photo.image else None
    photo.image.name = new_name
    photo.save(update_fields=['image', 'updated_at'])
    if old_name and old_name != new_name:
        transaction.on_commit(lambda: _discard_avatar(old_name))


class FaceStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            return Response(face_status(request.user))
        except DatabaseError:
            raise FaceError('service_unavailable', 'La comprobación facial se está preparando. Inténtalo de nuevo.', 503) from None

    def delete(self, request):
        record = FaceEnrollment.objects.filter(user_id=request.user.pk).first()
        if not record:
            return Response(status=204)
        current_photo = UserProfilePhoto.objects.filter(user_id=request.user.pk, image=record.avatar_name).first()
        if current_photo and record.avatar_name:
            try:
                current_photo.image.storage.delete(record.avatar_name)
            except Exception:
                raise FaceError('service_unavailable', 'No pudimos eliminar la foto asociada. Vuelve a intentarlo.', 503) from None
        with transaction.atomic():
            if current_photo:
                UserProfilePhoto.objects.filter(pk=current_photo.pk, image=record.avatar_name).delete()
            FaceEnrollment.objects.filter(user_id=request.user.pk).delete()
        return Response(status=204)


class FaceChallengeView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [FaceChallengeThrottle]

    def post(self, request):
        purpose = request.data.get('purpose')
        if purpose not in {'enroll', 'verify'}:
            raise FaceError('invalid_challenge', 'Indica el tipo de comprobación que vas a realizar.', 400)
        return Response({'challenge_token': create_challenge(request.user.pk, purpose), 'expires_in': CHALLENGE_MAX_AGE})


class FaceEnrollView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [FaceThrottle]

    def post(self, request):
        if FaceEnrollment.objects.filter(user_id=request.user.pk).exists():
            raise FaceError('face_already_enrolled', 'Ya tienes un registro facial. Comprueba tu selfie o elimina el registro antes de cambiarlo.', 409)
        data = _parse_capture(request, enrollment=True)
        selfie = data['selfie'].read()
        result = analyze_face(selfie=selfie, document=data['document'].read())
        if not result['verified']:
            raise FaceError('face_mismatch', 'El rostro de la selfie no coincide suficientemente con el documento. Revisa la luz y el retrato del documento.')
        now = timezone.now()
        template = {
            'document': result['document_embedding'], 'selfies': [result['embedding']],
            'accepted_selfie_hashes': [hashlib.sha256(selfie).hexdigest()],
            'model': 'SFace', 'detector': 'opencv',
        }
        avatar_name = _store_avatar(request.user.pk, result['crop_bytes'])
        try:
            with transaction.atomic():
                record = FaceEnrollment.objects.create(
                    user_id=request.user.pk, encrypted_template=encrypt_template(template),
                    consent_version=data['consent_version'], consented_at=now,
                    last_verified_at=now, verification_due_at=next_verification_date(now), avatar_name=avatar_name,
                )
                _set_avatar(request.user.pk, avatar_name)
        except IntegrityError:
            _discard_avatar(avatar_name)
            raise FaceError('face_already_enrolled', 'Tu registro ya se actualizó. Vuelve a cargar la pantalla.', 409) from None
        except Exception:
            _discard_avatar(avatar_name)
            raise
        return Response({**face_status(request.user, enrollment=record, available=True), 'verified': True}, status=201)


class FaceVerifyView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [FaceThrottle]

    def post(self, request):
        record = FaceEnrollment.objects.filter(user_id=request.user.pk).first()
        if not record:
            raise FaceError('face_not_enrolled', 'Primero comprueba la selfie con tu documento.', 409)
        data = _parse_capture(request)
        selfie = data['selfie'].read()
        fingerprint = hashlib.sha256(selfie).hexdigest()
        template = decrypt_template(record.encrypted_template)
        if fingerprint in template.get('accepted_selfie_hashes', []):
            raise FaceError('selfie_replayed', 'Esa captura ya se utilizó. Toma una selfie nueva con la cámara.', 409)
        result = analyze_face(selfie=selfie, references=template['selfies'])
        if not result['verified']:
            return Response({**face_status(request.user, enrollment=record, available=True), 'verified': False,
                             'code': 'face_mismatch', 'detail': 'La selfie no coincide suficientemente con tus capturas anteriores. Vuelve a intentarlo.'})
        now = timezone.now()
        template['selfies'] = (template['selfies'] + [result['embedding']])[-3:]
        template['accepted_selfie_hashes'] = (template.get('accepted_selfie_hashes', []) + [fingerprint])[-12:]
        avatar_name = _store_avatar(request.user.pk, result['crop_bytes'])
        try:
            with transaction.atomic():
                locked = FaceEnrollment.objects.select_for_update().filter(user_id=request.user.pk).first()
                if not locked or locked.last_verified_at != record.last_verified_at:
                    raise FaceError('reference_changed', 'Tu registro cambió durante la captura. Vuelve a intentarlo.', 409)
                locked.encrypted_template = encrypt_template(template)
                locked.last_verified_at = now
                locked.verification_due_at = next_verification_date(now)
                locked.avatar_name = avatar_name
                locked.save(update_fields=['encrypted_template', 'last_verified_at', 'verification_due_at', 'avatar_name'])
                _set_avatar(request.user.pk, avatar_name)
        except Exception:
            _discard_avatar(avatar_name)
            raise
        return Response({**face_status(request.user, enrollment=locked, available=True), 'verified': True})
