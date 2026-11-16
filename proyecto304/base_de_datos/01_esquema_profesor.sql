-- =====================================================================
-- 01 · Esquema del profesor (PostgreSQL / Supabase)
-- Fuente: github.com/jsricop/bd-reservas-error404 · esquema/esquema_postgres.sql
-- Copia sin cambios.
--
-- ATENCIÓN: borra y vuelve a crear las cuatro tablas (DROP TABLE).
-- Ejecutarlo SOLO al montar la base desde cero. Ver README.md.
-- =====================================================================

-- Esquema del sistema de reserva de recursos · PostgreSQL
-- Gestión de Proyectos de Software · UAN · 2026-II

DROP TABLE IF EXISTS reservas;
DROP TABLE IF EXISTS franjas;
DROP TABLE IF EXISTS recursos;
DROP TABLE IF EXISTS usuarios;

CREATE TABLE usuarios (
  id        INTEGER PRIMARY KEY,
  nombre    VARCHAR(120) NOT NULL,
  codigo    VARCHAR(20)  NOT NULL UNIQUE,
  programa  VARCHAR(80)  NOT NULL,
  correo    VARCHAR(120) NOT NULL UNIQUE
);

CREATE TABLE recursos (
  id         INTEGER PRIMARY KEY,
  nombre     VARCHAR(120) NOT NULL,
  tipo       VARCHAR(60)  NOT NULL,
  ubicacion  VARCHAR(80)  NOT NULL,
  capacidad  INTEGER      NOT NULL DEFAULT 1,
  atributos  VARCHAR(200),
  activo     SMALLINT     NOT NULL DEFAULT 1
);

CREATE TABLE franjas (
  id          INTEGER PRIMARY KEY,
  recurso_id  INTEGER NOT NULL REFERENCES recursos(id),
  fecha       DATE NOT NULL,
  hora_inicio TIME NOT NULL,
  hora_fin    TIME NOT NULL
);
CREATE INDEX idx_franjas_recurso_fecha ON franjas(recurso_id, fecha);

CREATE TABLE reservas (
  id          INTEGER PRIMARY KEY,
  franja_id   INTEGER NOT NULL REFERENCES franjas(id),
  recurso_id  INTEGER NOT NULL REFERENCES recursos(id),
  usuario_id  INTEGER NOT NULL REFERENCES usuarios(id),
  fecha       DATE NOT NULL,
  hora_inicio TIME NOT NULL,
  hora_fin    TIME NOT NULL,
  estado      VARCHAR(15) NOT NULL,
  creada_en   TIMESTAMP NOT NULL
);
CREATE INDEX idx_reservas_usuario ON reservas(usuario_id, estado);
CREATE INDEX idx_reservas_franja  ON reservas(franja_id, estado);
