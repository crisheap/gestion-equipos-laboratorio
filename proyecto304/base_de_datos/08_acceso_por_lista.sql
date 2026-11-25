-- =====================================================================
-- 08 · Acceso por lista desplegable (proyecto educativo · demo)
-- Error 404 · Gestión de equipos de laboratorio · UAN 2026-II
--
-- Pedido del PO (24 nov): ingresar eligiendo el usuario en una lista,
-- sin escribir contraseña, sin cambiar nada más del proyecto.
--
-- Cómo funciona sin tocar las reglas de negocio:
--   * Cada fila de `usuarios` tiene una cuenta de Supabase Auth con la
--     misma CLAVE DE DEMOSTRACIÓN. La página inicia sesión por debajo con
--     esa clave, así que reservar_franja, crear_reserva_dos_semanas,
--     registrar_devolucion, v_prestamos y las políticas RLS siguen
--     leyendo el correo del JWT exactamente igual que antes.
--   * listar_usuarios_acceso() entrega a la página (rol anon) solo
--     id, nombre y correo, para llenar la lista.
--
-- AVISO: la clave está también en proyecto.html, así que cualquiera que
-- abra la página puede entrar como cualquier usuario. Es intencional
-- para el proyecto educativo; no usar así con datos reales.
-- Se puede ejecutar más de una vez.
-- =====================================================================

-- 1) Lista pública de usuarios para el desplegable
CREATE OR REPLACE FUNCTION public.listar_usuarios_acceso()
RETURNS TABLE (id integer, nombre text, correo text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id, u.nombre::text, lower(u.correo)::text
  FROM usuarios u
  ORDER BY u.nombre;
$$;

REVOKE ALL ON FUNCTION public.listar_usuarios_acceso() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_usuarios_acceso() TO anon, authenticated;

-- 2) Cuentas de acceso con la clave de demostración
DO $$
DECLARE
  v_clave text := 'Demo-x4_7wrQbYezK';   -- misma constante que CLAVE_DEMO en proyecto.html
  r record;
  v_id uuid;
BEGIN
  FOR r IN SELECT lower(correo) AS correo FROM public.usuarios LOOP
    v_id := NULL;
    SELECT a.id INTO v_id FROM auth.users a WHERE lower(a.email) = r.correo;

    IF v_id IS NULL THEN
      v_id := gen_random_uuid();
      INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change, email_change_token_new
      ) VALUES (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
        r.correo, extensions.crypt(v_clave, extensions.gen_salt('bf')),
        now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        now(), now(), '', '', '', ''
      );
      INSERT INTO auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      ) VALUES (
        gen_random_uuid(), v_id, v_id::text, 'email',
        jsonb_build_object('sub', v_id::text, 'email', r.correo,
                           'email_verified', true, 'phone_verified', false),
        now(), now(), now()
      );
    ELSE
      UPDATE auth.users
         SET encrypted_password = extensions.crypt(v_clave, extensions.gen_salt('bf')),
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             updated_at = now()
       WHERE id = v_id;
    END IF;
  END LOOP;
END $$;
