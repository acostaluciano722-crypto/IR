# IR

IR es una app de movilidad en Flutter con experiencias de pasajero y conductor y una API Django. El pasajero propone una tarifa y elige entre ofertas; el conductor responde solicitudes y administra su Bolsa IR.

## Ecosistema en Docker (recomendado)

Requiere Docker Desktop iniciado y el contenedor existente `ir_postgres_postgis` activo. Desde la raíz:

```powershell
.\run_docker.ps1
```

El lanzador construye la imagen de Django y arranca **backend**, **Redis** y **Celery worker**. Conecta PostgreSQL a `ir_network` conservando su red original, sus datos y el puerto `5433` para DBeaver. Lee las credenciales existentes solo en memoria, aplica migraciones, verifica el esquema y ejecuta una tarea real a través de Redis y Celery.

La API sigue en `http://127.0.0.1:8000/api`. Flutter se ejecuta como antes: escritorio y web usan `127.0.0.1:8000`, Android Emulator usa `10.0.2.2:8000` y los teléfonos físicos usan la IPv4 del PC. El lanzador agrega las IPv4 actuales a `ALLOWED_HOSTS`. No ejecutes `run_dev.ps1` y el backend Docker simultáneamente en el mismo puerto.

```powershell
.\run_docker.ps1 -CheckOnly
Invoke-RestMethod http://127.0.0.1:8000/api/health/
docker compose ps
docker compose logs --tail 100 backend worker redis
docker compose down
```

`down` detiene los tres servicios del nuevo ecosistema. PostgreSQL sigue administrado por su instalación existente. Las fotos persisten en `backend/media` y Redis usa un volumen con AOF. Para cambios de código, vuelve a ejecutar `run_docker.ps1`; `-SkipBuild` reutiliza la imagen existente.

Consulta [la guía de Docker](docs/docker.md) para configuración manual, pruebas, escalado y alcance de las tareas de ProMaster. El worker está preparado y comprobado; el motor de bonificaciones binomiales todavía no está implementado en el código actual.

## Backend local (alternativa)

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

## Verificar PostgreSQL y consultar cuentas

Desde `backend`, ejecuta `./run_dev.ps1 -CheckOnly` para aplicar migraciones y comprobar las tablas, columnas, PostGIS y cantidades de registros. El lanzador obtiene el puerto publicado y las credenciales del contenedor existente, sin imprimir la contraseña.

En DBeaver, usa `localhost:5433`, base `ir_promaster_db` y esquema `public`. Abre `backend/verify_database.sql` y vuelve a ejecutar la consulta para ver todas las cuentas y sus perfiles. El filtro `LIKE 'dbcheck.%@example.test'` muestra únicamente cuentas de prueba; excluye los usuarios registrados con otro correo.

`backend/run_tests.ps1 -Docker` comprueba el registro, el login, los perfiles, los vehículos y la infraestructura con las dependencias del contenedor. Sin `-Docker` utiliza el entorno virtual local. Ambos modos copian únicamente el esquema a una base temporal de PostgreSQL/PostGIS y la eliminan al terminar.

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

## Alcance inicial del proyecto

- Login sobre la tabla `USUARIO` con token firmado.
- Perfil mínimo del pasajero: nombre, rango y puntos.
- Solicitud de viaje con origen, destino y tipo Economy/Moto.
- Historial de solicitudes del usuario.
- Identidad visual inicial basada en Lemon Tonic, aproximada como `#E8F044`.

## Funciones actuales

- El acceso acepta correo o celular y contraseña. Todavía no se envían códigos SMS.
- El pasajero solicita viajes, compara ofertas por monto, calificación y tipo de vehículo, sigue el viaje y califica al conductor.
- El conductor publica disponibilidad, ve solicitudes, acepta o contraoferta, navega el viaje y califica al pasajero.
- Al seleccionar un destino, el pasajero puede ver carros y motos activos dentro de ocho kilómetros. Las ubicaciones dejan de mostrarse si no se actualizan durante dos minutos.
- Pasajeros y conductores pueden elegir, cambiar y quitar su foto de perfil desde la galería.
- La cartera muestra movimientos recientes. Las recargas son simuladas en desarrollo y se bloquean en producción hasta conectar una pasarela real.

Las nuevas tablas de fotos y presencia se crean con las migraciones existentes; `run_dev.ps1` las aplica al arrancar. En producción, configura un almacenamiento de medios para las fotos antes de habilitar el flujo.
