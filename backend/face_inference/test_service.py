import os
import threading
import unittest

os.environ['FACE_SERVICE_WARMUP'] = 'false'
from service import CaptureError, FaceEngine, create_app


class FakeEngine:
    ready = True
    failed = False
    lock = threading.BoundedSemaphore(1)

    def __init__(self):
        self.calls = []

    def enroll(self, body):
        self.calls.append(body)
        if body.get('selfie') == 'spoof':
            raise CaptureError('spoof_detected')
        return {'verified': False}

    def verify(self, body):
        self.calls.append(body)
        return {'verified': False}


class ServiceBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.previous_token = os.environ.get('FACE_SERVICE_TOKEN')
        os.environ['FACE_SERVICE_TOKEN'] = 'unit-test-only-private-token-' * 2
        self.engine = FakeEngine()
        self.app = create_app(self.engine, warmup=False)
        self.client = self.app.test_client()
        self.headers = {'X-IR-Face-Token': os.environ['FACE_SERVICE_TOKEN']}

    def tearDown(self):
        if self.previous_token is None:
            os.environ.pop('FACE_SERVICE_TOKEN', None)
        else:
            os.environ['FACE_SERVICE_TOKEN'] = self.previous_token

    def test_unauthorized_requests_cannot_run_models(self):
        self.assertEqual(self.client.post('/v1/enroll', json={}).status_code, 401)
        self.assertFalse(self.engine.calls)

    def test_unavailable_and_busy_never_return_verified(self):
        self.engine.ready = False
        response = self.client.post('/v1/enroll', headers=self.headers, json={})
        self.assertEqual(response.status_code, 503)
        self.assertFalse(self.engine.calls)
        self.engine.ready = True
        self.engine.lock.acquire()
        try:
            response = self.client.post('/v1/enroll', headers=self.headers, json={})
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json['code'], 'service_busy')
        finally:
            self.engine.lock.release()

    def test_rejection_is_bounded_and_clears_concurrency_lock(self):
        rejected = self.client.post('/v1/enroll', headers=self.headers, json={'selfie': 'spoof'})
        self.assertEqual(rejected.status_code, 422)
        self.assertEqual(rejected.json, {'code': 'spoof_detected'})
        response = self.client.post('/v1/verify', headers=self.headers, json={'selfie': 'next'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {'verified': False})

    def test_image_paths_and_urls_are_not_loaded(self):
        engine = FaceEngine()
        for value in ['https://example.test/photo.jpg', '/etc/passwd', 'not base64']:
            with self.subTest(value=value), self.assertRaises(CaptureError) as error:
                engine.image(value)
            self.assertEqual(error.exception.code, 'invalid_image')


if __name__ == '__main__':
    unittest.main()
