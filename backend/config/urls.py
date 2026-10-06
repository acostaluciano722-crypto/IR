from django.contrib import admin
from django.db import DatabaseError, connection
from django.http import JsonResponse
from django.urls import include, path
from django.views.decorators.http import require_GET


REQUIRED_API_TABLES = {
    'historial_puntos',
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
    return JsonResponse({'api': 'ok', 'database': 'ok', 'postgis': 'ok'})


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
    path('api/', include('passengers.urls')),
    path('api/driver/', include('drivers.urls')),
    path('', api_status, name='api-status'),
]
