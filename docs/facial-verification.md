# Comprobación facial en IR

La primera comprobación compara una selfie tomada con la cámara con el rostro de una foto del documento. Solo después de coincidir se genera la foto de perfil a partir del recorte facial de esa selfie. Las siguientes comprobaciones comparan la nueva selfie con hasta tres selfies anteriores aceptadas. La vigencia es de **dos meses calendario**, calculados por el servidor en `America/Bogota`; los días que no existen en el mes de destino se ajustan a su último día.

La app pide consentimiento antes de abrir la cámara y permite repetir una captura. Al vencer la comprobación, el servidor y Flutter exigen renovarla antes de usar las operaciones de movilidad. Se puede cerrar sesión desde ese flujo. Desde el perfil se puede eliminar el registro facial; hacerlo vuelve a exigir la comprobación inicial y elimina la foto derivada si sigue siendo la foto actual.

Cambiar la foto de perfil abre la comprobación con una nueva selfie; la API impide reemplazar una foto derivada por una imagen de galería sin verificar. Quitar únicamente la foto sigue disponible y no elimina por sí mismo las referencias faciales; esa eliminación completa se gestiona de forma explícita en la pantalla de comprobación.

## Servicios y datos

- Django conserva una plantilla cifrada, fechas, versión del consentimiento y metadatos en `ir.ir_face_enrollment`, en Supabase. La tabla tiene RLS y carece de permisos para `anon` y `authenticated`; el cliente Flutter pasa por Django.
- La plantilla contiene el vector del documento, un máximo de tres vectores de selfies verificadas y hasta doce hashes de capturas para rechazar su reutilización exacta. No se guardan las imágenes originales del documento o de la selfie.
- La foto de perfil derivada se guarda en el bucket privado `ir-profile-photos`, con acceso firmado por Django.
- `face-inference` ejecuta DeepFace 0.0.103 con SFace, OpenCV y FasNet, mediante ONNX. Comparte la red Docker interna y no publica su puerto al equipo. El token entre servicios es obligatorio; los modelos se descargan al arrancar y se conservan en `face_models`.
- El proceso facial atiende una inferencia a la vez, con límites de CPU y memoria. Si está ocupado o no está listo, informa al usuario para reintentar. Redis coordina los retos de un solo uso, con caducidad de tres minutos; las inferencias no ocupan los procesos de Celery dedicados a otras tareas.

El documento debe mostrar un retrato claro. La selfie se toma con la cámara frontal, debe contener un solo rostro y superar los controles de calidad y detección básica de suplantación. Las imágenes admitidas son JPEG, PNG o WebP, de hasta 5 MB cada una.

Esta comprobación encuentra coincidencias de rostros. **No certifica la autenticidad del documento ni la identidad civil**, y la detección de suplantación no garantiza detener todas las presentaciones fraudulentas. No se analizan edad, género, raza ni emociones.

## Configurar otro equipo

Completa las variables de `.env.supabase.example` en el `.env` local, excluido de Git:

- `FACE_TEMPLATE_KEY`: una clave Fernet **idéntica en todos los backends conectados a la misma base compartida**. Compártela por el canal privado del equipo y conserva respaldo. No la reemplaces al reinstalar: otra clave impide descifrar los registros existentes. Rotarla requiere recifrar las plantillas de forma coordinada.
- `FACE_SERVICE_TOKEN`: secreto que debe coincidir entre Django y el servicio facial del mismo despliegue; puede ser diferente en cada equipo.
- `FACE_SERVICE_URL=http://face-inference:5005` para Docker.
- `FACE_VERIFICATION_REQUIRED=true` para aplicar la política en el servidor.

Para generar una clave nueva **solo al configurar el primer despliegue**, usa `Fernet.generate_key()` de `cryptography`; para el token interno, `secrets.token_urlsafe(48)`. No incluyas claves, selfies o documentos en commits, capturas de soporte ni registros.

```powershell
docker compose up -d --build --wait --wait-timeout 240
docker compose ps
```

La migración Django `0008_face_enrollment` ya se aplicó al proyecto compartido. El arranque conserva los datos y aplica únicamente migraciones pendientes. La primera descarga de modelos necesita Internet y puede tardar más que los siguientes arranques.

## Comprobaciones

Las pruebas del backend cubren coincidencia, rechazo, cifrado, consentimiento, renovación, fechas, permisos y eliminación con el motor sustituido. Las pruebas del servicio verifican autenticación y sus límites. Las de Flutter sustituyen cámara, ubicación y mapa para revisar permisos, ciclo de vida y estados del flujo.

`backend/.venv/Scripts/python.exe tools/verify_face_cloud.py` comprueba el despliegue real con una cuenta temporal: política obligatoria, bloqueo de movilidad, rechazo de una imagen sintética sin rostro mediante DeepFace, reto no reutilizable y tabla privada. Elimina la cuenta al terminar y no inscribe personas. Esta comprobación no valida la tasa de acierto con documentos o selfies humanas.

La prueba final de aceptación requiere que el usuario autorice la cámara y compare su propio documento y selfie. En web, la cámara necesita `localhost` o HTTPS; un teléfono que abra una IP por HTTP requiere un despliegue HTTPS para este flujo. No se debe sustituir la cámara por una selfie de galería para salvar esa restricción.
