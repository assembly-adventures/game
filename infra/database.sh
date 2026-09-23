#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
namespace="${1:-teddyt}"
oc whoami >/dev/null
if ! oc get secret assembly-adventures-postgres-credentials -n "$namespace" >/dev/null 2>&1; then
  python3 -c 'import json,secrets; print(json.dumps({"apiVersion":"v1","kind":"Secret","metadata":{"name":"assembly-adventures-postgres-credentials"},"type":"Opaque","stringData":{"POSTGRESQL_USER":"assembly_adventures","POSTGRESQL_DATABASE":"assembly_adventures","POSTGRESQL_PASSWORD":secrets.token_urlsafe(48)}}))' |
    oc create -n "$namespace" -f -
fi
oc process --local -f infra/postgres-template.yaml -p "NAMESPACE=$namespace" |
  oc apply -n "$namespace" -f -
oc rollout status deployment/assembly-adventures-postgres -n "$namespace" --timeout=180s
