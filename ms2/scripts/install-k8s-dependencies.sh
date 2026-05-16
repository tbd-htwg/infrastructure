#!/usr/bin/env bash
# Install in-cluster Redis + Elasticsearch (plain Kubernetes manifests) for tripplanning dev.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${ROOT}/k8s/dependencies"
NS="${NS:-tripplanning}"
MAX_PVC_GI="${MAX_PVC_GI:-20}"
MAX_PVC_COUNT="${MAX_PVC_COUNT:-0}"
REDIS_WAIT_TIMEOUT="${REDIS_WAIT_TIMEOUT:-120}"
ES_WAIT_TIMEOUT="${ES_WAIT_TIMEOUT:-600}"

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "ERROR: required command not found: $c"
      exit 1
    }
  done
}

audit_pvcs() {
  local pvc_json count oversize
  pvc_json="$(kubectl get pvc -n "${NS}" -o json 2>/dev/null || echo '{"items":[]}')"
  count="$(echo "${pvc_json}" | python3 -c "
import json, sys
items = json.load(sys.stdin).get('items', [])
print(len(items))
" 2>/dev/null || echo 0)"
  if [[ "${count}" -gt "${MAX_PVC_COUNT}" ]]; then
    echo "ERROR: expected at most ${MAX_PVC_COUNT} PVC(s) in ${NS}, found ${count}"
    kubectl get pvc -n "${NS}" 2>/dev/null || true
    exit 1
  fi
  oversize="$(echo "${pvc_json}" | python3 -c "
import json, re, sys
max_gi = int('${MAX_PVC_GI}')
bad = []
for item in json.load(sys.stdin).get('items', []):
    req = item.get('spec', {}).get('resources', {}).get('requests', {}).get('storage', '')
    m = re.match(r'^(\d+)(Gi)?$', str(req))
    if not m:
        continue
    gi = int(m.group(1))
    if gi > max_gi:
        bad.append(f\"{item['metadata']['name']}:{req}\")
if bad:
    print(','.join(bad))
" 2>/dev/null || true)"
  if [[ -n "${oversize}" ]]; then
    echo "ERROR: PVC(s) exceed ${MAX_PVC_GI}Gi: ${oversize}"
    exit 1
  fi
  echo "PVC audit OK (${count} claim(s) in ${NS}, each <= ${MAX_PVC_GI}Gi)."
}

main() {
  require_cmd kubectl python3

  kubectl get namespace "${NS}" >/dev/null 2>&1 || kubectl create namespace "${NS}"

  echo "== kubectl apply: Redis + Elasticsearch (${DEPS_DIR}) =="
  kubectl apply -k "${DEPS_DIR}"

  echo "== Waiting for redis Deployment (max ${REDIS_WAIT_TIMEOUT}s) =="
  kubectl wait --for=condition=Available deployment/redis -n "${NS}" --timeout="${REDIS_WAIT_TIMEOUT}s"

  echo "== Waiting for elasticsearch pod Ready (max ${ES_WAIT_TIMEOUT}s) =="
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=elasticsearch -n "${NS}" --timeout="${ES_WAIT_TIMEOUT}s"

  audit_pvcs
}

main "$@"
