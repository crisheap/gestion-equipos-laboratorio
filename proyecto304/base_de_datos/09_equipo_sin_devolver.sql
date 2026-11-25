-- =====================================================================
-- 09 · Un equipo sin devolver no se puede volver a reservar
-- Error 404 · Gestión de equipos de laboratorio · UAN 2026-II
--
-- Pedido del PO (24 nov, CC-17): cada equipo es una sola unidad. Si tiene
-- un préstamo vencido (pasó la hora tope) y no se ha registrado la
-- devolución, nadie puede hacer reservas nuevas de ese equipo hasta que
-- se devuelva.
--
-- Decisiones del PO:
--   * Solo cuentan los préstamos desde el 17 nov 2026 (arranque del
--     sistema). Los préstamos anteriores de los datos del profesor quedan
--     como historial: no se modifica ningún dato.
--   * Las reservas futuras que ya existían se mantienen; solo se bloquean
--     las reservas nuevas.
--
-- Solo cambia reservar_franja(). crear_reserva_dos_semanas() la llama
-- primero, así que queda cubierta. Se puede ejecutar más de una vez.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reservar_franja(p_franja_id integer)
 RETURNS TABLE(reserva_id integer, fecha date, hora_inicio time without time zone, hora_fin time without time zone, hora_tope timestamp without time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_correo   TEXT := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_usuario  INTEGER;
  v_franja   franjas%ROWTYPE;
  v_activo   SMALLINT;
  v_tope     TIME;
  v_id       INTEGER;
  v_pend_id  INTEGER;
  v_pend_fec DATE;
BEGIN
  IF v_correo = '' THEN
    RAISE EXCEPTION 'Debes iniciar sesión para apartar un equipo.' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.id INTO v_usuario FROM usuarios u WHERE lower(u.correo) = v_correo;
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Tu correo no está registrado como usuario del laboratorio.' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_franja FROM franjas f WHERE f.id = p_franja_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La franja seleccionada no existe.' USING ERRCODE = 'P0001';
  END IF;

  SELECT rc.activo, rc.hora_tope INTO v_activo, v_tope FROM recursos rc WHERE rc.id = v_franja.recurso_id;
  IF v_activo <> 1 THEN
    RAISE EXCEPTION 'El equipo está en mantenimiento y no se puede apartar.' USING ERRCODE = 'P0001';
  END IF;

  -- Regla propia: una franja que empieza en la hora tope del equipo o después
  -- no se puede devolver a tiempo (ej. multímetro con tope 18:00, franja 18:00-20:00).
  IF v_franja.hora_inicio >= v_tope THEN
    RAISE EXCEPTION 'Esta franja empieza después de la hora tope del equipo (%). Elige una franja anterior.',
      to_char(v_tope, 'HH24:MI') USING ERRCODE = 'P0001';
  END IF;

  -- DoD 19: no se reserva en el pasado (hora de Bogotá).
  IF (v_franja.fecha + v_franja.hora_inicio) <= (now() AT TIME ZONE 'America/Bogota') THEN
    RAISE EXCEPTION 'No se puede reservar una franja que ya pasó.' USING ERRCODE = 'P0001';
  END IF;

  -- DoD 20: franja ocupada. El índice único cubre el caso de dos solicitudes simultáneas.
  IF EXISTS (SELECT 1 FROM reservas r WHERE r.franja_id = p_franja_id AND r.estado = 'activa') THEN
    RAISE EXCEPTION 'Franja no disponible: otra persona ya la reservó.' USING ERRCODE = 'P0001';
  END IF;

  -- CC-17: el equipo es una sola unidad. Si un préstamo (desde el 17 nov) ya
  -- pasó su hora tope sin devolución registrada, el equipo sigue afuera.
  SELECT r.id, r.fecha INTO v_pend_id, v_pend_fec
    FROM reservas r
   WHERE r.recurso_id = v_franja.recurso_id
     AND r.estado = 'activa'
     AND r.devuelta_en IS NULL
     AND r.fecha >= DATE '2026-11-17'
     AND fn_ahora_bogota() > fn_limite_devolucion(r)
   ORDER BY r.fecha, r.hora_inicio
   LIMIT 1;
  IF v_pend_id IS NOT NULL THEN
    RAISE EXCEPTION 'Este equipo no está disponible: no se ha devuelto el préstamo #% del %. Se podrá reservar cuando se registre la devolución.',
      v_pend_id, to_char(v_pend_fec, 'DD/MM/YYYY') USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    INSERT INTO reservas (franja_id, recurso_id, usuario_id, fecha, hora_inicio, hora_fin, estado, creada_en, hora_tope)
    VALUES (v_franja.id, v_franja.recurso_id, v_usuario, v_franja.fecha, v_franja.hora_inicio,
            v_franja.hora_fin, 'activa', now() AT TIME ZONE 'America/Bogota', v_franja.fecha + v_tope)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Franja no disponible: otra persona ya la reservó.' USING ERRCODE = 'P0001';
  END;

  RETURN QUERY SELECT v_id, v_franja.fecha, v_franja.hora_inicio, v_franja.hora_fin, v_franja.fecha + v_tope;
END;
$function$;
