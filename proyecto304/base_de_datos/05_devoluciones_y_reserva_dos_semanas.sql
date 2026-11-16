-- =====================================================================
-- 05 · Devoluciones (HU-05), hora tope (HU-06) y reserva de dos semanas
--      (CR-01: HU-06 CA07.1 y CA07.2) · Sprint 3 · SCRUM-55
--
-- Reglas del CR-01:
--   R1. Reserva de dos semanas: si la franja de la segunda semana está
--       ocupada o no existe, solo se reserva la primera y se informa.
--   R2. Si el equipo de la primera semana no se devuelve antes de su
--       hora tope (o se devuelve tarde), la segunda semana se anula sola
--       y su franja queda libre.
--
-- Qué hace:
--   1. Columnas nuevas en reservas: devuelta_en, resultado_devolucion,
--      reserva_origen_id y motivo_anulacion.
--   2. registrar_devolucion(): guarda la hora real (Bogotá) y clasifica
--      la devolución como a_tiempo o fuera_de_tiempo (CA06 y CA07).
--   3. crear_reserva_dos_semanas(): reutiliza reservar_franja() (todas las
--      validaciones de HU-04) y aplica R1.
--   4. anular_reservas_por_incumplimiento() + disparador + pg_cron: R2.
--   5. Vista v_prestamos con el estado calculado (vencida, a tiempo...).
--
-- Requisitos: ejecutar después de 04. No borra datos y se puede repetir.
-- La reserva de una semana (HU-04, reservar_franja) no cambia.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Columnas nuevas
-- ---------------------------------------------------------------------
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS devuelta_en          TIMESTAMP;
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS resultado_devolucion VARCHAR(20);
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS reserva_origen_id    INTEGER REFERENCES reservas(id);
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS motivo_anulacion     VARCHAR(250);

ALTER TABLE reservas DROP CONSTRAINT IF EXISTS reservas_resultado_valido;
ALTER TABLE reservas ADD CONSTRAINT reservas_resultado_valido
  CHECK (resultado_devolucion IS NULL OR resultado_devolucion IN ('a_tiempo', 'fuera_de_tiempo'));

CREATE INDEX IF NOT EXISTS idx_reservas_origen ON reservas (reserva_origen_id);

-- ---------------------------------------------------------------------
-- 2. Funciones de apoyo
-- ---------------------------------------------------------------------
-- Hora actual en Bogotá (Supabase trabaja en UTC).
CREATE OR REPLACE FUNCTION public.fn_ahora_bogota()
RETURNS TIMESTAMP LANGUAGE sql STABLE
AS $$ SELECT (now() AT TIME ZONE 'America/Bogota')::timestamp; $$;

-- Límite de devolución de un préstamo: su hora tope guardada (04).
-- Si la franja termina después de la hora tope (solo pasa en datos
-- antiguos), el límite es el fin de la franja.
CREATE OR REPLACE FUNCTION public.fn_limite_devolucion(r reservas)
RETURNS TIMESTAMP LANGUAGE sql STABLE
AS $$ SELECT GREATEST(r.hora_tope, r.fecha + r.hora_fin); $$;

-- ---------------------------------------------------------------------
-- 3. R2 · Anular la segunda semana por incumplir la hora tope
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.anular_reservas_por_incumplimiento()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ahora TIMESTAMP := fn_ahora_bogota();
  v_n     INTEGER;
BEGIN
  UPDATE reservas r2
     SET estado = 'anulada',
         motivo_anulacion = format(
           'Anulada automáticamente: el equipo de la reserva #%s del %s no se devolvió antes de las %s.',
           r1.id, to_char(r1.fecha, 'DD/MM/YYYY'), to_char(fn_limite_devolucion(r1), 'HH24:MI'))
    FROM reservas r1
   WHERE r2.reserva_origen_id = r1.id
     AND r2.estado = 'activa'
     AND r2.fecha + r2.hora_inicio > v_ahora
     AND (
           (r1.estado = 'activa' AND r1.devuelta_en IS NULL AND v_ahora > fn_limite_devolucion(r1))
        OR (r1.devuelta_en IS NOT NULL AND r1.devuelta_en > fn_limite_devolucion(r1))
         );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- R2 en el momento de una devolución tardía.
