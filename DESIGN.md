---
name: IR
description: Interfaz de movilidad negociable para pasajeros en Cartagena.
colors:
  ink: "#171B1D"
  surface-deep: "#111213"
  surface-raised: "#202122"
  surface-input: "#303031"
  accent-lemon: "#E8F044"
  text-primary: "#FFFFFF"
  text-secondary: "#FFFFFFB3"
  map-road: "#28333E"
  map-water: "#091017"
typography:
  body:
    fontFamily: "Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.2
rounded:
  sm: "12px"
  md: "14px"
  lg: "18px"
  sheet: "30px"
spacing:
  sm: "8px"
  md: "14px"
  lg: "16px"
components:
  primary-action:
    backgroundColor: "{colors.accent-lemon}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    height: "52px"
  surface:
    backgroundColor: "{colors.surface-raised}"
    rounded: "{rounded.md}"
---

# Design System: IR

## Overview

**Creative North Star: "Cabina de navegación nocturna"**

IR es una herramienta operativa para pedir un viaje con claridad bajo presión de tiempo. La pantalla deja que el mapa explique el contexto y concentra la decisión en una hoja inferior de control. El lenguaje es minimalista, oscuro y táctil: el amarillo no decora, señala aquello que puede seleccionarse, confirmarse o requiere atención.

La dirección evita dashboards fragmentados, degradados, adornos decorativos y etiquetas de prototipo. Las superficies planas y los bordes sutiles crean jerarquía sin sombras; el contenido de la ruta, tarifa y estado siempre tiene prioridad sobre la marca.

**Key Characteristics:**
- Mapa oscuro como escenario continuo.
- Hoja inferior negra como instrumento principal.
- Amarillo limón reservado para acción, selección, ruta y estado.
- Contraste alto y controles táctiles amplios.

## Colors

La paleta es restringida: carbón, negro profundo, superficies elevadas y un único acento amarillo.

### Primary
- **Amarillo limón IR** (`#E8F044`): Selección activa, ruta, tarifas, puntos y acción primaria.

### Neutral
- **Carbón IR** (`#171B1D`): Texto oscuro sobre amarillo y elementos base del tema.
- **Negro profundo** (`#111213`): Hoja inferior, controles flotantes y overlays de navegación.
- **Superficie elevada** (`#202122`): Viajes recientes y resumen de ruta.
- **Campo de entrada** (`#303031`): Campo principal de destino.
- **Blanco** (`#FFFFFF`): Texto principal e iconos de alto contraste.
- **Blanco secundario** (`#FFFFFFB3`): Origen, metadatos y texto auxiliar.

### Named Rules
**The One Accent Rule.** El amarillo aparece solo cuando comunica selección, acción, ruta, precio o atención; las superficies no compiten con él.

## Typography

**Display Font:** Arial (fallback sans-serif)
**Body Font:** Arial (fallback sans-serif)
**Label Font:** Arial (fallback sans-serif)

**Character:** La tipografía es directa, compacta y legible en movimiento. El peso distingue acción y contexto sin depender de tamaños ornamentales.

### Hierarchy
- **Headline** (700, 20px): Mensajes de tarea y navegación.
- **Title** (700, 17px): Destino, resumen y viajes recientes.
- **Body** (400-600, 16px): Lugares, origen y estados.
- **Label** (700, 12px): ProMaster, metadatos y detalles secundarios.

## Layout

La pantalla usa un mapa a pantalla completa con controles flotantes dentro del área segura. La hoja inferior es desplazable y redondeada en sus dos esquinas superiores; su orden es selector de vehículo, ProMaster, destino, ruta/tarifa y contenido secundario. El selector conserva desplazamiento horizontal cuando el ancho no permite mostrar las cuatro categorías. Los controles táctiles principales mantienen al menos 48dp.

## Elevation & Depth

El sistema usa profundidad tonal y bordes de 1px, no sombras decorativas. La hoja se separa del mapa por contraste; las superficies internas usan `#202122` y borde `#2D2E2F`; los controles flotantes usan negro profundo con borde `#343638`.

## Shapes

La hoja usa 30px en su borde superior. Campos y resúmenes usan 14-18px; viajes recientes usan 12px. Las categorías usan 16px para crear una silueta táctil clara. Los controles circulares del mapa tienen 58px de diámetro y borde sutil.

## Components

### Selector de vehículo
- **Shape:** Cuatro controles horizontales de 96x88px, radio 16px.
- **Selected:** Amarillo limón con icono y texto carbón.
- **Unselected:** Superficie `#191A1B`, texto blanco secundario y borde `#3A3B3C`.

### Hoja de solicitud
- **Shape:** Superficie `#111213`, radio superior 30px, scroll vertical y asa visible.
- **Primary:** Botón amarillo de altura mínima 52px para solicitar el viaje.
- **States:** Loading con indicador, mensaje de error o confirmación en amarillo, ruta y tarifa cuando hay datos.

### Cards / Containers
- **ProMaster:** Superficie `#191A1B`, borde `#2B2C2D`, radio 14px.
- **Route and recent ride:** Superficie `#202122`, borde `#2D2E2F`, radios 12-14px.
- **Navigation overlay:** Negro profundo con alpha alto y borde sutil para mantener legibilidad sobre el mapa.

## Do's and Don'ts

- **Do:** Mantener visible la acción de solicitar cuando existe destino válido.
- **Do:** Usar amarillo para una sola señal semántica clara por grupo.
- **Do:** Conservar el mapa y la ubicación real como contexto primario.
- **Do:** Respetar safe areas, tamaños táctiles y escalado de texto del sistema.
- **Don't:** Reintroducir una ruta o etiqueta de “prototipo”.
- **Don't:** Añadir degradados, sombras duras, tarjetas anidadas o colores de acento adicionales.
- **Don't:** Ocultar ruta, tarifa, estado u ofertas detrás de decoración.