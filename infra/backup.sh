#!/usr/bin/env bash
set -euo pipefail
set -o noclobber
umask 077
namespace="${1:?Usage: infra/backup.sh NAMESPACE OUTPUT.dump}"
output="${2:?Supply an output path outside version control}"
oc exec -n "$namespace" deployment/assembly-adventures-postgres -- \
  sh -c 'PGPASSWORD="$POSTGRESQL_PASSWORD" pg_dump -h 127.0.0.1 -U "$POSTGRESQL_USER" -d "$POSTGRESQL_DATABASE" -Fc' > "$output"
echo "Database backup saved to $output"
