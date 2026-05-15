#!/usr/bin/env bash
# Read-only audit of CPU, disk, and storage use before teardown or after changes.
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
CLUSTER="${GKE_CLUSTER:-tripplanning-gke}"

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
  echo "== PVCs =="
  kubectl get pvc -A 2>/dev/null || true
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
