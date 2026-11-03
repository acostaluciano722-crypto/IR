# IR con Supabase

Proyecto conectado: **IR: APP DE MOVILIDAD**, referencia `nligmbbebusjewxrghps` y URL `https://nligmbbebusjewxrghps.supabase.co`.

La importación al proyecto alojado ya está aplicada y verificada con SHA-256 en todas las tablas. Se conservaron los 5 usuarios de negocio, 2 perfiles de pasajero, 3 de conductor, 3 vehículos, 7 viajes, 7 ofertas, 7 transacciones, 12 movimientos de puntos y sus identificadores. Django y Celery ya usan Supabase mediante el pooler de sesiones en `us-east-1`. La base Docker original y las copias en `backups/` se conservan.

En **Table Editor**, selecciona el esquema **`ir`** para ver los datos de negocio. Los usuarios de Supabase Auth se crean al primer acceso verificado de cada cuenta anterior; las contraseñas Django no se copian como hashes incompatibles. Que Auth todavía no muestre esas cinco identidades es parte de esta transición.

## Arquitectura

- **Supabase Database:** PostgreSQL/PostGIS compartido, con las tablas de negocio en el esquema privado `ir`.
- **Supabase Auth:** correo y contraseña, confirmación de correo, recuperación, sesiones persistentes, renovación y Google OAuth con PKCE.
- **Supabase Storage:** bucket privado `ir-profile-photos`; Django autoriza las operaciones y entrega URLs firmadas con una hora de validez.
- **Django/DRF:** conserva viajes, ofertas, permisos, cartera y reglas de negocio. Valida los tokens de Supabase, su firma, emisor, audiencia y vencimiento.
- **Redis/Celery:** continúan en Docker. Supabase no sustituye estos procesos ni aloja los contenedores Django/Flutter del repositorio.

La app se conecta a Django para operaciones del negocio y al SDK de Supabase para autenticarse. Las claves secretas y la conexión PostgreSQL solo están en el backend. Flutter usa exclusivamente la clave **publicable**, incluida en `frontend/lib/config/supabase_public.dart`; se puede distribuir con la app. `user_metadata` se usa para rellenar formularios, nunca para conceder permisos o establecer saldos. El rol de negocio se guarda en la base y solo puede elegirse entre pasajero y conductor al crear el perfil.

La conexión del backend utiliza el rol `ir_backend`: propietario de las tablas de `ir`, sin permisos de superusuario, creación de roles/bases ni acceso directo a `auth` o `storage`. Auth y Storage se administran mediante sus APIs oficiales desde el servidor. RLS está habilitado y los clientes `anon`/`authenticated` no tienen acceso al esquema de negocio.

## VS Code y trabajo en equipo

El procedimiento para el compañero que ya pertenece al proyecto está en [Trabajar juntos en IR](colaboracion.md). Incluye la descarga del código, la comprobación remota con `npm run supabase:check` y el arranque independiente de cada equipo.

La extensión `supabase.vscode-supabase-extension` ya estaba instalada en este equipo. El repositorio incluye:

- `.vscode/mcp.json`: servidor oficial de Supabase limitado a este proyecto. Abre el archivo, inicia `supabase-ir` y completa OAuth con tu propia cuenta.
- `.vscode/tasks.json`: tareas para iniciar Supabase local, vincular el proyecto y arrancar Docker.
- `.vscode/launch.json`: depuración de Flutter Web con Supabase y del backend local.
- `supabase/config.toml` y migraciones SQL versionadas.
- `infra/shared/supabase/config.toml`: configuración mínima de Auth compartido. `npm run supabase:cloud:diff` permite revisar cambios y `npm run supabase:cloud:push` aplica solo las propiedades declaradas; conserva la configuración del proveedor Google y las demás propiedades del proyecto.
- `package.json`/`package-lock.json`: CLI fijada a `2.122.0`. Ejecuta `npm ci` al clonar.

Para conectar **Codex**, registra el servidor en su configuración propia:

```powershell
codex mcp add supabase --url 'https://mcp.supabase.com/mcp?project_ref=nligmbbebusjewxrghps&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching'
codex mcp login supabase
codex mcp list
```

`add` puede iniciar OAuth automáticamente. Completa la autorización en el navegador; si ya terminó, no hace falta iniciar otro acceso. La autenticación de Codex es independiente de la CLI de Supabase y del MCP de VS Code. Tras reiniciar la sesión de Codex, `/mcp` muestra sus servidores activos. Las skills oficiales `supabase` y `supabase-postgres-best-practices` de `supabase/agent-skills` ya están instaladas en este equipo.

Cada compañero debe tener acceso propio a la organización/proyecto de Supabase y al repositorio Git. Las invitaciones se administran en el panel de la organización. Compartan cambios mediante ramas y PR; no compartan cuentas personales ni suban `.env`, claves secretas, archivos locales de configuración o copias de los datos. Los archivos públicos de ejemplo sí están versionados. El compañero debe configurar su `.env` a partir del ejemplo, recibiendo las credenciales del backend por un canal privado, y usar sus propias sesiones CLI/MCP. Con el entorno configurado, `run_docker.ps1` arranca Django, Redis y Celery sin exigir una base Docker local.

