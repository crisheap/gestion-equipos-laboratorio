# Proyecto 304 · aplicación

Ver el `README.md` de la raíz para el despliegue completo.

- `proyecto.html`: catálogo con estado (disponible, prestado ahora, en mantenimiento), búsqueda, filtros por tipo, ubicación y estado, consulta de franjas libres y préstamo con hora tope.
- `supabase_setup_profesor.sql`: esquema y datos del profesor (15 equipos, 40 usuarios, 1.800 franjas del 7 sep al 2 oct, 216 reservas). Contiene `DROP TABLE`: no ejecutar sobre datos reales sin respaldo.
- `migraciones/001_validaciones_servidor_hora_tope.sql`: hora tope por equipo y por préstamo, índice contra doble reserva, función `reservar_franja()`, RLS y franjas del 5 oct al 11 dic de 2026.
- `pruebas/pruebas_reglas_servidor.sql`: evidencia de las reglas de servidor (5 casos).

Para reservar, el correo con el que se inicia sesión debe existir en la tabla `usuarios`.
