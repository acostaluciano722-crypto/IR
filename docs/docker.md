# Django, Redis y Celery en Docker

## Arranque en Windows

Desde la raíz del repositorio, con Docker Desktop y `ir_postgres_postgis` activos:

```powershell
.\run_docker.ps1
```

El script obtiene la conexión del PostgreSQL existente mediante `backend/docker_database.ps1`, sin imprimir ni guardar la contraseña. Agrega el contenedor a la red externa `ir_network` y conserva sus redes y volúmenes originales. Los valores de conexión del proceso se restauran al terminar. No necesitas crear un `.env` para este flujo.

El backend espera PostgreSQL, aplica las migraciones, verifica el esquema externo, recopila archivos estáticos y sirve Django/DRF con Gunicorn. Redis debe estar saludable antes de iniciar Django; Celery espera la comprobación HTTP del backend. El contenedor ejecuta la aplicación con un usuario sin privilegios.

## Servicios y conexiones

| Servicio | Dirección dentro de Docker | Acceso desde el PC |
| --- | --- | --- |
| PostgreSQL/PostGIS existente | `ir_postgres_postgis:5432` | `localhost:5433`, como antes |
| Django/DRF | `backend:8000` | `http://127.0.0.1:8000/api` |
| Redis | `redis:6379` | Sin puerto publicado |
| Celery worker | Consume tareas de Redis | Sin puerto publicado |

Redis utiliza la base lógica `0` como broker, `1` como caché y `2` para resultados temporales. Las tres comparten el mismo proceso Redis; no son instancias aisladas. AOF y el volumen `ir_redis_data` conservan la cola entre recreaciones normales. La política `noeviction` evita expulsar mensajes para liberar memoria. Las tareas futuras que modifiquen saldos necesitan además idempotencia y una estrategia de recuperación; la persistencia de Redis por sí sola no garantiza una liquidación financiera.

Las fotos usan un montaje de `backend/media` y sobreviven a la recreación del backend. En Linux, esta carpeta debe ser escribible por el UID/GID `10001`. Los archivos estáticos de Django y DRF se recopilan dentro de la imagen en ejecución y se sirven con WhiteNoise. Las fotos conservan el comportamiento de desarrollo de Django (`DJANGO_DEBUG=true`).

## Flutter

No cambia el contrato de la API ni las URLs predeterminadas del frontend:

