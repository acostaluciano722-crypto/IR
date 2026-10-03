from django.test import SimpleTestCase


class DefaultDatabaseConfigTest(SimpleTestCase):
    def test_default_database_uses_sqlite_for_local_dev(self):
        from django.conf import settings

        self.assertEqual(
            settings.DATABASES['default']['ENGINE'],
            'django.db.backends.sqlite3',
        )
