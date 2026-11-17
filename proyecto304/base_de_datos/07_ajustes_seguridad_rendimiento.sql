-- =====================================================================
-- 07 · Ajustes de seguridad y rendimiento (avisos de Supabase, 17 nov 2026)
-- Ejecutar después de 05. No borra datos y se puede repetir.
-- =====================================================================
BEGIN;

-- 1. search_path fijo en las funciones auxiliares (lint 0011).
ALTER FUNCTION public.fn_ahora_bogota()               SET search_path = public;
ALTER FUNCTION public.fn_limite_devolucion(reservas)  SET search_path = public;

-- 2. Funciones internas fuera de la API pública (lints 0028/0029).
--    La anulación la ejecutan pg_cron (como postgres) y el disparador; el
--    navegador no necesita llamarlas. El disparador sigue funcionando.
REVOKE EXECUTE ON FUNCTION public.anular_reservas_por_incumplimiento() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_anular_por_devolucion_tardia()   FROM PUBLIC, anon, authenticated;

-- 3. La política de usuarios evalúa auth.jwt() una sola vez por consulta (lint 0003).
DROP POLICY IF EXISTS usuarios_propio ON usuarios;
CREATE POLICY usuarios_propio ON usuarios FOR SELECT
  USING (lower(correo) = lower(coalesce((SELECT auth.jwt()) ->> 'email', '')));

-- 4. Índice para la llave foránea reservas.recurso_id (lint 0001).
CREATE INDEX IF NOT EXISTS idx_reservas_recurso ON reservas (recurso_id);

COMMIT;
