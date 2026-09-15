---
version: 1
slug: "frontend-lib-screens-passenger-home-screen-dart"
primary_target: "frontend/lib/screens/passenger_home_screen.dart"
related_targets: []
---

## Scope & Mode

Pantalla principal del pasajero en modo Operate. La tarea central es solicitar un viaje desde la ubicación actual: buscar destino, entender ruta/tarifa, elegir categoría y enviar la solicitud. Debe conservar ofertas, viajes recientes, lugares cercanos, puntos y accesos de cuenta sin competir con la tarea principal.

## Thesis

La pantalla es una cabina de navegación nocturna, no un dashboard de tarjetas: el mapa demuestra el contexto y una hoja de control concentra la decisión. Rechaza la composición clara y fragmentada del prototipo de bienvenida; cada elemento existe para llevar al pasajero de destino a solicitud con el menor ruido posible.

## Own-world

Negro carbón y superficies casi negras como escena de uso nocturno; amarillo limón únicamente para selección, acción primaria, ruta y estados de atención. Texto blanco de alta legibilidad y gris cálido para secundarios. Controles táctiles de 48dp, bordes suaves de 14-18dp, iconografía Material consistente, sin degradados, sin sombras decorativas y sin etiquetas de prototipo.

## Story

El pasajero ve dónde está, abre el panel, elige Viaje/Moto/Viaje+/Comfort, escribe el destino y recibe inmediatamente la ruta y la tarifa estimada. Después confirma la solicitud y puede leer el estado u ofertas sin abandonar la superficie. ProMaster y el historial permanecen disponibles como información secundaria, no como obstáculos.

## First viewport

El mapa ocupa todo el fondo y conserva controles de menú y recenter en la parte superior con objetivos táctiles amplios. Una hoja negra anclada abajo muestra primero el selector de categoría, luego el estado ProMaster compacto y el campo “¿A dónde y por cuánto?”. Cuando existe destino, la ruta, tarifa y botón amarillo de solicitud quedan juntos y visibles; el contenido restante se descubre mediante desplazamiento de la hoja.

## Form

Cabina de navegación nocturna, dirección propia derivada de la restricción de marca. Seed key ccc495c3; la composición mantiene el mapa como escenario, la hoja como instrumento y la selección amarilla como señal única. La interacción firma es el cambio de categoría y la aparición de la ruta/tarifa dentro de la hoja, sin cambiar de pantalla.

## Finish

unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
