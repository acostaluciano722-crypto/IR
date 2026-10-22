from io import StringIO
from unittest.mock import patch

from celery.exceptions import TimeoutError
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase
from redis.exceptions import ConnectionError

from config.urls import REQUIRED_API_TABLES
from coredata.tasks import infrastructure_probe


class ApiHealthTests(SimpleTestCase):
    def setUp(self):
        self.connection_patch = patch('config.urls.connection')
        self.cache_patch = patch('config.urls.cache')
        self.connection = self.connection_patch.start()
        self.cache = self.cache_patch.start()
        self.addCleanup(self.connection_patch.stop)
        self.addCleanup(self.cache_patch.stop)
        self.connection.introspection.table_names.return_value = REQUIRED_API_TABLES
        self.cache.get.return_value = 'ok'

    def test_health_checks_postgis_schema_and_cache(self):
        response = self.client.get('/api/health/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {
            'api': 'ok', 'database': 'ok', 'postgis': 'ok', 'cache': 'ok',
        })
        self.cache.set.assert_called_once()
        self.cache.delete.assert_called_once()

    def test_unavailable_redis_reports_service_unavailable(self):
        self.cache.set.side_effect = ConnectionError('Redis disconnected')
        response = self.client.get('/api/health/')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()['cache'], 'unavailable')

    def test_failed_cache_round_trip_is_unhealthy(self):
        self.cache.get.return_value = None
        self.assertEqual(self.client.get('/api/health/').status_code, 503)

    def test_incomplete_schema_still_reports_missing_tables(self):
        self.connection.introspection.table_names.return_value = REQUIRED_API_TABLES - {'viaje'}
        response = self.client.get('/api/health/')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()['missing_tables'], ['viaje'])
        self.cache.set.assert_not_called()


class WorkerProbeTests(SimpleTestCase):
    @patch('coredata.tasks.cache')
    @patch('coredata.tasks.connection')
    def test_probe_uses_database_and_cache_and_removes_its_key(self, connection, cache):
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = (1,)
        cache.get.return_value = 'ok'
        self.assertEqual(infrastructure_probe.run(), {
            'worker': 'ok', 'database': 'ok', 'cache': 'ok',
        })
        cursor.execute.assert_called_once_with('SELECT 1')
        cache.delete.assert_called_once_with(cache.set.call_args.args[0])

    @patch('coredata.tasks.cache')
    @patch('coredata.tasks.connection')
    def test_probe_rejects_missing_cache_value(self, connection, cache):
        connection.cursor.return_value.__enter__.return_value.fetchone.return_value = (1,)
        cache.get.return_value = None
        with self.assertRaises(RuntimeError):
            infrastructure_probe.run()
        cache.delete.assert_called_once()

    @patch('coredata.management.commands.check_workers.infrastructure_probe')
    def test_command_waits_for_a_real_task_result(self, task):
        task.apply_async.return_value.get.return_value = {'worker': 'ok'}
        output = StringIO()
        call_command('check_workers', stdout=output)
        self.assertIn('"worker": "ok"', output.getvalue())
        task.apply_async.assert_called_once_with(retry=False)
        task.apply_async.return_value.get.assert_called_once_with(timeout=15)
        task.apply_async.return_value.forget.assert_called_once()

    @patch('coredata.management.commands.check_workers.infrastructure_probe')
    def test_missing_worker_is_reported_as_command_failure(self, task):
        task.apply_async.return_value.get.side_effect = TimeoutError()
        with self.assertRaises(CommandError):
            call_command('check_workers', stdout=StringIO())
