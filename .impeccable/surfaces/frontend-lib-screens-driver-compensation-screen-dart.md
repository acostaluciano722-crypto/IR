---
version: 1
slug: "frontend-lib-screens-driver-compensation-screen-dart"
primary_target: "frontend/lib/screens/driver_compensation_screen.dart"
related_targets:
  - "frontend/lib/screens/bonus_screen.dart"
  - "frontend/lib/screens/driver_home_screen.dart"
---

## Scope & Mode

Extensión Operate/Read de Bonificaciones del conductor: consultar PV personales, activación de red a los 10.000 PV, volúmenes diarios izquierdo/derecho, grado, maestrías quincenales, liquidaciones fechadas y condiciones del PDF. El producto tiene dos árboles independientes, de pasajeros y de conductores, ordenados por registro, de izquierda a derecha y por niveles; sus puntos y bonos no se mezclan. Esta superficie consulta el árbol del conductor. Los PI permanecen separados de los PV y las reglas monetarias sin confirmar se muestran pendientes.

## Thesis

La lectura ordenada del avance precede al catálogo: primero qué ha acumulado el conductor y después qué condiciones explican ese resultado. No se convierte una regla pendiente en una promesa de pago.

## Own-world

Se conserva el mundo negro/amarillo de PRODUCT.md y los componentes compartidos actuales. La implementación usa IrColors, Geist, iconos Material y superficies planas; el amarillo señala acciones. DESIGN.md conserva deriva previa respecto a Geist y algunos valores oscuros de ir_theme.dart; esta extensión no la repara ni la convierte en nuevos tokens normativos.

## Story

Desde Bonificaciones se consultan los PV y el umbral de activación, la red de hoy, las maestrías y los abonos. Cuando account.network está disponible, se muestra su posición en el árbol de conductores y se explica la asignación automática por registro, de izquierda a derecha y por niveles; no se solicita patrocinador ni ubicación manual. El código de integrante puede copiarse. Los detalles de reglas pendientes, ocho grados, siete maestrías, distribución del fondo y calendario se descubren mediante expansiones. Hay actualización, error con reintento e historial vacío.

## First viewport

Encabezado local con actualización, título de lectura, explicación de PV/débito y puntos personales. IrPageBody limita la lectura a 760 dp dentro del área segura; ListView permite recorrer el contenido y Wrap deja pasar las métricas a otra línea con poco ancho o texto ampliado.

## Form

Título local de 30 dp, secciones de 20 dp, pesos 700 para jerarquía y valores, separaciones de sección de 28 dp y márgenes horizontales de 20 dp. Lista continua sin tarjetas decorativas; estos valores describen esta superficie, no amplían el sistema global.

## Finish

Evidencia regenerada en artifacts/compensation/: phone.png, tablet.png, phone-large-text.png y sus variantes -details.png. Son capturas del renderizador de pruebas Flutter con datos de prueba, a 390×844, 1024×768 y 320×740 con escala de texto 1,8; el catálogo del fixture contiene una muestra, no prueba visual de todas sus entradas. tablet.png muestra la posición 2 del fixture y la explicación de asignación automática. La revisión de esta extensión de copia devolvió `ship`, limitado al párrafo de posición automática en los widgets inspeccionados; no implica aprobación general ni verifica ese párrafo fuera del primer encuadre con texto 1,8. Las tres pruebas UI cubren lectura de PV fraccionarios, reintento, centavos, umbral e historial vacío. La revisión nativa en emulador, hardware Android e iOS sigue pendiente; estas capturas no la sustituyen ni verifican por sí solas el aislamiento de los árboles en el backend.
