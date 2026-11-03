"""Private, CPU-bounded DeepFace verification. Never writes submitted images."""

import base64
import binascii
import hmac
import io
import math
import os
import threading
from functools import wraps

from flask import Flask, jsonify, request

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MODEL = 'SFace'
DETECTOR = 'opencv'


class CaptureError(Exception):
    def __init__(self, code):
        self.code = code


class FaceEngine:
    """Only verification/representation: never attribute inference or identity search."""

    def __init__(self):
        self.ready = False
        self.warming = False
        self.failed = False
        self.lock = threading.BoundedSemaphore(1)
        self.deepface = None

    def warm(self):
        self.warming = True
        try:
            import cv2
            from deepface import DeepFace
            cv2.setNumThreads(1)
            DeepFace.build_model(MODEL)
            DeepFace.build_model(DETECTOR, task='face_detector')
            DeepFace.build_model('Fasnet', task='spoofing')
            self.deepface = DeepFace
            self.ready = True
        except Exception as error:
            # Never log exception content: model paths, request data and credentials stay private.
            print('Face models could not warm: ' + type(error).__name__, flush=True)
            self.failed = True
        finally:
            self.warming = False

    def image(self, encoded):
        import cv2
        import numpy as np
        from PIL import Image, ImageOps, UnidentifiedImageError

        if not isinstance(encoded, str) or len(encoded) > ((MAX_IMAGE_BYTES + 2) // 3) * 4:
            raise CaptureError('invalid_image')
        try:
            raw = base64.b64decode(encoded, validate=True)
            if not raw or len(raw) > MAX_IMAGE_BYTES:
                raise ValueError('Invalid size')
            with Image.open(io.BytesIO(raw)) as inspection:
                if inspection.format not in {'JPEG', 'PNG', 'WEBP'}:
                    raise ValueError('Invalid format')
                width, height = inspection.size
                if width < 160 or height < 160 or width * height > 16_000_000:
                    raise ValueError('Invalid dimensions')
                oriented = ImageOps.exif_transpose(inspection).convert('RGB')
                image = cv2.cvtColor(np.asarray(oriented), cv2.COLOR_RGB2BGR)
        except (ValueError, binascii.Error, UnidentifiedImageError, Image.DecompressionBombError, OSError):
            raise CaptureError('invalid_image') from None
        max_side = max(image.shape[:2])
        if max_side > 1600:
            scale = 1600 / max_side
            image = cv2.resize(image, (round(image.shape[1] * scale), round(image.shape[0] * scale)))
        return image

    def extract(self, encoded, *, document=False):
        import cv2
        import numpy as np

        image = self.image(encoded)
        try:
            faces = self.deepface.extract_faces(
                img_path=image, detector_backend=DETECTOR, enforce_detection=True,
                align=True, expand_percentage=12, color_face='bgr',
                normalize_face=False, anti_spoofing=not document,
            )
        except ValueError as error:
            code = 'spoof_detected' if 'spoof' in str(error).lower() and not document else ('document_face_not_found' if document else 'face_not_found')
            raise CaptureError(code) from None
        if not faces:
            raise CaptureError('document_face_not_found' if document else 'face_not_found')
        if document:
            # ID cards may contain a smaller ghost portrait. Reject two primary-sized faces.
            faces.sort(key=lambda item: item['facial_area']['w'] * item['facial_area']['h'], reverse=True)
            largest = faces[0]['facial_area']
            if len(faces) > 1:
                secondary = faces[1]['facial_area']
                if secondary['w'] * secondary['h'] > largest['w'] * largest['h'] * 0.65:
                    raise CaptureError('ambiguous_document')
        elif len(faces) != 1:
            raise CaptureError('multiple_faces')
        chosen = faces[0]
        if not document and chosen.get('is_real') is not True:
            raise CaptureError('spoof_detected')
        area = chosen['facial_area']
        minimum_side = 56 if document else 80
        if min(area['w'], area['h']) < minimum_side:
            raise CaptureError('image_quality')
        crop = np.asarray(chosen['face'], dtype=np.uint8)
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        if gray.mean() < 25 or gray.mean() > 235 or cv2.Laplacian(gray, cv2.CV_64F).var() < 20:
            raise CaptureError('image_quality')
        represented = self.deepface.represent(
            img_path=crop, model_name=MODEL, detector_backend='skip',
            enforce_detection=True, align=False, normalization='base',
        )
        embedding = [float(value) for value in represented[0]['embedding']]
        if len(embedding) != 128 or not all(math.isfinite(value) for value in embedding):
            raise CaptureError('service_unavailable')
        scale = min(1, 512 / max(crop.shape[:2]))
        if scale < 1:
            crop = cv2.resize(crop, (round(crop.shape[1] * scale), round(crop.shape[0] * scale)))
        success, avatar = cv2.imencode('.jpg', crop, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not success:
            raise CaptureError('service_unavailable')
        return embedding, base64.b64encode(avatar.tobytes()).decode('ascii')

    def match(self, first, second):
        return bool(self.deepface.verify(
            img1_path=first, img2_path=second, model_name=MODEL,
            distance_metric='cosine', silent=True,
        )['verified'])

    def enroll(self, body):
        document, _ = self.extract(body.get('document'), document=True)
        selfie, crop = self.extract(body.get('selfie'))
        if not self.match(document, selfie):
            return {'verified': False}
        return {'verified': True, 'embedding': selfie, 'document_embedding': document,
                'crop': crop, 'model': MODEL, 'anti_spoofing': True}

    def verify(self, body):
        references = body.get('references')
        if not isinstance(references, list) or not 1 <= len(references) <= 3:
            raise CaptureError('invalid_image')
        for reference in references:
            if not isinstance(reference, list) or len(reference) != 128:
                raise CaptureError('invalid_image')
            if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) for value in reference):
                raise CaptureError('invalid_image')
        selfie, crop = self.extract(body.get('selfie'))
        matches = sum(self.match(reference, selfie) for reference in references)
        if matches < len(references) // 2 + 1:
            return {'verified': False}
        return {'verified': True, 'embedding': selfie, 'crop': crop, 'model': MODEL, 'anti_spoofing': True}


