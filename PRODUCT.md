# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter para la aplicación móvil/adaptable y Django para el backend existente.

## Users

El usuario principal es el pasajero (usuario rider) que necesita movilizarse dentro del área de cobertura, inicialmente Cartagena, Colombia. Solicita viajes, propone una tarifa, compara respuestas de conductores y elige la opción que mejor le conviene.

El conductor usa la misma app con su propio espacio operativo: controla su disponibilidad, revisa solicitudes cercanas, acepta o contraoferta y acompaña el viaje. Su prioridad visual es atender esas solicitudes; bolsa, actividad y ProMaster quedan accesibles como tareas secundarias.

## Product Purpose

IR conecta pasajeros y conductores para solicitar y completar viajes. El pasajero inicia la demanda indicando origen, destino, categoría y una oferta, consulta la ruta y el valor sugerido, recibe ofertas y puede seleccionar un conductor. El éxito del producto consiste en que el pasajero pueda completar ese flujo con información clara y seguimiento de su viaje.

## Positioning

IR convierte la solicitud de transporte en una interacción negociable: el pasajero propone un precio respetando la tarifa mínima legal, recibe contraofertas o aceptaciones de conductores cercanos y decide con base en precio, tiempo, calificación y categoría del vehículo. El sistema de puntos IR (PI), rangos ProMaster y bonificaciones añade una economía de fidelización a la experiencia de transporte.

## Operating Context

La experiencia se usa desde un dispositivo móvil con ubicación activa, dentro de Cartagena durante la fase inicial. El pasajero consulta mapas, busca destinos, estima rutas, solicita viajes, revisa ofertas y puede consultar viajes recientes, puntos, bonificaciones, soporte y perfil. En la primera fase, el pago del viaje se realiza directamente al conductor, principalmente en efectivo o transferencia; la plataforma no retiene el pago del trayecto.

## Capabilities and Constraints

- La aplicación debe conservar el mapa, geolocalización, búsqueda de lugares, rutas, tarifas, categorías de vehículo, solicitudes, ofertas, viajes recientes y navegación a puntos, bonificaciones, historial, soporte y perfil.
- El acceso compartido usa Supabase Auth con correo, contraseña, confirmación y recuperación. Google aparece solo cuando su proveedor OAuth está configurado; los códigos SMS requieren un proveedor adicional.
- Pasajeros y conductores completan una primera comparación facial entre la foto de su documento y una selfie tomada en ese momento. La selfie aceptada genera su foto de perfil.
- La comprobación se renueva cada dos meses calendario, calculados en Bogotá, comparando la nueva selfie con selfies anteriores aceptadas. El servidor exige la comprobación vigente para operar cuando la política está habilitada.
- El documento y la selfie original no se conservan: las referencias faciales se cifran en el backend y la foto derivada se aloja en Storage privado. El usuario puede eliminar su registro facial y volver a completar el flujo. La comparación no certifica la autenticidad del documento ni la identidad civil.
- La ubicación del conductor se publica mientras está disponible y se muestran vehículos activos cercanos al pasajero cuando prepara una solicitud.
- El conductor controla su disponibilidad, consulta solicitudes cercanas y conserva los flujos de aceptación, contraoferta, bolsa y seguimiento del viaje.
- La cartera del conductor muestra saldo y movimientos. Las recargas reales requieren una pasarela; el flujo local de desarrollo es solo una simulación.
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
