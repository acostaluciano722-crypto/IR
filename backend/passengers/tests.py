from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient


class DemoLoginTests(TestCase):
    def test_demo_login_creates_demo_user_when_missing(self):
        User = get_user_model()
        User.objects.filter(username='demo').delete()

        client = APIClient()
        response = client.post(
            '/api/auth/login/',
            {'username': 'demo', 'password': 'demo1234'},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(User.objects.filter(username='demo').exists())
        user = User.objects.get(username='demo')
        self.assertTrue(user.check_password('demo1234'))
        self.assertEqual(response.data['user']['username'], 'demo')
