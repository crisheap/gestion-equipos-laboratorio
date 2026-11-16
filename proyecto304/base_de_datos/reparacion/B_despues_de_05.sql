-- =====================================================================
-- Reparación · Paso B (después de A → 03 → 04 → 05)
-- Devuelve las reservas hechas desde la aplicación, cada una a la franja
-- oficial del profesor con el mismo equipo, fecha y hora. Si esa franja
-- ya tiene una reserva activa del profesor, la de la aplicación queda
-- fuera y se lista para avisar a la persona.
-- =====================================================================
BEGIN;

CREATE TEMP TABLE no_reubicadas ON COMMIT DROP AS
SELECT b.id AS reserva_original, b.usuario_id, b.f_recurso_id, b.f_fecha, b.f_hora_inicio, b.estado,
       CASE WHEN f.id IS NULL THEN 'La fecha ya no tiene franja (festivo)'
            ELSE 'La franja ya tiene una reserva activa del profesor' END AS motivo
  FROM respaldo_reservas_equipo b
  LEFT JOIN franjas f ON f.recurso_id = b.f_recurso_id AND f.fecha = b.f_fecha AND f.hora_inicio = b.f_hora_inicio
 WHERE f.id IS NULL
    OR (b.estado = 'activa' AND EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = f.id AND r.estado = 'activa'));

INSERT INTO reservas (franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
SELECT f.id, b.recurso_id, b.usuario_id, b.fecha, b.hora_inicio, b.hora_fin, b.estado, b.creada_en,
       coalesce(b.hora_tope, b.fecha + rc.hora_tope)
  FROM respaldo_reservas_equipo b
  JOIN franjas f   ON f.recurso_id = b.f_recurso_id AND f.fecha = b.f_fecha AND f.hora_inicio = b.f_hora_inicio
  JOIN recursos rc ON rc.id = b.recurso_id
 WHERE b.id NOT IN (SELECT reserva_original FROM no_reubicadas);

SELECT (SELECT count(*) FROM respaldo_reservas_equipo) - (SELECT count(*) FROM no_reubicadas) AS reubicadas,
       (SELECT count(*) FROM no_reubicadas) AS no_reubicadas;
SELECT * FROM no_reubicadas;

DROP TABLE respaldo_reservas_equipo;
COMMIT;