def create_app(engine=None, *, warmup=True):
    app = Flask(__name__)
    app.config['MAX_CONTENT_LENGTH'] = 15 * 1024 * 1024
    runtime = engine or FaceEngine()
    app.extensions['face_engine'] = runtime
    if engine is None and warmup:
        threading.Thread(target=runtime.warm, name='face-model-warmup', daemon=True).start()

    def inference(method):
        @wraps(method)
        def guarded():
            expected = os.environ.get('FACE_SERVICE_TOKEN', '')
            actual = request.headers.get('X-IR-Face-Token', '')
            if len(expected) < 32 or not hmac.compare_digest(actual, expected):
                return jsonify(code='unauthorized'), 401
            if not runtime.ready:
                return jsonify(code='service_unavailable'), 503
            if not runtime.lock.acquire(blocking=False):
                return jsonify(code='service_busy'), 503
            try:
                body = request.get_json(silent=True)
                if not isinstance(body, dict):
                    raise CaptureError('invalid_image')
                return jsonify(method(body))
            except CaptureError as error:
                return jsonify(code=error.code), 503 if error.code == 'service_unavailable' else 422
            except Exception as error:
                print('Face inference failed: ' + type(error).__name__, flush=True)
                return jsonify(code='service_unavailable'), 503
            finally:
                runtime.lock.release()
        return guarded

    @app.get('/health')
    def health():
        configured = len(os.environ.get('FACE_SERVICE_TOKEN', '')) >= 32
        ready = runtime.ready and configured
        return jsonify(ready=ready, model=MODEL, detector=DETECTOR, engine='onnx', anti_spoofing=True,
                       state='ready' if ready else ('models_unavailable' if runtime.failed else 'warming')), 200 if ready else 503

    @app.post('/v1/enroll')
    @inference
    def enroll(body):
        return runtime.enroll(body)

    @app.post('/v1/verify')
    @inference
    def verify(body):
        return runtime.verify(body)

    @app.errorhandler(413)
    def too_large(error):
        return jsonify(code='invalid_image'), 413

    return app


app = create_app(warmup=os.environ.get('FACE_SERVICE_WARMUP', 'true') != 'false')