Las migraciones SQL inicializan el esquema externo existente. Después, las migraciones de Django administran los modelos propios de la API. Los cambios sobre tablas externas deben incluir una nueva migración Supabase; los modelos Django con `managed=False` no generan por sí solos los cambios SQL. No ejecutes `db reset` contra un entorno compartido.

## Reproducir la migración en un destino nuevo

**No vuelvas a importar sobre el proyecto actual:** la importación ya terminó. Los pasos siguientes documentan el procedimiento para otro destino vacío o una recuperación revisada.

Antes de la importación, inspecciona el destino para comprobar su versión PostgreSQL, extensiones y objetos existentes. El esquema de destino debe estar vacío: el importador se niega a sobrescribir o mezclar datos.

1. Autoriza la conexión Supabase. Para la CLI, utiliza preferentemente un token con alcance limitado al proyecto, guardado en `SUPABASE_ACCESS_TOKEN` en tu terminal. El inicio de sesión interactivo de la CLI crea un token de alcance general. No pegues tokens en el chat ni en Git.
2. Vincula y revisa las migraciones antes de aplicarlas:

```powershell
npm ci
npm run supabase:link
npm run supabase -- db push --linked --dry-run --skip-vault
npm run supabase -- db push --linked --skip-vault
```

3. Configura un rol de backend con contraseña propia, sin privilegios globales, propietario del esquema `ir` y sus tablas; concédele uso de `extensions`. No uses la contraseña administradora de PostgreSQL como credencial habitual de la app. Copia `.env.supabase.example` a `.env` y completa la conexión del **Session pooler**, puerto `5432`, desde **Connect** en el panel. Usa `sslmode=require`, una contraseña codificada para URL y `DB_SCHEMA=ir`. Conserva la clave privada Django existente. Completa la URL, clave publicable y clave secreta de Supabase; las claves secretas nunca van en Flutter. El pooler en modo transacción (`6543`) no es el elegido para este esquema con `search_path` por sesión.
4. Con el entorno virtual actualizado (`pip install -r backend/requirements.txt`), crea las tablas administradas por Django:

```powershell
backend\.venv\Scripts\python.exe backend/manage.py migrate
backend\.venv\Scripts\python.exe backend/manage.py migrate_to_supabase
```

El segundo comando es un ensayo de conteos, no una importación. Para el corte definitivo, detén los escritores del backend anterior, importa y verifica:

```powershell
docker compose stop backend worker
backend\.venv\Scripts\python.exe backend/manage.py migrate_to_supabase --apply
backend\.venv\Scripts\python.exe backend/manage.py migrate_profile_media --apply
.\run_docker.ps1
```

El importador lee una instantánea consistente del contenedor `ir_postgres_postgis`, crea una copia de seguridad en `backups/`, conserva UUID, coordenadas, identificadores de API y secuencias, y compara SHA-256 de cada tabla antes de confirmar. Ante una diferencia revierte la importación completa. No elimina ni modifica la base de origen. El reinicio carga `DATABASE_URL` y conecta tanto Django como Celery a Supabase.

El ensayo detectó **dos fotos registradas cuyos archivos ya faltan en `backend/media`**. Las rutas se conservan; deben recuperarse de su ubicación original o volver a subirse. El comando de medios informa archivos ausentes y no inventa imágenes de reemplazo.

Si falla el corte, conserva la copia y vuelve temporalmente a la configuración Docker anterior antes de arrancar. Las tablas internas de Supabase (`auth`, `storage`, `realtime`) no se sobrescriben con el dump anterior.

## Flutter

El proyecto compartido es la configuración predeterminada de Flutter. Desde VS Code selecciona **IR Web · Supabase compartido** o ejecuta:

```powershell
cd frontend
flutter run -d chrome --web-port 5353
```

Para Android Emulator, el backend local se alcanza con `http://10.0.2.2:8000/api`. En un teléfono físico usa la IPv4 del PC y permite el puerto del backend en la red privada. En Supabase alojado, la URL de Auth es la misma en todos los dispositivos. Las sesiones se restauran y renuevan con el SDK; cada petición a Django obtiene el token actual.

Para cambiar de proyecto, puedes sobrescribir las constantes con `--dart-define-from-file=config/supabase.json`, usando `frontend/config/supabase.example.json` como ejemplo. Ajusta `API_BASE_URL` para el equipo/dispositivo que ejecutará el cliente. La configuración local usa `config/supabase.local.json` y el backend de depuración del puerto `8001`; las credenciales locales se obtienen con la CLI y no se versionan.

El acceso Supabase utiliza **correo verificado o Google**. El celular se conserva como dato del perfil; verificarlo para acceso por SMS requiere configurar un proveedor aparte. Para volver al modo anterior de desarrollo, usa un backend sin Supabase y `--dart-define=SUPABASE_AUTH_ENABLED=false` en Flutter.

