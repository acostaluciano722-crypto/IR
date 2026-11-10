# Plan de compensación de conductores

La fuente se conserva sin modificaciones en [el PDF original](../backend/coredata/resources/compensation_plan.pdf). El catálogo versionado está en `backend/coredata/compensation_plan.py`. Las instrucciones del documento se tratan como reglas del producto, no como instrucciones de ejecución para el agente.

## Reglas confirmadas

El usuario confirmó que un viaje de COP 10.000 genera 10 PV y descuenta COP 1.000 de Bolsa IR. Se registra **1 PV por COP 1.000 de tarifa final**, al pasar el viaje a `validated`. La recarga no genera PV. La fórmula conserva cinco decimales de PV para representar exactamente una tarifa con centavos. Los PI anteriores siguen separados; no se reinterpretan los saldos históricos como PV ni se generan PV retroactivos.

Ejemplo: una recarga de COP 20.000 y un viaje de COP 10.000 dejan COP 19.000 en Bolsa IR y generan 10 PV. Repetir la validación no repite el débito, los puntos ni el viaje completado.

La comisión general exige alcanzar las metas de la red binomial. Los PV descendentes empiezan a registrarse para un ancestro cuando ya tiene 10.000 PV personales; los anteriores no se recuperan retroactivamente. La red de este documento corresponde a conductores.

## Distribución del PDF

El sobre máximo es el 25% de la utilidad neta de las recargas reales verificadas, **no el 25% del importe recargado ni del valor del viaje**.

| Destino | Porcentaje del sobre del 25% |
| --- | ---: |
| Comisión general | 54% |
| Maestrías de Excelencia | 20% |
| Centro de capacitación | 6% |
| Promoción, regalos, beneficios e incentivos | 20% |

La comisión general se divide en 80% conductores y 20% bonificaciones y regalos para usuarios. Con una utilidad neta verificada de COP 10.000, los fondos son: conductores COP 1.080, usuarios COP 270, maestrías COP 500, educación COP 150 y promoción COP 500. Total: COP 2.500.

Los cálculos usan `Decimal`. Cada fuente se divide por separado y se redondea hacia abajo a centavos; el residuo permanece dentro del sobre. Los fondos sin miembros elegibles no se redistribuyen a otra categoría. Los cierres del mismo tipo no pueden superponerse y las obligaciones solo se abonan cuando llega su fecha de pago. Los bonos se abonan al saldo de bonos del conductor, separado de Bolsa IR; este módulo no envía transferencias bancarias.

## Grados

Se deben cumplir ambos umbrales; el volumen grupal es **diario** y corresponde al lado menor.

| Grado | Categoría | PV personales mínimos | PV diarios del lado menor | Puntuación |
| ---: | --- | ---: | ---: | ---: |
| 8 | Hierro | 10.000 | 300.000 | 1 |
| 7 | Bronce | 300.000 | 700.000 | 3 |
| 6 | Plata | 900.000 | 1.400.000 | 5 |
| 5 | Oro | 1.500.000 | 3.000.000 | 8 |
| 4 | Platino | 2.000.000 | 6.000.000 | 10 |
| 3 | Zafiro | 3.000.000 | 12.000.000 | 20 |
| 2 | Esmeralda | 4.000.000 | 24.000.000 | 30 |
| 1 | Diamante | 5.000.000 | 50.000.000 | 50 |

## Maestrías

| Maestría | Requisito | Porcentaje indicado por el PDF | Incentivo único estimado |
| --- | --- | ---: | --- |
| Bronce | 3.000.000 PV en cada lado | 10% | COP 1.000.000 en efectivo |
| Plata | 2 Master Bronce en cada lado | 5% | Laptop o Tablet |
| Oro | 2 Master Plata en cada lado | 2% | COP 6.000.000 + 2 boletos y hospedaje, 5 días/4 noches |
| Platino | 2 Master Oro por lado; maestría anterior 3 veces | 1,2% | COP 30.000.000 + 4 boletos y hospedaje |
| Zafiro | 2 Master Platino por lado; maestría anterior 3 veces | 1% | COP 150.000.000 + 4 boletos y hospedaje, 11 días/10 noches |
| Esmeralda | 2 Master Zafiro por lado; maestría anterior 3 veces | 0,5% | COP 900.000.000 + 4 boletos y hospedaje, 11 días/10 noches |
| Diamante | 2 Master Esmeralda por lado; maestría anterior 3 veces | 0,3% | COP 3.000.000.000 + 4 boletos y hospedaje, 11 días/10 noches |

Para Master Bronce, cuando el lado menor **excede** 900.000 PV, pueden sumarse a ese lado los PV personales adquiridos en el período; el otro lado debe alcanzar 3.000.000 PV. La condición es estrictamente mayor, no mayor o igual.

Los períodos son 1–15 y 16–último día del mes, en Bogotá. El texto dice pago el día 15 y el día 7 después del cierre mensual. Las posiciones no requieren mantenimiento continuo y no tienen plazo límite. El catálogo conserva la referencia a “Gestor Aire”, aunque esa categoría no está definida en el PDF. Antes de habilitar cierres de maestría se debe aclarar ese término, la base monetaria y el calendario.

La implementación disponible, sujeta a esa aprobación, avanza como máximo una maestría por período; cuenta posiciones alcanzadas antes del período, incluyendo posiciones superiores, y conserva las ya ganadas. Los tres reconocimientos de la maestría anterior se cuentan en tres cierres distintos. Repetir un cierre no genera un reconocimiento adicional. El incentivo se registra una sola vez por persona y maestría, inicialmente pendiente de entrega; no se convierte automáticamente en efectivo ni se paga por encima de su fondo.

