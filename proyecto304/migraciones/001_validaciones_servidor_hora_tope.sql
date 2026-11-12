-- =====================================================================
-- Migración 001 · Deuda del Sprint 2 (SCRUM-13 HU-04, SCRUM-12 HU-03)
-- Tarea Jira: ver «DT-01» en el Sprint 3.
--
-- Qué corrige (DoD v2, criterios 18, 19 y 20 · CA04):
--   1. La hora tope del equipo pasa a una columna (recursos.hora_tope)
--      y queda guardada en cada préstamo (reservas.hora_tope).
--   2. Doble reserva: índice único que impide dos reservas activas
--      sobre la misma franja, aunque lleguen al mismo tiempo.
--   3. Fecha pasada, franja ocupada y usuario: se validan en el servidor,
--      dentro de la función reservar_franja(). El navegador ya no inserta
--      directamente en la tabla reservas.
--   4. RLS: lectura pública del catálogo y la disponibilidad; nadie puede
--      escribir en las tablas desde el navegador.
--   5. Franjas horarias desde el 5 de octubre hasta el 11 de diciembre de
--      2026 (los datos semilla terminaban el 2 de octubre y no se podía
--      reservar ni demostrar nada en el Sprint 3).
--
-- Cómo aplicarla: Supabase → SQL Editor → pegar y ejecutar UNA vez,
-- después de supabase_setup_profesor.sql. No borra datos.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Hora tope por equipo y por préstamo
-- ---------------------------------------------------------------------
ALTER TABLE recursos ADD COLUMN IF NOT EXISTS hora_tope TIME;

UPDATE recursos
SET hora_tope = substring(atributos FROM 'hora tope (\d{2}:\d{2})')::time
WHERE hora_tope IS NULL;

-- Si algún equipo no trae hora tope en sus atributos, se usa la más estricta.
UPDATE recursos SET hora_tope = '18:00' WHERE hora_tope IS NULL;
ALTER TABLE recursos ALTER COLUMN hora_tope SET NOT NULL;

ALTER TABLE reservas ADD COLUMN IF NOT EXISTS hora_tope TIMESTAMP;

UPDATE reservas r
SET hora_tope = r.fecha + rc.hora_tope
FROM recursos rc
WHERE rc.id = r.recurso_id AND r.hora_tope IS NULL;

ALTER TABLE reservas ALTER COLUMN hora_tope SET NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Identificadores automáticos (el esquema entregado no los tenía)
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS reservas_id_seq OWNED BY reservas.id;
SELECT setval('reservas_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM reservas), 1));
ALTER TABLE reservas ALTER COLUMN id SET DEFAULT nextval('reservas_id_seq');

CREATE SEQUENCE IF NOT EXISTS franjas_id_seq OWNED BY franjas.id;
SELECT setval('franjas_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM franjas), 1));
ALTER TABLE franjas ALTER COLUMN id SET DEFAULT nextval('franjas_id_seq');

-- ---------------------------------------------------------------------
-- 3. Restricciones de integridad
-- ---------------------------------------------------------------------
ALTER TABLE reservas DROP CONSTRAINT IF EXISTS reservas_estado_valido;
ALTER TABLE reservas ADD CONSTRAINT reservas_estado_valido
  CHECK (estado IN ('activa', 'completada', 'cancelada', 'vencida', 'anulada'));

-- Una franja no puede tener dos reservas activas (doble reserva / concurrencia).
CREATE UNIQUE INDEX IF NOT EXISTS ux_reservas_franja_activa
  ON reservas (franja_id) WHERE estado = 'activa';

-- Una franja no se repite para el mismo equipo, fecha y hora.
CREATE UNIQUE INDEX IF NOT EXISTS ux_franjas_recurso_fecha_hora
  ON franjas (recurso_id, fecha, hora_inicio);

-- ---------------------------------------------------------------------
-- 4. Franjas del 5 de octubre al 11 de diciembre de 2026 (días hábiles)
--    Mismo patrón que los datos entregados: 6 franjas de 2 horas por equipo.
-- ---------------------------------------------------------------------
INSERT INTO franjas (recurso_id, fecha, hora_inicio, hora_fin)
SELECT rc.id, d::date, h.ini, h.fin
FROM recursos rc
CROSS JOIN generate_series('2026-10-05'::date, '2026-12-11'::date, '1 day') AS d
CROSS JOIN (VALUES ('07:00'::time, '09:00'::time), ('09:00', '11:00'), ('11:00', '13:00'),
                   ('14:00', '16:00'), ('16:00', '18:00'), ('18:00', '20:00')) AS h(ini, fin)
WHERE EXTRACT(ISODOW FROM d) < 6
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 5. Función del servidor para reservar (única vía de escritura)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reservar_franja(p_franja_id INTEGER)
RETURNS TABLE (reserva_id INTEGER, fecha DATE, hora_inicio TIME, hora_fin TIME, hora_tope TIMESTAMP)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_correo   TEXT := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_usuario  INTEGER;
  v_franja   franjas%ROWTYPE;
  v_activo   SMALLINT;
  v_tope     TIME;
  v_id       INTEGER;
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
$$;

REVOKE ALL ON FUNCTION public.reservar_franja(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reservar_franja(INTEGER) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Row Level Security: lectura pública, escritura solo por funciones
-- ---------------------------------------------------------------------
ALTER TABLE recursos ENABLE ROW LEVEL SECURITY;
ALTER TABLE franjas  ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservas ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS recursos_lectura ON recursos;
CREATE POLICY recursos_lectura ON recursos FOR SELECT USING (true);

DROP POLICY IF EXISTS franjas_lectura ON franjas;
CREATE POLICY franjas_lectura ON franjas FOR SELECT USING (true);

-- La disponibilidad necesita ver qué franjas están ocupadas.
DROP POLICY IF EXISTS reservas_lectura ON reservas;
CREATE POLICY reservas_lectura ON reservas FOR SELECT USING (true);

-- Cada persona solo ve su propio registro de usuario.
DROP POLICY IF EXISTS usuarios_propio ON usuarios;
CREATE POLICY usuarios_propio ON usuarios FOR SELECT
  USING (lower(correo) = lower(coalesce(auth.jwt() ->> 'email', '')));

-- Sin políticas de INSERT, UPDATE ni DELETE: el navegador no puede escribir
-- en ninguna tabla. Las escrituras pasan por funciones SECURITY DEFINER.

COMMIT;
