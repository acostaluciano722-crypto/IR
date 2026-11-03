# Referencia de movilidad: Uber e IR

Revisión del 21 de octubre de 2026. El alcance es la experiencia compartida de búsqueda, mapa, recogida y seguimiento. Las reglas de IR sobre tarifas, negociación, estados del viaje, cartera, PI, niveles y bonificaciones quedan fuera de los cambios.

## Evidencia y límites

- REA 6.7.0 abrió `https://m.uber.com/` en un Chrome temporal y observó su pantalla pública en `/go/home`: campos separados para recogida y destino. Evidencia `ev_3d5ba38840359fbd2c34149e38ba015d4ffc075a1a7c78367767b8dff925e9c9`.
- REA abrió la [guía oficial de la app del conductor](https://www.uber.com/us/en/drive/driver-app/) y capturó su contenido accesible. Evidencia `ev_d212c6b6b0515dd8e345b4bd98002aa1919289cbd178fbe53e230ecf080af726`.
- El informe anterior citaba `artifacts/research/uber-rider-evidence.json` y `artifacts/research/uber-public-evidence.json`; esos archivos no estaban disponibles en la continuación del 3 de noviembre. Sus identificadores anteriores se conservan como historial, no como capturas verificadas en esta revisión.
- La revisión no incluye una APK/IPA, código privado de Uber ni un viaje autenticado. Los iconos son dibujos originales de IR; su aspecto es una decisión de diseño, no una reproducción verificada de recursos de Uber.

## Comparación aplicada

| Antes en IR | Después | Motivo |
| --- | --- | --- |
| Marcadores genéricos y SVG usados como bitmaps | Cinco PNG propios: pasajero, recogida, destino, carro y moto | El formato PNG funciona con los mapas web y nativos; cada papel tiene una silueta distinta |
| Sin control para recuperar la ruta completa | Botón «Ver recorrido completo» en ambas vistas | Facilita recuperar el contexto del viaje sin solicitar una ruta nueva |
| El mapa volvía al centro tras cinco segundos | Centrados bajo control del usuario | Evita interrumpir la exploración |
| El encuadre no reservaba espacio para la hoja | Encuadre dentro del área visible sobre el panel | Mantiene los puntos de la ruta fuera del área cubierta |
| Lugares cercanos cargados pero sin acceso en la hoja | Hasta tres accesos que usan la selección de destino existente | Reduce escritura sin añadir reglas de negocio |
| Identificación del vehículo, código de encuentro y calificación ya presentes | Se conserva el flujo actual | No duplicar capacidades ni cambiar su validación |

La [guía de recogidas](https://www.uber.com/us/en/ride/how-it-works/pickups/) y la [identificación de vehículo y conductor](https://help.uber.com/en/riders/article/how-to-identify-a-driver-and-their-vehicle?nodeId=02746faf-1bc6-4d3f-8ba2-ab35f36d7191) se usaron como referencias funcionales. Reservas, pagos integrados, chat, viajes para terceros y funciones de emergencia requerirían ampliar el backend y no se incorporan en este alcance.

## Comprobación

- PNG transparentes a resolución 3× con tamaño estable en el mapa y sin dependencia de fuentes o imágenes remotas.
- Coordenadas inválidas descartadas al dibujar; rutas muy cortas admitidas sin límites de cámara degenerados.
- Proyección del recorrido comprobada sobre el área visible en teléfono y pantalla horizontal.
- Vistas de pasajero y conductor comprobadas con texto ampliado; el control de ruta recoge la hoja y conserva el aislamiento de punteros.
- La selección de lugares cercanos utiliza las llamadas ya existentes de detalles y estimación.

Las pruebas de widgets sustituyen mapa, ubicación y API. La apariencia de los dibujos se revisó sobre fondos claros y oscuros; la integración en un dispositivo físico requiere validación adicional.

## Rediseño del 3 de noviembre de 2026

REA 6.7.0 volvió a observar la página pública `https://m.uber.com/`, que redirigió a `/go/home`, con Chrome temporal, sin iniciar sesión ni conceder permisos de ubicación. Evidencia `ev_7f278d314e9b96381943ae543314e38873583abb8bab1c18153e7f8c8c5d245d`. La observación completa y la captura se guardan localmente en `artifacts/research/uber-rider-20261103.json` y `.png`, excluidos de Git. El navegador temporal se cerró al terminar.

En 1440×900, la captura muestra navegación superior, panel de solicitud a la izquierda con origen y destino separados y mapa amplio a la derecha. El aviso de cookies ocupa parte inferior derecha; no se aceptó ni se envió una solicitud. Es evidencia de la web pública en ese momento, no de la aplicación nativa autenticada, su código privado o el comportamiento de un viaje real.

La adaptación de IR conserva esos principios de prioridad y espacio; mantiene su identidad negra y amarillo limón, las tarifas negociadas, PI y ProMaster:

| Antes | Después | Por qué |
| --- | --- | --- |
| Formularios extendidos a todo el ancho y contenedor exterior grande | Formularios de 420–440 dp, jerarquía clara y cabecera compacta | Mantener la lectura y las acciones juntas tanto en teléfono como en escritorio |
| Rejilla decorativa, cinta repetitiva y logo sobredimensionado | Superficies grafito y diagrama geométrico de origen y destino en bienvenida | Comunicar movilidad con contenido propio y menos distracción |
| Categorías y recompensas antes del destino | Destino como primera acción del pasajero; categorías y PI después | Alinear el orden con la tarea de solicitar viaje |
| Hoja sobre el mapa también en escritorio | Desde 1000 dp: navegación de 88 dp, panel de 400 dp y mapa restante | Evitar cubrir el mapa con los controles en una pantalla amplia |
| Menú como única navegación principal | Navegación inferior móvil y rail de escritorio, conservando el menú | Hacer visibles actividad, cuenta, bolsa o puntos |
| Vista del conductor sin mapa continuo al estar libre | Mapa estable, disponibilidad primero y solicitudes después | Dar contexto antes de aceptar o contraofertar |
| Botón de Google activo con proveedor deshabilitado | Botón disponible solo si Supabase anuncia Google habilitado | Evitar una acción que termina siempre en error; la configuración OAuth sigue pendiente |

La tipografía es Geist alojada en la app. Se conserva Google Maps para el mapa real: el diagrama de la bienvenida es ilustrativo y no afirma disponibilidad de vehículos. No se agregaron reservas, pagos integrados, chat ni funciones ajenas al backend actual.

La revisión de composición usa capturas de widgets Flutter en 390×844, 1440×900 y 922×900. En pasajero/conductor se sustituye el mapa por una vista de prueba y los perfiles son sintéticos. Las pruebas de interacción cubren pantallas estrechas, texto ampliado, teclado, seguimiento y recuperación de errores; estas capturas no sustituyen la prueba de mapa y cámara en un teléfono físico.