from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path

def api_status(request):
    return JsonResponse({
        'name': 'IR API',
        'status': 'ok',
        'endpoints': {
            'login': '/api/auth/login/',
            'places': '/api/places/search/?input=Cartagena',
            'rides': '/api/rides/',
        },
    })

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('passengers.urls')),
    path('api/driver/', include('drivers.urls')),
    path('', api_status, name='api-status'),
]
