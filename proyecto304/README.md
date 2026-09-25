# Proyecto 304 - versión mejorada

Se conservaron la estructura visual y el inicio de sesión de `proyecto.html`.
Los cambios principales son:

1. El catálogo ahora usa las tablas del proyecto del profesor: `recursos`, `franjas`, `reservas` y `usuarios`.
2. Se cargan los 15 equipos reales incluidos en los datos entregados por el profesor.
3. Se agregó búsqueda por nombre, tipo, ubicación y atributos.
4. Se agregaron filtros por tipo y ubicación.
5. La reserva ahora selecciona fecha y franja horaria.
6. Antes de reservar se consulta si la franja está libre.
7. El correo autenticado se relaciona con `usuarios.correo`.
8. La reserva se guarda en `reservas`, en vez de usar `prestamos`.
9. Se conserva Supabase Auth para el inicio de sesión.

## Base de datos

Ejecuta `supabase_setup_profesor.sql` en Supabase SQL Editor para crear/cargar las tablas y datos del profesor.

IMPORTANTE: ese script contiene `DROP TABLE IF EXISTS`, igual que el script original del profesor. Si ya tienes información importante en tu Supabase, haz respaldo y revisa antes de ejecutarlo.

## Usuarios de prueba

La tabla `usuarios` contiene los 40 usuarios semilla del profesor. Para que una cuenta de Supabase Auth pueda crear reservas, su correo debe coincidir con uno de esos correos.

## Nota

La base de datos del profesor no tiene una tabla `laboratorios`, `equipos` o `prestamos`. Por eso el código original del 304 se cambió únicamente en la capa de datos para usar el modelo que entregó el profesor.
