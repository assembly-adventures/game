#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
namespace="${1:-teddyt}"
app_host="${2:?Usage: infra/deploy.sh NAMESPACE APP_HOST}"
for asset in index.html index.js index.wasm index.pck; do
  test -s "build/web/$asset" || { echo "Missing build/web/$asset; run infra/export_web.py first." >&2; exit 1; }
done
oc whoami >/dev/null
oc get namespace "$namespace" >/dev/null
./infra/database.sh "$namespace"
context_dir="$(mktemp -d)"
trap 'rm -rf "$context_dir"' EXIT
mkdir -p "$context_dir/infra" "$context_dir/build/web" "$context_dir/server"
cp infra/Dockerfile "$context_dir/infra/"
cp server/app.py server/api.py server/database.py server/grading.py server/gameplay.py server/requirements.txt "$context_dir/server/"
mkdir -p "$context_dir/db/migrations" "$context_dir/db/seed"
cp db/migrations/*.sql "$context_dir/db/migrations/"
cp db/seed/*.sql "$context_dir/db/seed/"
cp -R build/web/. "$context_dir/build/web/"
# Keep the same signing key across deployments; do not print it to the terminal.
if ! oc get secret assembly-adventures-session -n "$namespace" >/dev/null 2>&1; then
  python3 -c 'import json, secrets; print(json.dumps({"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "assembly-adventures-session"}, "type": "Opaque", "stringData": {"SESSION_SECRET": secrets.token_urlsafe(48)}}))' |
    oc create -n "$namespace" -f -
fi
oc process --local -f infra/app-template.yaml -p "NAMESPACE=$namespace" -p "APP_HOST=$app_host" |
  oc apply -n "$namespace" -f -
oc start-build assembly-adventures -n "$namespace" --from-dir="$context_dir" --follow --wait
oc rollout status deployment/assembly-adventures -n "$namespace" --timeout=180s
echo "Deployment ready: https://$app_host — verify Onyen login in a browser."
