-- =====================================================================
-- Reparación · Paso A (solo si 00_diagnostico.sql lo indica)
-- Caso: se aplicó la migración 001 ORIGINAL, que generó franjas propias
-- del 5 oct al 11 dic (con ids desde 1801, incluidos festivos). Esas
-- franjas chocan con el complemento oficial del profesor (ids 1801–7110).
--
-- Qué hace:
--   1. Guarda en respaldo_reservas_equipo las reservas creadas desde la
--      aplicación (id > 216) con el equipo, la fecha y la hora de su franja.
--   2. Borra esas reservas y las franjas generadas (id > 1800).
--   3. Permite temporalmente hora_tope vacía para que entre el complemento
--      (04 la vuelve a llenar y a exigir).
-- Las 1.800 franjas y 216 reservas del profesor no se tocan.
--
-- Orden completo: A → 03 → 04 → 05 → B → 06.
-- =====================================================================
BEGIN;

DROP TABLE IF EXISTS respaldo_reservas_equipo;
CREATE TABLE respaldo_reservas_equipo AS
SELECT r.*, f.recurso_id AS f_recurso_id, f.fecha AS f_fecha, f.hora_inicio AS f_hora_inicio
  FROM reservas r JOIN franjas f ON f.id = r.franja_id
 WHERE r.id > 216;

DELETE FROM reservas WHERE id > 216;
DELETE FROM franjas  WHERE id > 1800;

ALTER TABLE reservas ALTER COLUMN hora_tope DROP NOT NULL;

SELECT (SELECT count(*) FROM respaldo_reservas_equipo) AS reservas_respaldadas,
       (SELECT count(*) FROM franjas)                  AS franjas_que_quedan,
       (SELECT count(*) FROM reservas)                 AS reservas_que_quedan;

COMMIT;
