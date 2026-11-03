# Trabajar juntos en IR

El proyecto compartido es [IR: APP DE MOVILIDAD](https://supabase.com/dashboard/project/nligmbbebusjewxrghps), referencia `nligmbbebusjewxrghps`. Cada integrante entra con su propia cuenta de Supabase, ya incorporada al equipo del proyecto.

## Qué está compartido

| Componente | Ubicación | Uso por el equipo |
| --- | --- | --- |
| Datos de movilidad | Supabase Database, esquema privado `ir` | Ambos entornos consultan la misma base. |
| Acceso de la app | Supabase Auth | Correo, sesiones y recuperación; Google requiere configurar su cliente OAuth. |
| Fotos nuevas de perfil | Supabase Storage, bucket privado `ir-profile-photos` | Django autoriza y firma el acceso a las fotos. |
| Código Flutter, Django y migraciones | [Repositorio IR](https://github.com/acostaluciano722-crypto/IR) | Cambios mediante Git y ramas. |
| Django, Redis y Celery | Docker en el equipo de cada desarrollador | Cada PC puede ejecutar la API usando la base compartida, sin depender del otro PC. |

Supabase aloja los datos y servicios anteriores. Para una API y una app públicas disponibles las 24 horas se necesita desplegar además los contenedores del backend y el frontend en un servicio de alojamiento.

## Descargar esta integración

La integración se publica en la rama `feat/supabase-compartido`:

```powershell
git clone --branch feat/supabase-compartido https://github.com/acostaluciano722-crypto/IR.git
cd IR
npm ci
```

Si ya tienes el repositorio, guarda primero tus cambios y cambia a esa rama desde el control de código de VS Code. No hace falta importar otra vez la base: los datos y migraciones ya están en Supabase.

## Comprobar tu acceso remoto

Con Node.js instalado, desde la raíz del repositorio:

```powershell
npm run supabase -- login
npm run supabase:link
npm run supabase:check
```

Usa tu propia cuenta y completa el acceso en el navegador. La comprobación solo lee información del proyecto y conteos, sin modificar datos ni mostrar información personal o claves. Muestra las migraciones aplicadas, el bucket privado y el estado de RLS. Funciona sin arrancar Docker y sin pedir la contraseña PostgreSQL del otro integrante.

En el panel de Supabase abre **Table Editor** y cambia el selector de esquema a **`ir`**. Los usuarios de negocio están en `ir.usuario`; los perfiles y viajes conservan sus datos. La sección **Authentication → Users** muestra las identidades de quienes ya completaron el acceso de la app.

Ser integrante del equipo de Supabase da acceso al proyecto de desarrollo. Para entrar en la app Flutter se crea o vincula una cuenta de pasajero/conductor desde la propia app.

## Ejecutar la app en tu equipo

1. Instala Docker Desktop y Flutter. Inicia Docker Desktop.
2. Copia `.env.supabase.example` a `.env`. Completa las credenciales del backend mediante el canal privado del equipo: conexión del rol `ir_backend`, claves publicable y secreta de Supabase, una clave privada Django y configuración necesaria de Maps. Mantén `DB_SCHEMA=ir`, SSL y el pooler de sesiones del puerto `5432`. `.env` está excluido de Git.
3. Ejecuta el backend y los procesos de tareas:

```powershell
.\run_docker.ps1
```

4. En otra terminal, inicia Flutter Web:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port 5353
```

También puedes usar la configuración **IR Web · Supabase compartido** de VS Code. La clave publicable del frontend ya está incluida en el código; las credenciales secretas se usan exclusivamente en el backend.

La API se sirve en `http://127.0.0.1:8000/api` de **tu propio PC**. Flutter Android Emulator utiliza `10.0.2.2:8000`. Para un teléfono físico, configura `API_BASE_URL` con la IP del PC que está ejecutando Django. Todos esos clientes usan el mismo proyecto Supabase alojado.

## Coordinar los cambios

Cada cambio de código va en una rama y se integra mediante revisión. Los cambios de tablas externas (`managed=False`) requieren una migración SQL en `supabase/migrations`; los modelos administrados por Django usan `backend/coredata/migrations`.

Antes de aplicar migraciones compartidas, coordina quién las ejecuta y revisa el destino con `npm run supabase:check`. `supabase db reset`, la reimportación de los datos anteriores y los scripts con cuentas temporales no forman parte del arranque cotidiano de un compañero.

El rol de desarrollo de la plataforma y RLS cumplen funciones diferentes: el primero permite trabajar en el panel; las tablas privadas siguen protegidas frente a los clientes de la app. Para completar Google y el envío de correos a usuarios externos, consulta [la guía de Supabase](supabase.md).
