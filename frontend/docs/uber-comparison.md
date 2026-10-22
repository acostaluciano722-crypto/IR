# Referencia de movilidad: Uber e IR

Revisión del 21 de octubre de 2026. El alcance es la experiencia compartida de búsqueda, mapa, recogida y seguimiento. Las reglas de IR sobre tarifas, negociación, estados del viaje, cartera, PI, niveles y bonificaciones quedan fuera de los cambios.

## Evidencia y límites

- REA 6.7.0 abrió `https://m.uber.com/` en un Chrome temporal y observó su pantalla pública en `/go/home`: campos separados para recogida y destino. Evidencia `ev_3d5ba38840359fbd2c34149e38ba015d4ffc075a1a7c78367767b8dff925e9c9`.
- REA abrió la [guía oficial de la app del conductor](https://www.uber.com/us/en/drive/driver-app/) y capturó su contenido accesible. Evidencia `ev_d212c6b6b0515dd8e345b4bd98002aa1919289cbd178fbe53e230ecf080af726`.
- Las capturas completas se conservan localmente en `artifacts/research/uber-rider-evidence.json` y `artifacts/research/uber-public-evidence.json`, excluidas de Git. Ambos navegadores temporales finalizaron correctamente.
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