```powershell
cd frontend
flutter run -d chrome --web-port 5353
# Android Emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
# Teléfono físico: reemplaza la IP por la del PC en la misma red Wi-Fi
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

El lanzador agrega las IPv4 locales a `ALLOWED_HOSTS`; si cambias de red, vuelve a ejecutarlo. Para fijar una lista propia, define `$env:ALLOWED_HOSTS` antes de arrancar. CORS continúa habilitado para desarrollo y el puerto `8000` se publica en todas las interfaces para permitir Android y teléfonos físicos. Puedes restringirlo con `BACKEND_BIND_ADDRESS=127.0.0.1` si solo usas web o escritorio.

La clave de Google Maps del backend se pasa desde `GOOGLE_MAPS_API_KEY` en el entorno o `.env`. La clave del navegador conserva su configuración independiente en Flutter. El lanzador no recupera claves que solo existían en otra terminal.

## Comprobaciones

```powershell
.\run_docker.ps1 -CheckOnly
Invoke-RestMethod http://127.0.0.1:8000/api/health/
docker compose exec backend python manage.py check_workers
docker compose ps
docker compose logs --tail 100 backend worker redis
```

La salud HTTP comprueba PostGIS, las tablas requeridas y una escritura/lectura de caché. `check_workers` envía `coredata.infrastructure_probe` por el broker, espera su ejecución en un proceso Celery y lee el resultado desde Redis. La tarea comprueba PostgreSQL y la caché, sin modificar usuarios, viajes o saldos. Esto verifica el recorrido completo; la salud HTTP por sí sola no garantiza que un worker esté activo.

Pruebas de regresión sobre una base temporal que copia únicamente el esquema PostgreSQL existente:

```powershell
.\backend\run_tests.ps1 -Docker
```

Con `-Docker`, las pruebas usan el backend y las dependencias de la imagen que está en ejecución. Sin el parámetro se utiliza el entorno virtual local, que debe tener instalado `backend/requirements.txt`. Las pruebas nuevas cubren salud de caché, Redis desconectado, esquema incompleto, ejecución de la tarea y errores cuando no responde un worker.

## Operación

```powershell
# Reconstruir y actualizar backend y worker tras modificar código/dependencias
.\run_docker.ps1
# Arrancar sin reconstruir
.\run_docker.ps1 -SkipBuild
# Detener el ecosistema, conservando los datos
docker compose down
# Reiniciar un servicio existente
docker compose restart worker
```

El código se copia a la imagen, de modo que debes reconstruir para aplicar cambios. Los servicios se reinician automáticamente con Docker salvo que los detengas explícitamente. El PostgreSQL existente mantiene su propia política de arranque. No uses `down -v` si quieres conservar el volumen Redis.

Para aumentar la capacidad del worker, define `$env:CELERY_WORKER_CONCURRENCY = '4'` y vuelve a ejecutar el lanzador. También puedes crear varias réplicas con `docker compose up -d --no-recreate --no-deps --scale worker=2 worker` mientras mantienes la configuración de conexión en el entorno o `.env`. Cada réplica tiene su propio nombre de nodo. Ajusta la concurrencia según la CPU y las conexiones disponibles en PostgreSQL.

## Configuración manual y otros sistemas

El ejemplo `.env.example` contiene valores de desarrollo. Copia a `.env`, completa `DB_PASSWORD` con la contraseña real y ajusta `DB_NAME`, `DB_USER` y las demás variables. `.env` está excluido de Git y del contexto de construcción. No uses el puerto publicado `5433` para la conexión entre contenedores; usa `5432`.

```powershell
Copy-Item .env.example .env
docker network create ir_network
docker network connect ir_network ir_postgres_postgis
docker compose up -d --build --wait
docker compose exec backend python manage.py check_workers
```

Los comandos de creación/conexión de red se ejecutan solo si todavía no existen. En Windows, el lanzador hace estas comprobaciones automáticamente. Los comandos de consulta (`ps`, `logs`, `down`, `exec`) funcionan después del lanzador sin guardar credenciales; para recrear contenedores con `up`, usa el lanzador o proporciona el `.env` completo.

## Alcance de ProMaster

La base contiene campos de red, rangos y bonificaciones, pero el código actual no incluye un algoritmo que calcule y liquide bonificaciones binomiales. Esta entrega prepara y verifica la infraestructura para ejecutarlo fuera del servidor HTTP. Los puntos individuales, la reserva/débito de Bolsa IR, el registro y los endpoints conservan su lógica actual.

Cuando se implemente el motor, las tareas deberán estar en una aplicación instalada, por ejemplo `coredata/tasks.py`, y enviarse después del commit de la operación que las origina mediante `delay_on_commit`. Para movimientos de dinero se necesitarán registros únicos por liquidación, bloqueos/transacciones y recuperación de envíos fallidos. No se agregaron porcentajes ni reglas de bonificación sin especificación.

## Configuración de despliegue

La configuración incluida conserva el entorno local: depuración, HTTP y recargas simuladas. Para un despliegue público configura una clave estable y privada, `DJANGO_DEBUG=false`, hosts/orígenes explícitos, HTTPS y almacenamiento/servidor para medios. Mantén la misma `DJANGO_SECRET_KEY` que usabas si quieres conservar la validez de los tokens existentes. Redis permanece accesible solo desde su red Docker.

Referencias: [redes de Compose](https://docs.docker.com/compose/how-tos/networking/), [orden de arranque](https://docs.docker.com/compose/how-tos/startup-order/), [Celery con Django](https://docs.celeryq.dev/en/stable/django/first-steps-with-django.html), [caché Redis de Django](https://docs.djangoproject.com/en/5.2/topics/cache/#redis) y [WhiteNoise](https://whitenoise.readthedocs.io/en/stable/django.html).