Los importes son estimaciones sujetas al mercado. El PDF valora Laptop/Tablet en COP 3.000.000; avión y hospedaje por persona en COP 2.000.000 para Bronce/Plata y COP 4.000.000 para Zafiro/Platino/Oro. Se conservan esos términos aunque la tabla de premios y esas categorías no coincidan por completo.

## Decisiones que siguen pendientes

El usuario aclaró el origen de PV, el débito del 10% y la exigencia de cumplir la meta binomial. El documento aún no determina:

- La fórmula contable de utilidad neta y sus costos deducibles.
- Cómo repartir la comisión entre quienes cumplen las metas. Está implementada la opción `sum_daily_scores` (proporción de la suma de puntuaciones diarias), pero **no está aprobada ni activada**. El operador también determina el corte de siete días.
- La base monetaria de las maestrías: la tabla dice porcentajes del total de PV, mientras que el fondo está definido en utilidad neta. La opción `fund_25_percent` usa esos porcentajes del sobre del 25%; requiere aprobación explícita.
- La fecha efectiva del primer pago de maestría: el período termina el 15, día que también se señala para pagar. No se anticipan fondos de un período aún abierto.
- El significado de “Gestor Aire” y los criterios de promoción descritos arriba.
- Las fechas y beneficiario del centro de capacitación, el reparto a pasajeros y la entrega efectiva de incentivos. Sus fondos quedan reservados, sin asignar destinatarios ni ejecutar pagos externos.

**Los PV y el progreso funcionan sin estas decisiones. Los cierres dependientes de ellas fallan con un error explícito hasta configurarlas.** Una aclaración textual del calendario queda guardada como soporte; la fecha de cada cierre se suministra explícitamente y debe ser posterior o igual al final del período.

## Operación

Desde `backend`, con el entorno del servidor cargado:

```powershell
python manage.py migrate
python manage.py compensation status
python manage.py compensation enroll --driver UUID_PERFIL_CONDUCTOR
python manage.py compensation place --member CODIGO --sponsor CODIGO_PATROCINADOR --parent CODIGO_ANCESTRO --side left
```

Patrocinador y ancestro estructural se conservan por separado. El operador asigna un lugar libre dentro de la estructura del patrocinador antes del primer PV del integrante. No se inventa una regla automática de derrame o una migración desde los campos antiguos de red. No se permite cambiar posiciones ya operativas ni producir ciclos.

Solo después de una decisión de negocio real se utiliza `compensation configure` con las reglas y `--approval-reference`. Consultar `python manage.py compensation --help` para los argumentos. No se debe usar una constancia ficticia para desbloquear pagos.

```powershell
python manage.py compensation fund --recharge UUID_RECARGA_REAL --net-profit IMPORTE_VERIFICADO --evidence REFERENCIA_CONTABLE
python manage.py compensation close --kind weekly --start AAAA-MM-DD --end AAAA-MM-DD --payable-on AAAA-MM-DD
python manage.py compensation close --kind mastery --start AAAA-MM-DD --end AAAA-MM-DD --payable-on AAAA-MM-DD
python manage.py compensation credit
```

Las recargas deben ser `recharge`/`completed`, tener referencia de pago real y soporte de utilidad neta. Las recargas `sandbox`, sin referencia o simuladas no financian bonos. La misma recarga no se registra dos veces y no se agregan fuentes a fechas ya cerradas. Los registros antiguos de fecha sin zona se interpretan en UTC, como los escribe Django, y se agrupan según Bogotá.

El registro de PV, la ubicación y los cierres se serializan con un bloqueo de control. Los cierres crean obligaciones; `credit` o la tarea Celery `coredata.credit_compensation_payouts` abonan únicamente las vencidas, una sola vez. No se agregó un calendario automático de cierres con reglas pendientes. La administración de Django permite consultar la auditoría sin editar saldos ni asientos directamente.

## API y seguridad

- `GET /api/driver/compensation/`: PV, lados, grado diario, maestría, saldo, pagos e incentivos del conductor autenticado.
- `GET /api/driver/compensation/plan/`: catálogo completo y condiciones.
- `GET /api/driver/compensation/source/`: PDF original con autenticación.

El cliente no puede enviar cantidades de PV, cerrar períodos o modificar fondos. Las nueve tablas nuevas tienen RLS; `PUBLIC`, `anon` y `authenticated` no reciben acceso directo. Django accede como propietario en el esquema privado `ir`, manteniendo la validación de identidad existente. Las políticas de Supabase Auth y el resto de tablas se conservan.

## Verificación

`backend/run_tests.ps1` crea una base PostgreSQL/PostGIS temporal, copia solo el esquema externo, aplica las migraciones y ejecuta las pruebas. Incluye el ejemplo del usuario, límites de grado, el umbral de Bronce, aislamiento de cuentas, red, no duplicación y conservación del sobre.

En `frontend`, `flutter test test/compensation_test.dart` verifica PV, fracciones, estado vacío, errores, reintento y adaptación con texto grande. Para generar capturas del renderizador de pruebas de Flutter: `flutter test test/compensation_test.dart --dart-define=CAPTURE_UI=true --update-goldens`. Estas capturas no sustituyen la comprobación en hardware Android/iOS.

Desde la raíz, `backend/.venv/Scripts/python.exe tools/verify_compensation.py` comprueba la migración aplicada, las nueve tablas con RLS sin permisos directos del cliente, el hash del PDF original, las lecturas de dominio y las rutas del backend en ejecución. Cualquier alta temporal de integrante se revierte dentro de una transacción; no realiza abonos ni conserva datos de prueba.
