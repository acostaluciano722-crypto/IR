import uuid

from django.contrib import admin
from django.core.cache import cache
from django.db import DatabaseError, connection
from django.http import JsonResponse
from django.urls import include, path
from django.conf import settings
from django.conf.urls.static import static
from django.views.decorators.http import require_GET
from redis.exceptions import RedisError
from coredata.auth_views import CompleteProfileView, CurrentUserView, LegacyPasswordMigrationView, LinkLegacyAccountView
from coredata.face_views import FaceChallengeView, FaceEnrollView, FaceStatusView, FaceVerifyView
from coredata.compensation_views import BinaryNetworkMeView, CompensationMeView, CompensationPlanView, CompensationSourceView


REQUIRED_API_TABLES = {
    'ir_binary_position',
    'ir_compensation_control',
    'ir_compensation_member',
    'ir_compensation_pv',
    'ir_compensation_branch',
    'ir_compensation_funding',
    'ir_compensation_period',
    'ir_compensation_payout',
    'ir_compensation_award',
    'ir_compensation_incentive',
    'historial_puntos',
    'ir_profile_photo',
    'ir_driver_presence',
    'ofertas',
    'perfil_conductor',
    'perfil_pasajero',
    'rangos',
    'transacciones',
    'usuario',
    'vehiculo',
    'viaje',
}


@require_GET
def api_health(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT PostGIS_Version()')
            cursor.fetchone()
            existing_tables = set(connection.introspection.table_names(cursor))
    except DatabaseError:
        return JsonResponse(
            {'api': 'ok', 'database': 'unavailable', 'postgis': 'unavailable'},
            status=503,
        )
    missing_tables = sorted(REQUIRED_API_TABLES - existing_tables)
    if missing_tables:
        return JsonResponse({
            'api': 'ok',
            'database': 'ok',
            'postgis': 'ok',
            'schema': 'incomplete',
            'missing_tables': missing_tables,
        }, status=503)
    health = {'api': 'ok', 'database': 'ok', 'postgis': 'ok'}
    key = f'api-health:{uuid.uuid4().hex}'
    try:
        cache.set(key, 'ok', timeout=15)
        if cache.get(key) != 'ok':
            raise RuntimeError('Cache check failed')
        cache.delete(key)
    except (RedisError, OSError, RuntimeError):
        return JsonResponse({**health, 'cache': 'unavailable'}, status=503)
    return JsonResponse({**health, 'cache': 'ok'})


def api_status(request):
    return JsonResponse({
        'name': 'IR API',
        'status': 'ok',
        'endpoints': {
            'health': '/api/health/',
            'login': '/api/auth/login/',
            'places': '/api/places/search/?input=Cartagena',
            'rides': '/api/rides/',
        },
    })

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', api_health, name='api-health'),
    path('api/network/', BinaryNetworkMeView.as_view(), name='network-me'),
    path('api/driver/compensation/', CompensationMeView.as_view(), name='compensation-me'),
    path('api/driver/compensation/plan/', CompensationPlanView.as_view(), name='compensation-plan'),
    path('api/driver/compensation/source/', CompensationSourceView.as_view(), name='compensation-source'),
    path('api/auth/me/', CurrentUserView.as_view(), name='auth-me'),
    path('api/auth/profile/', CompleteProfileView.as_view(), name='auth-profile'),
    path('api/auth/legacy-migrate/', LegacyPasswordMigrationView.as_view(), name='auth-legacy-migrate'),
    path('api/auth/link-legacy/', LinkLegacyAccountView.as_view(), name='auth-link-legacy'),
    path('api/profile/face/', FaceStatusView.as_view(), name='face-status'),
    path('api/profile/face/challenge/', FaceChallengeView.as_view(), name='face-challenge'),
    path('api/profile/face/enroll/', FaceEnrollView.as_view(), name='face-enroll'),
    path('api/profile/face/verify/', FaceVerifyView.as_view(), name='face-verify'),
    path('api/', include('passengers.urls')),
    path('api/driver/', include('drivers.urls')),
    path('', api_status, name='api-status'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
