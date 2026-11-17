# Base de datos · Gestión de equipos de laboratorio (Error 404)

Base oficial entregada por el profesor (repositorio `jsricop/bd-reservas-error404`) organizada para el proyecto y para Supabase (proyecto nuevo `gestion-equipos-laboratorio-uan`, ref `gnhneqorycwupbookpzu`, organización «Error 404 UAN», creado el 15 nov 2026; reemplaza al proyecto anterior `igfzfwwanfcfjykctyzx`).

## Qué contiene

| Archivo | Qué hace | Origen |
|---|---|---|
| `00_diagnostico.sql` | Solo lectura. Dice en qué estado está la base y qué scripts faltan. | Equipo |
| `01_esquema_profesor.sql` | Crea las tablas `usuarios`, `recursos`, `franjas`, `reservas` (**borra las existentes**). | Profesor, sin cambios |
| `02_datos_profesor.sql` | 15 equipos, 40 usuarios, 1.800 franjas (7 sep–2 oct) y 216 reservas. | Profesor, sin cambios |
| `03_datos_complemento_profesor.sql` | 5.310 franjas y 354 reservas del 5 oct al 31 dic, sin fines de semana ni festivos. | Profesor (9 oct 2026), sin cambios |
| `04_validaciones_servidor_hora_tope.sql` | Hora tope por equipo, función `reservar_franja`, índices anti doble reserva y RLS. | Equipo (migración 001 sin generar franjas) |
| `05_devoluciones_y_reserva_dos_semanas.sql` | HU-05/HU-06 (`registrar_devolucion`) y CR-01 (`crear_reserva_dos_semanas`, anulación automática). | Equipo |
| `07_ajustes_seguridad_rendimiento.sql` | Corrige los avisos de Supabase: `search_path` fijo, funciones internas fuera de la API, política de usuarios optimizada e índice en `reservas.recurso_id`. | Equipo (17 nov) |
| `06_verificacion.sql` | Solo lectura. Compara la base con los valores esperados. | Equipo |
| `pruebas/` | Pruebas en transacción que se deshace: no dejan datos. | Equipo |
| `reparacion/` | Solo si ya se había aplicado la migración 001 original. | Equipo |

## Cómo ejecutarlo en Supabase

1. Abrir **Supabase → SQL Editor** del proyecto.
2. Ejecutar `00_diagnostico.sql`. La columna `que_hacer` dice qué camino seguir:

| Estado que muestra el diagnóstico | Scripts a ejecutar, en este orden |
|---|---|
| Base vacía | 01 → 02 → 03 → 04 → 05 → 06 |
| Solo datos base del profesor (hasta 2 oct) | 03 → 04 → 05 → 06 |
| Se aplicó la migración 001 original | `reparacion/A` → 03 → 04 → 05 → `reparacion/B` → 06 |
| Datos completos del profesor | 04 → 05 → 06 |
| Falta solo la 05 | 05 → 06 |
| Base al día | 06 |

3. En `06_verificacion.sql`, la columna `valor` debe coincidir con `esperado` en todas las filas.
4. Ejecutar `pruebas/pruebas_reglas_servidor.sql` (5 casos) y `pruebas/pruebas_devolucion_y_dos_semanas.sql` (9 casos). Todos deben salir «OK».

El archivo 03 pesa unos 310 KB. Si el SQL Editor no lo acepta completo, se puede ejecutar con `psql` y la cadena de conexión del proyecto (Project Settings → Database):

```bash
psql "postgresql://postgres.[ref]:[CLAVE]@aws-0-[region].pooler.supabase.com:5432/postgres" -v ON_ERROR_STOP=1 -f 03_datos_complemento_profesor.sql
```

## Reparación (migración 001 original ya aplicada)

La migración 001 original generaba sus propias franjas del 5 oct al 11 dic, incluidos los festivos, con ids desde 1801. Esos ids chocan con el complemento oficial del profesor.

- **A** guarda las reservas hechas desde la aplicación (id > 216) y borra las franjas generadas (id > 1800). Las 1.800 franjas y 216 reservas del profesor no se tocan.
- **B** vuelve a poner cada reserva de la aplicación en la franja oficial del mismo equipo, fecha y hora. Si la fecha era festivo, o si la franja ya tiene una reserva del profesor, la reserva se lista para avisar a la persona.

## Reglas que quedan en el servidor

- Solo usuarios registrados con correo `@uan.edu.co` y sesión iniciada pueden reservar o devolver.
- No se reserva una franja ocupada, pasada o que empiece después de la hora tope del equipo.
- **Reserva de dos semanas (CR-01):** `crear_reserva_dos_semanas(franja)` reserva la franja y la misma franja 7 días después. Si la segunda no existe (festivo o fin de calendario) o está ocupada, se reserva solo la primera y el mensaje lo explica.
- **Anulación:** si el primer préstamo no se devuelve antes de la hora límite, o se devuelve tarde, la reserva de la segunda semana pasa a `anulada` y la franja queda libre. Ocurre al registrar la devolución tarde y, cada 10 minutos, con `pg_cron`.
- **Devolución:** `registrar_devolucion(reserva)` marca `completada` y clasifica `a_tiempo` o `fuera_de_tiempo`.

## Pendientes para el equipo

- `pg_cron`: activarlo en Supabase (Database → Extensions) para que la anulación por no devolución corra sola. Sin él, la anulación solo se dispara al registrar una devolución tarde.
- Decisión del PO: hoy cualquier usuario registrado puede registrar una devolución. Definir si solo lo hace el laboratorista.
- Frontend: conectar los botones de HU-05/HU-06 y de reserva de dos semanas a `registrar_devolucion` y `crear_reserva_dos_semanas` con `supabase.rpc(...)`.

## Reemplaza a

- `../supabase_setup_profesor.sql`: le falta el complemento del profesor.
- `../migraciones/001_validaciones_servidor_hora_tope.sql`: generaba franjas propias que chocan con las oficiales.

No usar esos dos archivos ni el script `00_franjas` de SCRUM-55.

## Estado en Supabase (15 nov 2026)

Proyecto `gestion-equipos-laboratorio-uan` (`https://gnhneqorycwupbookpzu.supabase.co`), cargado en este orden: 01+02 y 03 (tomados directamente del repositorio del profesor), 04, `pg_cron` + 05.

- Verificación: las 15 comprobaciones coinciden (incluida la tarea `pg_cron` y 0 reservas de prueba sobrantes).
- Pruebas: 5/5 reglas del servidor y 9/9 devolución y dos semanas, deshechas al terminar.
- API pública: lee equipos, franjas y reservas; no muestra usuarios; sin sesión no se puede reservar.
- Auth: Site URL `https://gestion-equipos-laboratorio-uan.netlify.app` y redirección `https://gestion-equipos-laboratorio-uan.netlify.app/**`.
- `proyecto.html` apunta al proyecto nuevo (URL y clave publicable).

## Actualización 17 nov 2026

- Aplicado `07_ajustes_seguridad_rendimiento.sql` en Supabase. Quedan solo dos avisos: las tres funciones que usa la aplicación (`reservar_franja`, `registrar_devolucion`, `crear_reserva_dos_semanas`), que son intencionales, y la protección contra contraseñas filtradas de Auth.
- `pruebas/pruebas_integracion_usuario_real.sql` con el usuario real `cherrera31@uan.edu.co`: 9/9 OK (SCRUM-44, 50 y 59), sin datos sobrantes.
- `pg_cron`: 190 ejecuciones correctas de `anular-reservas-incumplidas` al 17 nov.
