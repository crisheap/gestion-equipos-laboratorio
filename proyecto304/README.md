# Proyecto 304 · aplicación

Ver el `README.md` de la raíz para el despliegue completo.

- `proyecto.html`: catálogo con estado, búsqueda y filtros, consulta de franjas libres, préstamo con hora tope, reserva de dos semanas (CR-01) y «Mis préstamos» con registro de devolución (HU-05 y HU-06). Usa el proyecto de Supabase `gestion-equipos-laboratorio-uan`.
- `base_de_datos/`: **base vigente**. Scripts 00 a 07 en orden, pruebas y reparación; ver su `README.md`.
- `supabase_setup_profesor.sql`, `migraciones/001_validaciones_servidor_hora_tope.sql` y `pruebas/pruebas_reglas_servidor.sql`: solo historial. No ejecutarlos: no traen el complemento del profesor y la 001 genera franjas que chocan con las oficiales.

Para reservar, el correo con el que se inicia sesión debe existir en la tabla `usuarios`.
