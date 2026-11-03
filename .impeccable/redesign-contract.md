# Rediseño IR · 3 de noviembre de 2026

## THESIS

IR debe hacer que pedir o atender un viaje sea la primera tarea visible. La disposición toma como referencia la web pública de Uber, conservando IR negro/amarillo, negociación de tarifas y PI/ProMaster. Es una app operativa Flutter; la bienvenida presenta la propuesta sin convertirse en una página de marketing larga.

## OWN-WORLD

Superficies grafito planas, amarillo limón para acción o selección, tipografía Geist alojada en la app, iconografía Material, bordes sutiles y espacios medidos. Sin rejilla decorativa, cinta repetitiva, logotipo gigante, métricas inventadas ni contenedores anidados para formularios. El diagrama de bienvenida es geometría original de origen/ruta/destino, no disponibilidad simulada.

## STORY

La bienvenida lleva a crear cuenta o entrar. El acceso y la recuperación usan un formulario compacto. Tras completar el perfil, el primer acceso pide foto de documento, consentimiento y selfie de cámara. La coincidencia genera la foto de perfil; las renovaciones cada dos meses calendario usan las selfies aceptadas anteriores.

El pasajero empieza por el destino y después categoría, ruta y oferta. El conductor controla su disponibilidad y atiende solicitudes. Actividad, cuenta, puntos y bolsa permanecen accesibles sin desplazar la tarea de movilidad. Cerrar sesión siempre está disponible.

## FIRST VIEWPORT

En teléfono: cabecera compacta, mapa continuo y panel inferior desplazable sobre navegación fija. Pasajero muestra destino antes de categorías; conductor muestra disponibilidad y solicitudes antes de bolsa/PI. En escritorio desde 1000 dp: rail de 88 dp, panel de 400 dp y mapa expandido. El formulario de acceso mide 420–440 dp; la bienvenida muestra el mensaje y ambas acciones sin un marco sobredimensionado. El flujo facial explica primero qué compara y qué conserva, y muestra el paso del documento antes de la selfie.

## FORM

Código directo en Flutter, elección expresa del usuario; no existe comp aprobada. La referencia estructural es Uber, con la marca IR fijada por el usuario. El brief anterior conserva seed key `ccc495c3`; no se presenta como una nueva tirada. La selección de GPT Taste se ejecutó con seed 450 y se adaptó a Operate: bienvenida centrada, sans Geist y transiciones breves nativas. No se introduce GSAP en Flutter ni scroll decorativo en controles de uso frecuente.

La interacción distintiva es seleccionar destino/categoría y leer ruta, tarifa y estado sin abandonar mapa/panel. La presión de botones dura 120 ms a escala .97 y las entradas de contenido duran 240 ms, respetando movimiento reducido. La navegación entre pantallas utiliza las rutas Material adaptativas de Flutter, conservando el gesto de retroceso de iOS y las preferencias de accesibilidad del sistema.

## QUALITY BAR

La jerarquía debe leerse con una sola mirada: destino en pasajero y disponibilidad/solicitudes en conductor. Controles principales de al menos 48 dp, separación entre grupos, secundarios con contraste legible, texto ampliado y teclado sin perder la tarea. Los estados disabled, carga y error deben ser distinguibles. Google se ofrece únicamente con proveedor configurado. Ningún texto afirma autenticidad documental o identidad civil certificada.

La evidencia de cierre cubre 390×844, 1440×900 y formularios a 922×900. Las capturas de widgets contienen mapas sustituidos y perfiles sintéticos, por lo que acreditan composición; mapa nativo, áreas seguras físicas y aceptación real de documento/selfie requieren prueba de dispositivo. No se ejecuta detector HTML/CSS sobre Dart.
