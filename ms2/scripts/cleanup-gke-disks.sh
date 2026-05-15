#!/usr/bin/env bash
# List and optionally delete orphan GCE persistent disks (main cause of 500GB SSD quota on Autopilot).
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
DRY_RUN="${DRY_RUN:-true}"

echo "Project: ${PROJECT}  Region: ${REGION}  DRY_RUN=${DRY_RUN}"
echo ""
echo "== Disks in ${REGION} (orphans have empty USERS column) =="
gcloud compute disks list \
  --project="${PROJECT}" \
  --filter="zone~${REGION}" \
  --format="table(name,sizeGb,zone.basename(),users,status)"

ORPHANS="$(gcloud compute disks list \
  --project="${PROJECT}" \
  --filter="zone~${REGION} AND -users:*" \
  --format="value(name,zone)" 2>/dev/null || true)"

if [[ -z "${ORPHANS}" ]]; then
  echo ""
  echo "No unattached disks found in ${REGION}."
  exit 0
fi

echo ""
echo "Unattached disks:"
TOTAL_GB=0
while read -r name zone; do
  [[ -z "${name}" ]] && continue
  size="$(gcloud compute disks describe "${name}" --zone="${zone}" --project="${PROJECT}" --format='value(sizeGb)' 2>/dev/null || echo "?")"
  echo "  ${name}  ${size}GB  ${zone}"
  TOTAL_GB=$((TOTAL_GB + size))
done <<< "${ORPHANS}"

echo ""
echo "Approx unattached total: ${TOTAL_GB} GB"
echo ""
echo "To delete them: DRY_RUN=false ./scripts/cleanup-gke-disks.sh"
echo "Then scale down workloads so Autopilot releases node disks:"
echo "  kubectl delete -k gitops/tenants/tripplanning --ignore-not-found"

if [[ "${DRY_RUN}" == "true" ]]; then
  exit 0
fi

while read -r name zone; do
  [[ -z "${name}" ]] && continue
  echo "Deleting ${name} in ${zone}..."
  gcloud compute disks delete "${name}" --zone="${zone}" --project="${PROJECT}" --quiet
done <<< "${ORPHANS}"

echo "Done."
