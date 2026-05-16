#!/usr/bin/env bash
# Read-only audit of CPU, disk, and storage use before teardown or after changes.
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
CLUSTER="${GKE_CLUSTER:-tripplanning-gke}"
SSD_QUOTA_GB="${SSD_QUOTA_GB:-500}"
MAX_PVC_GI="${MAX_PVC_GI:-20}"

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

echo "Project: ${PROJECT}  Region: ${REGION}"

if gcloud container clusters describe "${CLUSTER}" --region="${REGION}" --project="${PROJECT}" &>/dev/null; then
  gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT}" >/dev/null
  echo ""
  echo "== Pods by namespace =="
  kubectl get pods -A -o wide 2>/dev/null || true
  echo ""
  echo "== Pod CPU requests (requires jq) =="
  if command -v jq &>/dev/null; then
    kubectl get pods -A -o json | jq -r '
      [.items[] | . as $p | .spec.containers[] |
        {ns: $p.metadata.namespace, pod: $p.metadata.name, cpu: (.resources.requests.cpu // "0")}] |
      group_by(.ns) | .[] | "\(.[0].ns): \(map(.cpu) | join(", "))"'
  fi
  echo ""
  echo "== PVCs (max ${MAX_PVC_GI}Gi per claim in tripplanning) =="
  kubectl get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SIZE:.spec.resources.requests.storage 2>/dev/null || true
  if command -v python3 &>/dev/null; then
    kubectl get pvc -A -o json 2>/dev/null | python3 -c "
import json, re, sys
max_gi = int('${MAX_PVC_GI}')
warn = []
for item in json.load(sys.stdin).get('items', []):
    req = item.get('spec', {}).get('resources', {}).get('requests', {}).get('storage', '')
    m = re.match(r'^(\d+)(Gi)?$', str(req))
    if not m:
        continue
    if int(m.group(1)) > max_gi:
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        warn.append(f'{ns}/{name}:{req}')
if warn:
    print('WARN: PVC(s) exceed {}Gi: {}'.format(max_gi, ', '.join(warn)))
" || true
  fi
  echo ""
  echo "== Non-app namespaces =="
  kubectl get pods -A 2>/dev/null | grep -E 'cert-manager|external-secrets|observability|flux-system|gmp-' || echo "(none)"
else
  echo "Cluster ${CLUSTER} not found."
fi

echo ""
echo "== GCE disks =="
gcloud compute disks list --filter="zone~${REGION}" --project="${PROJECT}" \
  --format="table(name,sizeGb,users)" 2>/dev/null || true

if command -v python3 &>/dev/null; then
  total_gb="$(gcloud compute disks list --filter="zone~${REGION}" --project="${PROJECT}" \
    --format='value(sizeGb)' 2>/dev/null | python3 -c "import sys; print(sum(int(x) for x in sys.stdin if x.strip()))" 2>/dev/null || echo 0)"
  echo "Total regional disk (approx): ${total_gb} GiB (quota target < ${SSD_QUOTA_GB} GB)"
  if [[ "${total_gb}" -gt $((SSD_QUOTA_GB - 50)) ]]; then
    echo "WARN: approaching ${SSD_QUOTA_GB} GB SSD quota — run cleanup-gke-disks.sh and reduce node count"
  fi
fi

echo ""
echo "== GCS bucket sizes =="
for b in "${PROJECT}-project-logs" "${PROJECT}-images-bucket" "${PROJECT}-frontend-bucket"; do
  gsutil du -sh "gs://${b}" 2>/dev/null || echo "gs://${b}: (missing or empty)"
done

echo ""
echo "== Cloud SQL =="
gcloud sql instances describe tripplanning-dev-pg --project="${PROJECT}" \
  --format="yaml(settings.tier,settings.dataDiskSizeGb)" 2>/dev/null || echo "tripplanning-dev-pg: not found"

echo ""
echo "== Project quotas (CPU / disk) =="
gcloud compute project-info describe --project="${PROJECT}" \
  --format="table(quotas.metric,quotas.limit,quotas.usage)" 2>/dev/null \
  | grep -iE 'CPU|DISK|STORAGE' || true
