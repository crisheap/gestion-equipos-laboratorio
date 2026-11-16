-- =====================================================================
-- Pruebas de HU-05, HU-06 y CR-01 (reserva de dos semanas)
-- Ejecutar en Supabase → SQL Editor DESPUÉS de 05.
-- Todo corre en una transacción que se deshace al final: no deja datos.
-- Resultado esperado: una fila «OK» por caso y ningún «FALLA».
-- =====================================================================
BEGIN;

CREATE TEMP TABLE resultado (caso TEXT, estado TEXT, detalle TEXT) ON COMMIT DROP;
GRANT ALL ON resultado TO authenticated, anon;

-- Franjas de prueba (futuras, antes de la hora tope del equipo)
CREATE TEMP TABLE f ON COMMIT DROP AS
WITH libres AS (
  SELECT fr.*, rc.hora_tope AS tope
    FROM franjas fr JOIN recursos rc ON rc.id = fr.recurso_id
   WHERE rc.activo = 1
     AND fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date + 1
     AND fr.hora_inicio < rc.hora_tope
     AND NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa'))
SELECT
  -- 1: primera y segunda semana libres
  (SELECT a.id FROM libres a JOIN libres b ON b.recurso_id = a.recurso_id AND b.fecha = a.fecha + 7
     AND b.hora_inicio = a.hora_inicio ORDER BY a.fecha, a.id LIMIT 1) AS par_libre,
  -- 2: primera libre y segunda ocupada
  (SELECT a.id FROM libres a JOIN franjas b ON b.recurso_id = a.recurso_id AND b.fecha = a.fecha + 7
     AND b.hora_inicio = a.hora_inicio
    WHERE EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = b.id AND r.estado = 'activa')
    ORDER BY a.fecha, a.id LIMIT 1) AS segunda_ocupada,
  -- 3: primera libre y la segunda no existe (festivo o fuera del calendario)
  (SELECT a.id FROM libres a
    WHERE NOT EXISTS (SELECT 1 FROM franjas b WHERE b.recurso_id = a.recurso_id AND b.fecha = a.fecha + 7
                        AND b.hora_inicio = a.hora_inicio)
    ORDER BY a.fecha, a.id LIMIT 1) AS sin_segunda,
  -- 4: primera ocupada
  (SELECT fr.id FROM franjas fr
    WHERE fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date
      AND EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
    ORDER BY fr.fecha LIMIT 1) AS primera_ocupada,
  -- franjas auxiliares sin reserva activa para casos de devolución
  (SELECT fr.id FROM franjas fr
    WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
    ORDER BY fr.id LIMIT 1 OFFSET 0) AS aux1,
  (SELECT fr.id FROM franjas fr
    WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
    ORDER BY fr.id LIMIT 1 OFFSET 1) AS aux2,
  (SELECT fr.id FROM franjas fr
    WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa')
    ORDER BY fr.id LIMIT 1 OFFSET 2) AS aux3;
GRANT SELECT ON f TO authenticated, anon;

-- Préstamos preparados como administrador (fechas controladas):
--   900001: venció hace 1 h y tiene segunda semana 900002 dentro de 5 días.
--   900003: empezó hace 1 h y su hora tope es en 2 h (devolución a tiempo).
--   900004: venció hace 3 h, sin segunda semana (devolución tarde).
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
SELECT 900001, aux1, 1, 1, (now() AT TIME ZONE 'America/Bogota')::date - 1, '07:00', '09:00', 'activa',
       now(), (now() AT TIME ZONE 'America/Bogota') - interval '1 hour' FROM f;
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope, reserva_origen_id)
SELECT 900002, aux2, 1, 1, (now() AT TIME ZONE 'America/Bogota')::date + 5, '07:00', '09:00', 'activa',
       now(), (now() AT TIME ZONE 'America/Bogota')::date + 5 + time '18:00', 900001 FROM f;
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
SELECT 900003, aux3, 1, 1, (now() AT TIME ZONE 'America/Bogota')::date,
       ((now() AT TIME ZONE 'America/Bogota') - interval '1 hour')::time,
       ((now() AT TIME ZONE 'America/Bogota') - interval '1 hour')::time, 'activa',
       now(), (now() AT TIME ZONE 'America/Bogota') + interval '2 hours' FROM f;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"email":"vrios1@uan.edu.co"}';

