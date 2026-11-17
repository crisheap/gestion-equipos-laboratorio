-- =====================================================================
-- Pruebas de integración con el usuario real cherrera31@uan.edu.co (id 41)
-- SCRUM-44 (HU-05), SCRUM-50 (HU-06) y SCRUM-59 (CR-01) · 17 nov 2026
-- Ejecutar en Supabase → SQL Editor después de 07. Todo se deshace al final:
-- el resultado llega como un error «RESULTADO (se deshace todo): …».
-- Resultado obtenido el 17 nov 2026: 9/9 OK.
-- =====================================================================
BEGIN;
CREATE TEMP TABLE resultado (caso TEXT, estado TEXT, detalle TEXT) ON COMMIT DROP;
GRANT ALL ON resultado TO authenticated, anon;
CREATE TEMP TABLE f ON COMMIT DROP AS
WITH libres AS (
  SELECT fr.* FROM franjas fr JOIN recursos rc ON rc.id = fr.recurso_id
   WHERE rc.activo = 1 AND fr.fecha > (now() AT TIME ZONE 'America/Bogota')::date + 1
     AND fr.hora_inicio < rc.hora_tope
     AND NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa'))
SELECT
  (SELECT a.id FROM libres a JOIN libres b ON b.recurso_id = a.recurso_id AND b.fecha = a.fecha + 7 AND b.hora_inicio = a.hora_inicio ORDER BY a.fecha, a.id LIMIT 1) AS par_libre,
  (SELECT a.id FROM libres a JOIN franjas b ON b.recurso_id = a.recurso_id AND b.fecha = a.fecha + 7 AND b.hora_inicio = a.hora_inicio
    WHERE EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = b.id AND r.estado = 'activa') ORDER BY a.fecha, a.id LIMIT 1) AS segunda_ocupada,
  (SELECT a.id FROM libres a WHERE a.fecha + 7 = DATE '2026-12-08' ORDER BY a.id LIMIT 1) AS antes_festivo,
  (SELECT fr.id FROM franjas fr WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa') ORDER BY fr.id LIMIT 1) AS aux1,
  (SELECT fr.id FROM franjas fr WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa') ORDER BY fr.id LIMIT 1 OFFSET 1) AS aux2,
  (SELECT fr.id FROM franjas fr WHERE NOT EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = fr.id AND r.estado = 'activa') ORDER BY fr.id LIMIT 1 OFFSET 2) AS aux3;
GRANT SELECT ON f TO authenticated, anon;

-- Préstamos de prueba del usuario 41 con fechas controladas:
--   900001 vencido hace 1 h con segunda semana 900002; 900003 en curso, tope en 2 h.
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
SELECT 900001, aux1, 1, 41, (now() AT TIME ZONE 'America/Bogota')::date - 1, '07:00', '09:00', 'activa', now(), (now() AT TIME ZONE 'America/Bogota') - interval '1 hour' FROM f;
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope, reserva_origen_id)
SELECT 900002, aux2, 1, 41, (now() AT TIME ZONE 'America/Bogota')::date + 5, '07:00', '09:00', 'activa', now(), (now() AT TIME ZONE 'America/Bogota')::date + 5 + time '18:00', 900001 FROM f;
INSERT INTO reservas (id, franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
SELECT 900003, aux3, 1, 41, (now() AT TIME ZONE 'America/Bogota')::date, ((now() AT TIME ZONE 'America/Bogota') - interval '1 hour')::time, ((now() AT TIME ZONE 'America/Bogota') - interval '1 hour')::time, 'activa', now(), (now() AT TIME ZONE 'America/Bogota') + interval '2 hours' FROM f;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"email":"cherrera31@uan.edu.co","role":"authenticated"}';

DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT par_libre FROM f));
  IF (j->>'segunda_id') IS NOT NULL THEN INSERT INTO resultado VALUES ('59.1 dos semanas libres','OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('59.1 dos semanas libres','FALLA', j::text); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('59.1 dos semanas libres','FALLA',SQLERRM); END $$;
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT segunda_ocupada FROM f));
  IF (j->>'segunda_id') IS NULL AND (j->>'primera_id') IS NOT NULL THEN INSERT INTO resultado VALUES ('59.2 segunda ocupada','OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('59.2 segunda ocupada','FALLA', j::text); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('59.2 segunda ocupada','FALLA',SQLERRM); END $$;
DO $$ DECLARE j JSON; BEGIN
  j := crear_reserva_dos_semanas((SELECT antes_festivo FROM f));
  IF (j->>'segunda_id') IS NULL AND (j->>'primera_id') IS NOT NULL THEN INSERT INTO resultado VALUES ('59.3 segunda en festivo 08/12','OK', j->>'mensaje');
  ELSE INSERT INTO resultado VALUES ('59.3 segunda en festivo 08/12','FALLA', coalesce(j::text,'sin franja de prueba')); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('59.3 segunda en festivo 08/12','FALLA',SQLERRM); END $$;
DO $$ DECLARE n INT; o INT; BEGIN
  SELECT count(*), count(*) FILTER (WHERE usuario_id <> 41) INTO n, o FROM v_prestamos;
  IF n >= 7 AND o = 0 THEN INSERT INTO resultado VALUES ('50.1 v_prestamos solo propios','OK', n || ' préstamos propios');
  ELSE INSERT INTO resultado VALUES ('50.1 v_prestamos solo propios','FALLA', n || ' filas, ' || o || ' ajenas'); END IF;
END $$;
DO $$ DECLARE e TEXT; BEGIN
  SELECT estado_calculado INTO e FROM v_prestamos WHERE id = 900001;
  IF e = 'vencida' THEN INSERT INTO resultado VALUES ('50.2 préstamo vencido','OK','estado_calculado = vencida');
  ELSE INSERT INTO resultado VALUES ('50.2 préstamo vencido','FALLA', coalesce(e,'null')); END IF;
END $$;
DO $$ DECLARE v VARCHAR; BEGIN
  SELECT resultado INTO v FROM registrar_devolucion(900003);
  IF v = 'a_tiempo' THEN INSERT INTO resultado VALUES ('44.1 devolución a tiempo','OK','a_tiempo');
  ELSE INSERT INTO resultado VALUES ('44.1 devolución a tiempo','FALLA', coalesce(v,'null')); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('44.1 devolución a tiempo','FALLA',SQLERRM); END $$;
DO $$ DECLARE v VARCHAR; e TEXT; BEGIN
  SELECT resultado INTO v FROM registrar_devolucion(900001);
  SELECT estado INTO e FROM reservas WHERE id = 900002;
  IF v = 'fuera_de_tiempo' AND e = 'anulada' THEN INSERT INTO resultado VALUES ('44.2 tarde anula 2.ª semana','OK', e);
  ELSE INSERT INTO resultado VALUES ('44.2 tarde anula 2.ª semana','FALLA', v || ' / ' || e); END IF;
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('44.2 tarde anula 2.ª semana','FALLA',SQLERRM); END $$;
DO $$ BEGIN
  PERFORM * FROM registrar_devolucion(900003);
  INSERT INTO resultado VALUES ('44.3 devolución repetida','FALLA','la aceptó');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('44.3 devolución repetida','OK',SQLERRM); END $$;
DO $$ BEGIN
  PERFORM anular_reservas_por_incumplimiento();
  INSERT INTO resultado VALUES ('S.1 anulación no expuesta a usuarios','FALLA','se pudo llamar');
EXCEPTION WHEN OTHERS THEN INSERT INTO resultado VALUES ('S.1 anulación no expuesta a usuarios','OK',SQLERRM); END $$;
RESET ROLE;
DO $$ BEGIN RAISE EXCEPTION 'RESULTADO (se deshace todo): %', (SELECT string_agg(caso || ' = ' || estado || CASE WHEN estado='FALLA' THEN ' [' || detalle || ']' ELSE '' END, ' | ' ORDER BY caso) FROM resultado); END $$;
