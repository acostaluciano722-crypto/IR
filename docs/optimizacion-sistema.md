# Revisión y optimización del sistema

Esta revisión acompaña el cambio a dos árboles binarios por orden de llegada. Se revisaron registro y Auth, modelos y migraciones, viajes/ofertas, puntos y bonificaciones, consultas de presencia e historial, comunicación HTTP de Flutter, administración y herramientas de verificación. No se cambiaron tarifas, generación de PI/PV, umbrales de calificación, negociación, comprobación facial ni fórmulas de pago pendientes de aprobación.

## Cambios con impacto medible

| Área | Problema observado | Cambio y comprobación |
| --- | --- | --- |
| Red | Asignación manual, múltiples raíces y consultas por ancestro | Número único por rol, padre/lado derivados, asignación serializada; pruebas de dos árboles de 15 nodos, altas concurrentes y rollback |
| Propagación de PV | Un acceso al padre y una suma por cada nivel | Un lote de ancestros y una suma agrupada; profundidad 1 y 5 usan la misma cantidad de consultas |
| Resumen de compensación | Sumas de períodos y lados repetidas, transacción incluso para lecturas ya inscritas | Dos agregaciones y lectura de miembros sin escritura; prueba limita la respuesta ordinaria a 8 consultas |
| Actualización de viajes | Precarga de vehículos y ofertas antes de cambiar estado/ubicación | Consulta de acción con propiedad/estado; una consulta de lectura y respuesta final con el mismo contenido completo |
| Liquidación | ORM y soporte contable completo cargado por fuente; división monetaria repetida | Lectura por lotes de UUID/utilidad, una división por fuente; se conserva el redondeo original a centavos |
| Abonos e incentivos | Escrituras y búsquedas dentro del bucle de miembros | Operaciones por lotes; seis abonos usan como máximo 10 consultas y siguen siendo idempotentes y atómicos |
| Historial | PostgreSQL solo tenía claves primarias y el índice por estado | Índices por pasajero/fecha, conductor/fecha y transacción de conductor/fecha; no se duplica el índice existente por estado |
| Calificaciones | Viajes distintos podían actualizar el promedio de un mismo perfil a la vez | Bloqueo del perfil antes de modificar promedio/conteo; se conserva la fórmula y el rechazo de calificaciones repetidas |
| HTTP Flutter | Lecturas idénticas simultáneas podían multiplicar peticiones | Comparten solo la petición en curso; no se almacenan respuestas completadas. La clave incluye URI y autenticación; una escritura, subida de archivo o cierre de sesión invalida las lecturas en curso para el siguiente refresco |

Las pruebas HTTP cubren separación entre sesiones, reintento tras error, refresco después de una escritura y subida de imagen con el cliente inyectado. No se habilitó una caché de saldos, viajes o posiciones ya resueltos.

## Limpieza

Se retiró `backend/modelos_generados.py`: era una copia de 945 líneas del esquema, sin importaciones desde la aplicación. Los modelos activos siguen en `coredata`. También se retiraron los dos módulos `views.py` que solo reexportaban clases; las mismas rutas y nombres importan ahora desde `api_views.py`. Se eliminó el serializador de estado de conductor que no tenía consumidores y el comando de ubicación manual de referidos.

Se conservaron las migraciones históricas aplicadas, las tablas externas y sus columnas heredadas, los prototipos que PRODUCT.md registra como referencia y los recursos usados por pruebas. Suprimirlos no aportaba una mejora de ejecución verificable y podía eliminar contexto o compatibilidad.

## Datos y despliegue

`0010_arrival_binary_network` crea las posiciones por rol, ordena los usuarios existentes y enlaza las cuentas de compensación conservando sus UUID. Una prueba recorre la migración histórica real con saldos y PV previos. `0011_query_indexes` añade únicamente los tres índices de historial. La tabla nueva tiene RLS y acceso directo revocado para clientes.

La distribución monetaria, los límites del 25%, la exigencia personal/grupal y las reglas no aprobadas del PDF permanecen como antes. El árbol del pasajero no participa en la evaluación o reparto del plan del conductor.

Comprobaciones: `backend/run_tests.ps1`, `flutter analyze`, `flutter test` y `backend/.venv/Scripts/python.exe tools/verify_compensation.py`. Las pruebas de base usan una instancia temporal local, sin copiar cuentas o saldos reales. Las capturas de Flutter verifican widgets; el ensayo sobre dispositivos físicos Android/iOS sigue pendiente.
