# gestion-equipos-laboratorio

Aplicación web del equipo **Error 404** (Gestión de Proyectos de Software · UAN Sede Sur · 2026-II) para consultar los equipos de laboratorio, ver su disponibilidad por franja, registrar préstamos y controlar las devoluciones con la regla propia: **todo equipo prestado debe devolverse antes de su hora tope**.

- Tablero: Jira, proyecto **SCRUM** (7 historias de usuario en 5 épicas).
- Aplicación publicada: Netlify (URL en el documento de gestión del proyecto).

## Stack real

| Capa | Tecnología | Dónde está |
| --- | --- | --- |
| Interfaz | HTML5, CSS3 y JavaScript en un solo archivo | `proyecto304/proyecto.html` |
| Base de datos y servidor | Supabase (PostgreSQL 15) | Proyecto Supabase del equipo |
| Reglas de negocio en el servidor | Función `reservar_franja()` + índice único + RLS | `proyecto304/migraciones/` |
| Inicio de sesión | Supabase Auth (correo `@uan.edu.co`) | — |
| Publicación | Netlify, sitio estático | — |

El Charter inicial planteaba PHP + MySQL. El cambio a Supabase/PostgreSQL está registrado en el control de cambios del documento de gestión (CC-04).

## Estructura

```
proyecto304/
  proyecto.html                      Aplicación (catálogo, búsqueda, filtros, disponibilidad y préstamo)
  supabase_setup_profesor.sql        Esquema y datos semilla entregados por el profesor
  migraciones/
    001_validaciones_servidor_hora_tope.sql   Reglas de servidor y hora tope (deuda del Sprint 2)
  pruebas/
    pruebas_reglas_servidor.sql      Pruebas de doble reserva, fecha pasada, hora tope y RLS
docs/                                Charter y Definition of Done
```

## Cómo desplegar desde cero

1. **Base de datos.** En Supabase → SQL Editor ejecutar, en este orden:
   1. `proyecto304/supabase_setup_profesor.sql` (crea tablas y datos semilla; **borra** las tablas si ya existen).
   2. `proyecto304/migraciones/001_validaciones_servidor_hora_tope.sql` (no borra datos; se puede ejecutar más de una vez).
2. **Pruebas.** Ejecutar `proyecto304/pruebas/pruebas_reglas_servidor.sql`. Debe mostrar 5 filas con estado `OK`. No deja datos de prueba.
3. **Autenticación.** En Supabase → Authentication, habilitar el proveedor de correo. Solo pueden reservar las cuentas cuyo correo exista en la tabla `usuarios`.
4. **Claves.** En `proyecto.html`, `SUPABASE_URL` y `SUPABASE_KEY` deben ser los del proyecto (la clave es la *publishable*; es pública por diseño y la seguridad la dan las políticas RLS).
5. **Publicación.** Subir `proyecto304/proyecto.html` a Netlify (arrastrar la carpeta o conectar este repositorio con `proyecto304` como directorio de publicación).

> Plan gratuito: Supabase pausa el proyecto tras una semana sin uso y Netlify puede suspender el sitio. Abrir la URL 24 h y 1 h antes de cada Review (riesgo R-03).

## Reglas que valida el servidor

| Regla | Dónde | Criterio DoD v2 |
| --- | --- | --- |
| No se reserva una franja con reserva activa, ni con dos solicitudes simultáneas | `reservar_franja()` + índice `ux_reservas_franja_activa` | 20 |
| No se reserva una franja que ya pasó (hora de Bogotá) | `reservar_franja()` | 19 |
| La hora tope del equipo queda guardada en cada préstamo | columna `reservas.hora_tope` | CA04 |
| No se reserva una franja que empieza en la hora tope o después | `reservar_franja()` | Regla propia |
| El navegador no puede escribir directo en las tablas | RLS sin políticas de escritura | 18 |

## Convención de trabajo

- Una rama por tarea: `tipo/SCRUM-NN-descripcion`.
- La clave de Jira va en cada commit y Pull Request (`SCRUM-13: ...`) para que Jira muestre el desarrollo vinculado.
- Otro integrante revisa y aprueba el Pull Request antes de fusionar a `main` (DoD v2, criterio 16).