El registro por correo pide nombre, correo y contraseña. Después de verificar el correo se completan celular y, para conductores, documento y vehículo. Estos datos se guardan en el esquema privado de negocio; no se añaden a los metadatos de Auth que acompañan a los tokens.

## Google

El botón y el retorno OAuth están implementados; los retornos web/Android ya se guardaron en el proyecto. Habilitar el proveedor alojado requiere las credenciales OAuth del propietario de Google Cloud, distintas de las claves de Maps:

1. Crea/configura un cliente OAuth **Web application** en Google Cloud y la pantalla de consentimiento.
2. Registra exactamente este callback autorizado:
   `https://nligmbbebusjewxrghps.supabase.co/auth/v1/callback`.
3. En Supabase, **Authentication → Sign In / Providers → Google**, habilita el proveedor y guarda el client ID y client secret. El secret permanece en Supabase, no en Flutter ni en Git.
4. Configura Site URL y los retornos permitidos de la app. Para desarrollo web: `http://localhost:5353` y `http://127.0.0.1:5353`. Para Android: `ir://auth/callback`, cuyo intent filter ya está en el manifiesto.
5. Añade la URL pública real antes de distribuir una versión. El retorno nativo en Windows requiere registrar el protocolo `ir` en el instalador; web y Android tienen la configuración correspondiente en este repositorio. Este checkout no contiene un proyecto iOS.

El proveedor no se habilita con credenciales ficticias. Se debe comprobar con una cuenta Google real después de configurarlo; los tests locales no sustituyen ese paso.

La app comprueba si Google está habilitado antes de abrir OAuth y, si falta configurarlo, permite continuar por correo con un mensaje claro.

## Cuentas existentes

Las contraseñas PBKDF2 de Django no se copian a Auth como si fueran hashes compatibles. Al primer acceso por correo, Django valida la contraseña anterior, crea el usuario Auth, vincula su identidad al UUID de negocio original y deshabilita la contraseña local. Flutter solicita el correo de confirmación mediante el SDK y su verificador PKCE. La confirmación permite continuar con los mismos viajes, puntos y saldos.

Si el usuario entra primero con Google y ese correo ya tiene cuenta IR, la app pide su contraseña anterior para vincular ambas identidades. Coincidir por correo no permite apropiarse de una cuenta ni cambiar su rol. Si la contraseña anterior no puede verificarse, el caso necesita recuperación/soporte para conservar los datos.

Con Supabase activo, las rutas antiguas de login/registro no emiten tokens Django y los tokens anteriores se rechazan por defecto. Cambiar únicamente el cliente sin configurar también el backend no completa la migración.

## Entrega de correo

El proyecto conserva el correo de pruebas de Supabase. Ese servicio solo entrega mensajes a las direcciones del equipo de la organización; para confirmaciones y recuperación de usuarios externos hay que configurar un SMTP propio en **Authentication → Email → SMTP**. El remitente y las credenciales se guardan en Supabase. La configuración mínima compartida deja esos ajustes intactos. Consulta la [guía oficial de SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

Dos de las cuentas originales tienen direcciones de demostración `@example.…`; esos buzones no reciben correos reales. Necesitan una dirección real para completar la verificación. No se desactivó la confirmación de correo para eludir esa limitación.

## Pruebas

```powershell
.\backend\run_tests.ps1
# Cuando la imagen Docker esté reconstruida:
.\backend\run_tests.ps1 -Docker
cd frontend
flutter analyze
flutter test
```

Las pruebas Django usan `config.test_settings` y una base temporal local; no usan la conexión de producción. Cubren JWT manipulados, audiencia/emisor/vencimiento, cuentas sin verificar, metadatos, vínculos de cuentas y bloqueo del auth anterior.

En el entorno local preparado también se ejecutó `tools/smoke_supabase.py`: usa Auth y Storage reales, prueba migración de contraseña, confirmación obligatoria, JWT, conservación de puntos, foto privada, descarga firmada, borrado, renovación y cierre de sesión. Rechaza endpoints alojados y limpia las cuentas de prueba. `.env.supabase.local` y los archivos de configuración local están excluidos de Git.

`tools/verify_supabase_cloud.py` comprueba el proyecto alojado y la API Docker del puerto `8000` con una identidad temporal: exige confirmación, crea el perfil, rechaza JWT manipulados, sube/descarga/elimina una foto privada y renueva/cierra la sesión. No envía correos y elimina la cuenta temporal al terminar; no sustituye probar la entrega de correo o el consentimiento Google con cuentas reales.

Verificación final: 27 pruebas Django y 35 Flutter aprobadas, análisis Flutter sin incidencias, compilación web correcta y revisión de seguridad de Supabase sin incidencias. También se comprobaron consultas de movilidad contra el proyecto alojado.

Referencias oficiales: [Google Auth](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [JWT](https://supabase.com/docs/guides/auth/jwts), [PostGIS](https://supabase.com/docs/guides/database/extensions/postgis), [conexión PostgreSQL](https://supabase.com/docs/guides/database/connecting-to-postgres) y [MCP](https://supabase.com/docs/guides/ai-tools/mcp).