-- Caso 1: dos semanas libres → se crean las dos, vinculadas
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT par_libre FROM f));
  IF (j->>'segunda_id') IS NOT NULL
     AND (SELECT reserva_origen_id FROM reservas WHERE id = (j->>'segunda_id')::int) = (j->>'primera_id')::int
  THEN INSERT INTO resultado VALUES ('1 dos semanas libres', 'OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('1 dos semanas libres', 'FALLA', j::text); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('1 dos semanas libres', 'FALLA', SQLERRM); END $$;

-- Caso 2: segunda semana ocupada → solo la primera (R1)
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT segunda_ocupada FROM f));
  IF (j->>'primera_id') IS NOT NULL AND (j->>'segunda_id') IS NULL
  THEN INSERT INTO resultado VALUES ('2 segunda semana ocupada', 'OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('2 segunda semana ocupada', 'FALLA', j::text); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('2 segunda semana ocupada', 'FALLA', SQLERRM); END $$;

-- Caso 3: la segunda semana no tiene franja (festivo / fin de calendario) → solo la primera
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT sin_segunda FROM f));
  IF (j->>'primera_id') IS NOT NULL AND (j->>'segunda_id') IS NULL
  THEN INSERT INTO resultado VALUES ('3 segunda semana sin franja', 'OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('3 segunda semana sin franja', 'FALLA', j::text); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('3 segunda semana sin franja', 'FALLA', SQLERRM); END $$;

-- Caso 4: primera semana ocupada → no se crea nada
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT primera_ocupada FROM f));
  INSERT INTO resultado VALUES ('4 primera semana ocupada', 'FALLA', 'creó la reserva');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('4 primera semana ocupada', 'OK', SQLERRM); END $$;

-- Caso 5: devolución a tiempo (HU-05 y HU-06)
DO $$ DECLARE v VARCHAR; BEGIN
  SELECT resultado INTO v FROM registrar_devolucion(900003);
  IF v = 'a_tiempo' THEN INSERT INTO resultado VALUES ('5 devolución a tiempo', 'OK', 'clasificada a_tiempo');
  ELSE INSERT INTO resultado VALUES ('5 devolución a tiempo', 'FALLA', coalesce(v, 'null')); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('5 devolución a tiempo', 'FALLA', SQLERRM); END $$;

-- Caso 6: devolución tarde → fuera_de_tiempo y la segunda semana se anula (R2, disparador)
DO $$ DECLARE v VARCHAR; e TEXT; BEGIN
  SELECT resultado INTO v FROM registrar_devolucion(900001);
  SELECT estado INTO e FROM reservas WHERE id = 900002;
  IF v = 'fuera_de_tiempo' AND e = 'anulada'
  THEN INSERT INTO resultado VALUES ('6 devolución tarde anula 2.ª semana', 'OK', (SELECT motivo_anulacion FROM reservas WHERE id = 900002));
  ELSE INSERT INTO resultado VALUES ('6 devolución tarde anula 2.ª semana', 'FALLA', v || ' / ' || e); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('6 devolución tarde anula 2.ª semana', 'FALLA', SQLERRM); END $$;

-- Caso 7: la franja anulada queda libre para otra persona
SET LOCAL request.jwt.claims = '{"email":"spena2@uan.edu.co"}';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM reservas WHERE franja_id = (SELECT aux2 FROM f) AND estado = 'activa')
  THEN INSERT INTO resultado VALUES ('7 franja anulada queda libre', 'OK', 'sin reserva activa');
  ELSE INSERT INTO resultado VALUES ('7 franja anulada queda libre', 'FALLA', 'sigue ocupada'); END IF;
END $$;

-- Caso 8: no se registra dos veces la misma devolución
DO $$ BEGIN
  PERFORM * FROM registrar_devolucion(900003);
  INSERT INTO resultado VALUES ('8 devolución repetida', 'FALLA', 'la aceptó');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('8 devolución repetida', 'OK', SQLERRM); END $$;

-- Caso 9: sin sesión no se puede reservar dos semanas
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
  PERFORM crear_reserva_dos_semanas((SELECT par_libre FROM f));
  INSERT INTO resultado VALUES ('9 sin sesión', 'FALLA', 'permitió reservar');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('9 sin sesión', 'OK', SQLERRM); END $$;

RESET ROLE;
SELECT * FROM resultado ORDER BY caso;

ROLLBACK;
