-- =====================================================================
-- 00 · Diagnóstico (solo lectura): ¿en qué estado está la base?
-- Ejecutarlo PRIMERO. No cambia nada. La última columna dice qué hacer.
-- =====================================================================
WITH e AS (
  SELECT
    to_regclass('public.franjas') IS NOT NULL                                   AS hay_tablas,
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'reservas' AND column_name = 'hora_tope') > 0 AS hay_hora_tope,
    (SELECT count(*) FROM pg_proc WHERE proname = 'reservar_franja') > 0         AS hay_reservar_franja,
    (SELECT count(*) FROM pg_proc WHERE proname = 'crear_reserva_dos_semanas') > 0 AS hay_dos_semanas
)
SELECT
  hay_tablas, hay_hora_tope, hay_reservar_franja, hay_dos_semanas,
  CASE WHEN hay_tablas THEN (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM franjas', false, true, '')))[1]::text END AS franjas,
  CASE WHEN hay_tablas THEN (xpath('/row/c/text()', query_to_xml('SELECT max(fecha) AS c FROM franjas', false, true, '')))[1]::text END AS ultima_fecha,
  CASE WHEN hay_tablas THEN (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM reservas', false, true, '')))[1]::text END AS reservas,
  CASE WHEN hay_tablas THEN (xpath('/row/c/text()', query_to_xml(
    'SELECT count(*) AS c FROM franjas WHERE fecha IN (''2026-10-12'',''2026-11-02'',''2026-11-16'',''2026-12-08'')', false, true, '')))[1]::text END AS franjas_en_festivos,
  CASE
    WHEN NOT hay_tablas THEN
      'Base vacía: ejecutar 01, 02, 03, 04, 05 y 06.'
    WHEN (xpath('/row/c/text()', query_to_xml('SELECT max(fecha) AS c FROM franjas', false, true, '')))[1]::text = '2026-10-02' THEN
      'Solo datos base del profesor: ejecutar 03, 04, 05 y 06.'
    WHEN (xpath('/row/c/text()', query_to_xml(
          'SELECT count(*) AS c FROM franjas WHERE fecha IN (''2026-10-12'',''2026-11-02'',''2026-11-16'',''2026-12-08'')', false, true, '')))[1]::text <> '0' THEN
      'Se aplicó la migración 001 original (franjas propias en festivos): ver README, sección Reparación (A → 03 → 04 → 05 → B → 06).'
    WHEN (xpath('/row/c/text()', query_to_xml('SELECT max(fecha) AS c FROM franjas', false, true, '')))[1]::text = '2026-12-31'
         AND NOT hay_reservar_franja THEN
      'Datos completos del profesor: ejecutar 04, 05 y 06.'
    WHEN hay_reservar_franja AND NOT hay_dos_semanas THEN
      'Falta solo la 05: ejecutar 05 y 06.'
    WHEN hay_dos_semanas THEN
      'Base al día: ejecutar 06 para confirmar.'
    ELSE 'Estado no reconocido: enviar este resultado al equipo antes de ejecutar nada.'
  END AS que_hacer
FROM e;