CREATE OR REPLACE FUNCTION public.trg_anular_por_devolucion_tardia()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.devuelta_en IS NOT NULL AND NEW.devuelta_en > fn_limite_devolucion(NEW) THEN
    PERFORM anular_reservas_por_incumplimiento();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_anular_por_devolucion_tardia ON reservas;
CREATE TRIGGER tg_anular_por_devolucion_tardia
  AFTER UPDATE OF devuelta_en ON reservas
  FOR EACH ROW EXECUTE FUNCTION trg_anular_por_devolucion_tardia();

-- ---------------------------------------------------------------------
-- 4. HU-05 · Registrar la devolución (con la clasificación de HU-06)
-- ---------------------------------------------------------------------
-- Cualquier usuario registrado que haya iniciado sesión puede registrar
-- la devolución (un solo rol, R-03). Solo préstamos activos cuya franja
-- ya empezó.
CREATE OR REPLACE FUNCTION public.registrar_devolucion(p_reserva_id INTEGER)
RETURNS TABLE (reserva_id INTEGER, devuelta_en TIMESTAMP, limite TIMESTAMP, resultado VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_correo TEXT := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_r      reservas%ROWTYPE;
  v_ahora  TIMESTAMP := fn_ahora_bogota();
  v_res    VARCHAR(20);
BEGIN
  IF v_correo = '' OR NOT EXISTS (SELECT 1 FROM usuarios u WHERE lower(u.correo) = v_correo) THEN
    RAISE EXCEPTION 'Debes iniciar sesión con un correo registrado para registrar devoluciones.' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_r FROM reservas r WHERE r.id = p_reserva_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El préstamo % no existe.', p_reserva_id USING ERRCODE = 'P0001';
  END IF;
  IF v_r.estado <> 'activa' OR v_r.devuelta_en IS NOT NULL THEN
    RAISE EXCEPTION 'El préstamo % no está pendiente de devolución (estado: %).', p_reserva_id, v_r.estado USING ERRCODE = 'P0001';
  END IF;
  IF v_r.fecha + v_r.hora_inicio > v_ahora THEN
    RAISE EXCEPTION 'La franja del préstamo % todavía no empieza; no se puede registrar la devolución.', p_reserva_id USING ERRCODE = 'P0001';
  END IF;

  v_res := CASE WHEN v_ahora <= fn_limite_devolucion(v_r) THEN 'a_tiempo' ELSE 'fuera_de_tiempo' END;

  UPDATE reservas r
     SET devuelta_en = v_ahora, estado = 'completada', resultado_devolucion = v_res
   WHERE r.id = p_reserva_id;

  RETURN QUERY SELECT p_reserva_id, v_ahora, fn_limite_devolucion(v_r), v_res;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. R1 · Reserva de dos semanas
-- ---------------------------------------------------------------------
-- La primera semana pasa por reservar_franja(): usuario con sesión,
-- equipo activo, franja antes de la hora tope, no pasada y libre.
-- La segunda es la misma franja siete días después, si existe y está libre.
CREATE OR REPLACE FUNCTION public.crear_reserva_dos_semanas(p_franja_id INTEGER)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  f1        franjas%ROWTYPE;
  f2        franjas%ROWTYPE;
  v_id1     INTEGER;
  v_id2     INTEGER;
  v_usuario INTEGER;
  v_tope    TIME;
  v_mensaje TEXT;
BEGIN
  SELECT rf.reserva_id INTO v_id1 FROM reservar_franja(p_franja_id) rf;
  SELECT * INTO f1 FROM franjas f WHERE f.id = p_franja_id;
  SELECT r.usuario_id INTO v_usuario FROM reservas r WHERE r.id = v_id1;
  SELECT rc.hora_tope INTO v_tope FROM recursos rc WHERE rc.id = f1.recurso_id;

  SELECT * INTO f2 FROM franjas f
   WHERE f.recurso_id = f1.recurso_id AND f.fecha = f1.fecha + 7
     AND f.hora_inicio = f1.hora_inicio AND f.hora_fin = f1.hora_fin
   ORDER BY f.id LIMIT 1 FOR UPDATE;

  IF NOT FOUND THEN
    v_mensaje := format('Solo se reservó el %s: la franja del %s no está habilitada.',
                        to_char(f1.fecha, 'DD/MM/YYYY'), to_char(f1.fecha + 7, 'DD/MM/YYYY'));
  ELSIF EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = f2.id AND r.estado = 'activa') THEN
    v_mensaje := format('Solo se reservó el %s: la franja del %s ya está ocupada.',
                        to_char(f1.fecha, 'DD/MM/YYYY'), to_char(f2.fecha, 'DD/MM/YYYY'));
  ELSE
    BEGIN
      INSERT INTO reservas (franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin,
                            estado, creada_en, hora_tope, reserva_origen_id)
      VALUES (f2.id, f2.recurso_id, v_usuario, f2.fecha, f2.hora_inicio, f2.hora_fin,
              'activa', fn_ahora_bogota(), f2.fecha + v_tope, v_id1)
      RETURNING id INTO v_id2;
      v_mensaje := format('Reservas realizadas para el %s y el %s, de %s a %s. Si no devuelves el equipo antes de las %s del %s, la reserva del %s se anula automáticamente.',
                          to_char(f1.fecha, 'DD/MM/YYYY'), to_char(f2.fecha, 'DD/MM/YYYY'),
                          to_char(f1.hora_inicio, 'HH24:MI'), to_char(f1.hora_fin, 'HH24:MI'),
                          to_char(v_tope, 'HH24:MI'), to_char(f1.fecha, 'DD/MM/YYYY'),
                          to_char(f2.fecha, 'DD/MM/YYYY'));
    EXCEPTION WHEN unique_violation THEN
      v_mensaje := format('Solo se reservó el %s: la franja del %s acaba de ser ocupada.',
                          to_char(f1.fecha, 'DD/MM/YYYY'), to_char(f2.fecha, 'DD/MM/YYYY'));
    END;
  END IF;

  RETURN json_build_object('primera_id', v_id1, 'segunda_id', v_id2,
                           'fecha_primera', f1.fecha, 'fecha_segunda', f1.fecha + 7,
                           'mensaje', v_mensaje);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. Vista para HU-06 (vencidos) y HU-07 (consulta de préstamos)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_prestamos;
