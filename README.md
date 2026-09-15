# IR

Primer vertical slice de la plataforma de movilidad IR: login breve y flujo inicial de pasajero.

## Backend

```powershell
cd backend
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
py manage.py migrate
py manage.py createsuperuser
py manage.py runserver
```

La API queda en `http://127.0.0.1:8000/api/`. El login usa `username` y `password`; el frontend Flutter apunta por defecto a `http://10.0.2.2:8000/api` para Android Emulator.

## Frontend

Requiere instalar Flutter y tenerlo en el `PATH`.

```powershell
cd frontend
flutter pub get
flutter run
```

Para un dispositivo físico, cambia `baseUrl` en `frontend/lib/services/api_service.dart` por la IP local del equipo que ejecuta Django.

## Mapa y búsqueda en tiempo real

La app usa Google Maps y Places Autocomplete. No guardes la clave en Git. Define la clave en el entorno del backend antes de arrancar Django:

```powershell
$env:GOOGLE_MAPS_API_KEY = 'TU_CLAVE_RESTRINGIDA'
cd backend
.venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000
```

En `frontend/web/index.html`, reemplaza localmente `GOOGLE_MAPS_API_KEY` por una clave nueva y restringida para `http://localhost:5353/*` y `http://127.0.0.1:5353/*`, o usa una copia local del archivo fuera de Git. Habilita en Google Cloud **Maps JavaScript API**, **Places API** y facturación con límites de uso. La clave del navegador y la del backend deben ser claves restringidas separadas.

El usuario puede buscar lugares, seleccionar una sugerencia y enviar el pedido al endpoint real de viajes.

Al seleccionar una sugerencia de Places, el backend obtiene sus coordenadas y calcula distancia y duración con Google Directions. La posición del pasajero se mantiene activa con un stream de ubicación y la ruta se recalcula al desplazarse.

## Alcance actual

- Login con token DRF.
- Perfil mínimo del pasajero: nombre, rango y puntos.
- Solicitud de viaje con origen, destino y tipo Economy/Moto.
- Historial de solicitudes del usuario.
- Identidad visual inicial basada en Lemon Tonic, aproximada como `#E8F044`.
