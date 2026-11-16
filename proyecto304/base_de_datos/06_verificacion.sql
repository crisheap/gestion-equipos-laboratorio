-- =====================================================================
-- 06 · Verificación de la base (solo lectura)
-- Ejecutar al final. Compara cada valor con lo esperado.
-- =====================================================================
SELECT 'recursos' AS dato, count(*)::text AS valor, '15' AS esperado FROM recursos
UNION ALL SELECT 'usuarios', count(*)::text, '40' FROM usuarios
UNION ALL SELECT 'franjas', count(*)::text, '7110' FROM franjas
UNION ALL SELECT 'última fecha con franjas', max(fecha)::text, '2026-12-31' FROM franjas
UNION ALL SELECT 'días hábiles con franjas', count(DISTINCT fecha)::text, '79' FROM franjas
UNION ALL SELECT 'reservas del profesor (id ≤ 570)', count(*)::text, '570' FROM reservas WHERE id <= 570
UNION ALL SELECT 'franjas con dos reservas activas', count(*)::text, '0'
  FROM (SELECT franja_id FROM reservas WHERE estado = 'activa' GROUP BY franja_id HAVING count(*) > 1) x
UNION ALL SELECT 'equipos sin hora tope', count(*)::text, '0' FROM recursos WHERE hora_tope IS NULL
UNION ALL SELECT 'reservas sin hora tope', count(*)::text, '0' FROM reservas WHERE hora_tope IS NULL
UNION ALL SELECT 'función reservar_franja', count(*)::text, '1' FROM pg_proc WHERE proname = 'reservar_franja'
UNION ALL SELECT 'función registrar_devolucion', count(*)::text, '1' FROM pg_proc WHERE proname = 'registrar_devolucion'
UNION ALL SELECT 'función crear_reserva_dos_semanas', count(*)::text, '1' FROM pg_proc WHERE proname = 'crear_reserva_dos_semanas'
UNION ALL SELECT 'tablas con RLS activo', count(*)::text, '4'
  FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('recursos','franjas','reservas','usuarios') AND rowsecurity;
