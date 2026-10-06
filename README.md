# IR

Primer vertical slice de la plataforma de movilidad IR: login breve y flujo inicial de pasajero.

## Backend

```powershell
cd backend
py -m venv .venv
.venv\Scripts\activate
.venv\Scripts\python.exe -m pip install -r requirements.txt
.\run_dev.ps1
```

El lanzador comprueba el contenedor `ir_postgres_postgis`, toma su configuración sin imprimir ni guardar la contraseña, aplica las migraciones y sirve Django en `0.0.0.0:8000` para aceptar conexiones de Flutter. La base Docker debe publicar el puerto `5433`.

Comprueba que la API y PostGIS respondan:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health/
```

Debe devolver `api: ok`, `database: ok` y `postgis: ok`. El login usa `username` y `password`, y devuelve un token firmado con vencimiento de siete días.

## Frontend

Requiere instalar Flutter y tenerlo en el `PATH`.

```powershell
cd frontend
flutter pub get
flutter run
```

En Android Emulator, `ApiService` usa `http://10.0.2.2:8000/api`; en Flutter Web y escritorio usa `http://127.0.0.1:8000/api`. Para un teléfono físico conectado a la misma red Wi-Fi que el PC, pasa la IPv4 del PC al ejecutar Flutter:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

Reemplaza `192.168.1.20` por la IPv4 que muestra `ipconfig`. Si Windows Firewall pregunta, permite el puerto `8000` en redes privadas. CORS y HTTP sin cifrar se habilitan solo en desarrollo; el manifiesto de release no permite HTTP claro.

## Mapa y búsqueda en tiempo real

La app usa Google Maps y Places Autocomplete. No guardes la clave en Git. Define la clave en el entorno del backend antes de arrancar Django:

```powershell
$env:GOOGLE_MAPS_API_KEY = 'TU_CLAVE_RESTRINGIDA'
cd backend
.\run_dev.ps1
```

En `frontend/web/index.html`, reemplaza localmente `GOOGLE_MAPS_API_KEY` por una clave nueva y restringida para `http://localhost:5353/*` y `http://127.0.0.1:5353/*`, o usa una copia local del archivo fuera de Git. Habilita en Google Cloud **Maps JavaScript API**, **Places API** y facturación con límites de uso. La clave del navegador y la del backend deben ser claves restringidas separadas.

El usuario puede buscar lugares, seleccionar una sugerencia y enviar el pedido al endpoint real de viajes.

Al seleccionar una sugerencia de Places, el backend obtiene sus coordenadas y calcula distancia y duración con Google Directions. La posición del pasajero se mantiene activa con un stream de ubicación y la ruta se recalcula al desplazarse.

## Alcance actual

- Login sobre la tabla `USUARIO` con token firmado.
- Perfil mínimo del pasajero: nombre, rango y puntos.
- Solicitud de viaje con origen, destino y tipo Economy/Moto.
- Historial de solicitudes del usuario.
- Identidad visual inicial basada en Lemon Tonic, aproximada como `#E8F044`.
