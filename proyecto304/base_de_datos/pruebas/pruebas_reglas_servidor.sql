-- =====================================================================
-- Pruebas de las reglas de servidor (DoD v2 criterios 18, 19 y 20)
-- Ejecutar en Supabase → SQL Editor DESPUÉS de 04.
-- Todo corre dentro de una transacción que se deshace al final:
-- no deja reservas de prueba en la base.
-- Resultado esperado: una línea «OK» por caso y ningún «FALLA».
-- =====================================================================
BEGIN;

CREATE TEMP TABLE resultado (caso TEXT, estado TEXT, detalle TEXT) ON COMMIT DROP;
GRANT ALL ON resultado TO authenticated, anon;

-- Franjas de prueba: siempre en el futuro y antes de la hora tope.
CREATE TEMP TABLE f ON COMMIT DROP AS
SELECT
  (SELECT fr.id FROM franjas fr JOIN recursos rc ON rc.id = fr.recurso_id
    WHERE fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date AND fr.hora_inicio < rc.hora_tope
      AND NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
      AND NOT EXISTS (SELECT 1 FROM reservas p WHERE p.recurso_id = fr.recurso_id AND p.estado = 'activa'   -- CC-17: equipo sin devolver
                       AND p.devuelta_en IS NULL AND p.fecha >= DATE '2026-11-17' AND fn_ahora_bogota() > fn_limite_devolucion(p))
    ORDER BY fr.fecha, fr.hora_inicio LIMIT 1) AS libre,
  (SELECT fr.id FROM franjas fr WHERE fr.fecha < (now() AT TIME ZONE 'America/Bogota')::date
    ORDER BY fr.fecha DESC LIMIT 1) AS pasada,
  (SELECT fr.id FROM franjas fr JOIN recursos rc ON rc.id = fr.recurso_id
    WHERE fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date AND fr.hora_inicio >= rc.hora_tope
    LIMIT 1) AS tras_tope,
  -- CC-17: franja libre de un equipo con un préstamo vencido sin devolver (NULL si no hay ninguno)
  (SELECT fr.id FROM franjas fr JOIN recursos rc ON rc.id = fr.recurso_id
    WHERE fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date AND fr.hora_inicio < rc.hora_tope
      AND NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
      AND EXISTS (SELECT 1 FROM reservas p WHERE p.recurso_id = fr.recurso_id AND p.estado = 'activa'
                    AND p.devuelta_en IS NULL AND p.fecha >= DATE '2026-11-17' AND fn_ahora_bogota() > fn_limite_devolucion(p))
    ORDER BY fr.fecha, fr.hora_inicio LIMIT 1) AS equipo_sin_devolver;
GRANT SELECT ON f TO authenticated, anon;

SET LOCAL ROLE authenticated;

-- Caso 1: reserva válida
SET LOCAL request.jwt.claims = '{"email":"vrios1@uan.edu.co"}';
DO $$ BEGIN
  PERFORM * FROM reservar_franja((SELECT libre FROM f));
  INSERT INTO resultado VALUES ('1 reserva válida', 'OK', 'se creó con hora_tope');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('1 reserva válida', 'FALLA', SQLERRM); END $$;

-- Caso 2: doble reserva de la misma franja (criterio 20)
SET LOCAL request.jwt.claims = '{"email":"spena2@uan.edu.co"}';
DO $$ BEGIN
  PERFORM * FROM reservar_franja((SELECT libre FROM f));
  INSERT INTO resultado VALUES ('2 doble reserva', 'FALLA', 'permitió la segunda reserva');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('2 doble reserva', 'OK', SQLERRM); END $$;

-- Caso 3: franja en el pasado (criterio 19)
DO $$ BEGIN
  PERFORM * FROM reservar_franja((SELECT pasada FROM f));
  INSERT INTO resultado VALUES ('3 fecha pasada', 'FALLA', 'permitió reservar en el pasado');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('3 fecha pasada', 'OK', SQLERRM); END $$;

-- Caso 4: franja que empieza después de la hora tope (regla propia)
DO $$ BEGIN
  PERFORM * FROM reservar_franja((SELECT tras_tope FROM f));
  INSERT INTO resultado VALUES ('4 después de hora tope', 'FALLA', 'permitió la franja');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('4 después de hora tope', 'OK', SQLERRM); END $$;

-- Caso 5: inserción directa desde el navegador (criterio 18)
DO $$ BEGIN
  INSERT INTO reservas (franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
  VALUES ((SELECT libre FROM f), 1, 2, current_date, '14:00', '16:00', 'activa', now(), now());
  INSERT INTO resultado VALUES ('5 insert directo', 'FALLA', 'RLS no bloqueó la escritura');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('5 insert directo', 'OK', SQLERRM); END $$;

-- Caso 6: equipo con un préstamo vencido sin devolver (CC-17)
DO $$ BEGIN
  IF (SELECT equipo_sin_devolver FROM f) IS NULL THEN
    INSERT INTO resultado VALUES ('6 equipo sin devolver', 'OK', 'hoy no hay equipos sin devolver');
  ELSE
    PERFORM * FROM reservar_franja((SELECT equipo_sin_devolver FROM f));
    INSERT INTO resultado VALUES ('6 equipo sin devolver', 'FALLA', 'permitió reservar un equipo que no se ha devuelto');
  END IF;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO resultado VALUES ('6 equipo sin devolver', CASE WHEN SQLERRM LIKE 'Este equipo no está disponible%' THEN 'OK' ELSE 'FALLA' END, SQLERRM);
END $$;

RESET ROLE;
SELECT * FROM resultado ORDER BY caso;

ROLLBACK;
