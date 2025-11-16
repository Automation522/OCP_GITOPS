#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST manquant}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?PGDATABASE manquant}"
: "${PGUSER:?PGUSER manquant}"
: "${PGPASSWORD:?PGPASSWORD manquant}"

CONN_STR="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}"

echo "Attente de PostgreSQL ${PGHOST}:${PGPORT}..."
until psql "$CONN_STR" -c "SELECT 1" >/dev/null 2>&1; do
  sleep 2
  echo "Toujours en attente de PostgreSQL..."
done

echo "Base accessible, application du script seed.sql"
psql "$CONN_STR" -f /opt/db/seed.sql

echo "Initialisation terminée"