CREATE VIEW public.v_prestamos WITH (security_invoker = true) AS
SELECT r.id, r.recurso_id, rc.nombre AS equipo, r.usuario_id, u.nombre AS solicitante,
       r.fecha, r.hora_inicio, r.hora_fin, r.hora_tope, r.estado, r.devuelta_en,
       r.resultado_devolucion, r.reserva_origen_id, r.motivo_anulacion,
       CASE
         WHEN r.estado = 'activa' AND r.devuelta_en IS NULL
              AND fn_ahora_bogota() > fn_limite_devolucion(r) THEN 'vencida'
         ELSE r.estado
       END AS estado_calculado
  FROM reservas r
  JOIN recursos rc ON rc.id = r.recurso_id
  JOIN usuarios u  ON u.id  = r.usuario_id;

-- ---------------------------------------------------------------------
-- 7. Permisos
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.registrar_devolucion(INTEGER)        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crear_reserva_dos_semanas(INTEGER)   FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_devolucion(INTEGER)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.crear_reserva_dos_semanas(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anular_reservas_por_incumplimiento() TO anon, authenticated;
GRANT SELECT ON public.v_prestamos TO anon, authenticated;

COMMIT;

-- ---------------------------------------------------------------------
-- 8. R2 sin intervención: revisión automática cada 10 minutos (pg_cron)
--    Fuera de la transacción: si pg_cron no está disponible, la aplicación
--    llama a anular_reservas_por_incumplimiento() al cargar.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.schedule('anular-reservas-incumplidas', '*/10 * * * *',
                        'SELECT public.anular_reservas_por_incumplimiento();');
  RAISE NOTICE 'pg_cron programado cada 10 minutos.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible (%). La aplicación ejecutará la revisión al cargar.', SQLERRM;
END $$;
