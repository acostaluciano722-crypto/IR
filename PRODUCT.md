# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter para la aplicación móvil/adaptable y Django para el backend existente.

## Users

El usuario principal es el pasajero (usuario rider) que necesita movilizarse dentro del área de cobertura, inicialmente Cartagena, Colombia. Solicita viajes, propone una tarifa, compara respuestas de conductores y elige la opción que mejor le conviene.

## Product Purpose

IR conecta pasajeros y conductores para solicitar y completar viajes. El pasajero inicia la demanda indicando origen, destino, categoría y una oferta, consulta la ruta y el valor sugerido, recibe ofertas y puede seleccionar un conductor. El éxito del producto consiste en que el pasajero pueda completar ese flujo con información clara y seguimiento de su viaje.

## Positioning

IR convierte la solicitud de transporte en una interacción negociable: el pasajero propone un precio respetando la tarifa mínima legal, recibe contraofertas o aceptaciones de conductores cercanos y decide con base en precio, tiempo, calificación y categoría del vehículo. El sistema de puntos IR (PI), rangos ProMaster y bonificaciones añade una economía de fidelización a la experiencia de transporte.

## Operating Context

La experiencia se usa desde un dispositivo móvil con ubicación activa, dentro de Cartagena durante la fase inicial. El pasajero consulta mapas, busca destinos, estima rutas, solicita viajes, revisa ofertas y puede consultar viajes recientes, puntos, bonificaciones, soporte y perfil. En la primera fase, el pago del viaje se realiza directamente al conductor, principalmente en efectivo o transferencia; la plataforma no retiene el pago del trayecto.

## Capabilities and Constraints

- La aplicación debe conservar el mapa, geolocalización, búsqueda de lugares, rutas, tarifas, categorías de vehículo, solicitudes, ofertas, viajes recientes y navegación a puntos, bonificaciones, historial, soporte y perfil.
- El backend existente es Django y la aplicación cliente existente es Flutter.
- La interfaz y la terminología principal deben permanecer en español.
- Los importes se expresan en pesos colombianos (COP).
- La oferta del pasajero no puede estar por debajo de la tarifa mínima legal vigente definida por el producto.
- Las categorías actuales incluyen carro económico, moto, Viaje+ y Comfort.
- Los viajes completados generan PI y contribuyen al nivel ProMaster del pasajero.
- El producto debe conservar el flujo funcional existente al adaptar la interfaz visual.
- La cobertura inicial es Cartagena; la expansión geográfica queda abierta.

## Brand Commitments

El nombre del producto es IR. La interfaz principal debe conservar la dirección visual solicitada por el producto: negro como color predominante y amarillo como color de resaltado, tomando como referencia el prototipo del pasajero sin exponer la etiqueta ni el flujo de prototipo.

## Evidence on Hand

- Aplicación Flutter y flujo funcional del pasajero en `frontend/lib/screens/passenger_home_screen.dart`.
- Servicio de integración con backend en `frontend/lib/services/api_service.dart`.
- Backend Django en `backend/`.
- Prototipo de referencia y componentes mock en `frontend/lib/screens/passenger_home_mock_screen.dart` y pantallas mock relacionadas.
- El repositorio contiene mapa Google Maps, seguimiento de ubicación y datos de rutas integrados en la pantalla funcional.
- No hay testimonios, métricas de adopción ni material comercial confirmado; futuras interfaces no deben fabricarlos.

## Product Principles

- El pasajero conserva agencia para proponer y elegir.
- La información de precio, ruta y estado debe ser comprensible antes de confirmar.
- La ubicación y el estado del viaje deben mantenerse actualizados.
- La progresión ProMaster debe convertir el uso recurrente en beneficios comprensibles.
- La interfaz visual puede cambiar, pero no debe degradar las capacidades funcionales existentes.

## Accessibility & Inclusion

No se ha establecido todavía un estándar formal de accesibilidad. Deben conservarse controles legibles, contraste suficiente entre negro, amarillo y texto, objetivos táctiles adecuados y estados de carga/error comprensibles en español.