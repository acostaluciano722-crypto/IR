-- DBeaver: localhost:5433, base ir_promaster_db, esquema public.
-- Ejecutar de nuevo la consulta para actualizar los resultados.
SELECT current_database() AS base, current_schema() AS esquema;

-- Todas las cuentas, incluidos los registros reales de la aplicacion.
SELECT u.correo, u.rol, u.estado, u.fecha_creacion,
       pp.id_pasajero, pc.id_conductor,
       v.id_vehiculo, v.placa, v.categoria
FROM public.usuario u
LEFT JOIN public.perfil_pasajero pp ON pp.id_usuario = u.id_usuario
LEFT JOIN public.perfil_conductor pc ON pc.id_usuario = u.id_usuario
LEFT JOIN public.vehiculo v ON v.id_conductor = pc.id_conductor
ORDER BY u.fecha_creacion DESC;

-- El filtro LIKE 'dbcheck.%@example.test' solo muestra cuentas de prueba.
-- Para buscar una cuenta concreta, agregar WHERE u.correo = 'tu_correo'
-- antes de ORDER BY en la consulta anterior.

SELECT 'usuario' AS tabla, count(*) AS registros FROM public.usuario
UNION ALL SELECT 'perfil_pasajero', count(*) FROM public.perfil_pasajero
UNION ALL SELECT 'perfil_conductor', count(*) FROM public.perfil_conductor
UNION ALL SELECT 'vehiculo', count(*) FROM public.vehiculo
UNION ALL SELECT 'viaje', count(*) FROM public.viaje
UNION ALL SELECT 'ofertas', count(*) FROM public.ofertas
UNION ALL SELECT 'transacciones', count(*) FROM public.transacciones
UNION ALL SELECT 'historial_puntos', count(*) FROM public.historial_puntos;
