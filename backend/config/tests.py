from django.test import SimpleTestCase


class DefaultDatabaseConfigTest(SimpleTestCase):
    def test_default_database_uses_docker_postgresql(self):
        from django.conf import settings

        self.assertEqual(
            settings.DATABASES['default']['ENGINE'],
            'django.db.backends.postgresql',
        )
        self.assertEqual(settings.DATABASES['default']['PORT'], '5433')
