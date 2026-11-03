"""Readiness and real no-face rejection probe; never uses a person's image."""

import base64
import importlib.util
import io
import json
import os
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from PIL import Image

base = 'http://127.0.0.1:5005'
with urlopen(base + '/health', timeout=5) as response:
    health = json.load(response)
assert health['ready'] is True and health['engine'] == 'onnx' and health['anti_spoofing'] is True

try:
    urlopen(Request(base + '/v1/verify', data=b'{}', headers={'Content-Type': 'application/json'}), timeout=5)
except HTTPError as error:
    assert error.code == 401
else:
    raise AssertionError('Unauthenticated inference was accepted')

buffer = io.BytesIO()
Image.new('RGB', (320, 320), (110, 110, 110)).save(buffer, format='PNG')
blank = base64.b64encode(buffer.getvalue()).decode('ascii')
request = Request(base + '/v1/enroll', method='POST',
                  data=json.dumps({'document': blank, 'selfie': blank}).encode(),
                  headers={'Content-Type': 'application/json', 'X-IR-Face-Token': os.environ['FACE_SERVICE_TOKEN']})
try:
    urlopen(request, timeout=45)
except HTTPError as error:
    assert error.code == 422
    rejected = json.load(error)
    assert rejected['code'] == 'document_face_not_found'
else:
    raise AssertionError('A blank image was accepted as an ID portrait')

assert importlib.util.find_spec('tensorflow') is None
assert importlib.util.find_spec('torch') is None

# Exercise the actual ONNX forward/metric path using synthetic pixels, not a person's image.
import numpy as np
from deepface import DeepFace
pixels = np.random.default_rng(11).integers(0, 256, size=(112, 112, 3), dtype=np.uint8)
vector = DeepFace.represent(img_path=pixels, model_name='SFace', detector_backend='skip',
                            enforce_detection=True, align=False)[0]['embedding']
assert len(vector) == 128
assert DeepFace.verify(img1_path=vector, img2_path=vector, model_name='SFace', silent=True)['verified'] is True
opposite = [-float(value) for value in vector]
assert DeepFace.verify(img1_path=vector, img2_path=opposite, model_name='SFace', silent=True)['verified'] is False
print(json.dumps({'ready': health, 'unauthorized_rejected': True, 'real_no_face_rejected': True,
                  'synthetic_onnx_vector_path': '128 dimensions and distance metric checked',
                  'tensorflow_or_torch_installed': False, 'human_face_comparison': 'requires user camera capture'}))
