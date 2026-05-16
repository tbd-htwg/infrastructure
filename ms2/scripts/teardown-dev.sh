#!/usr/bin/env bash
# Wipe all ms2 dev resources inside the GCP project (keep the project itself).
# Order: Kubernetes workloads → Cloud SQL first → terraform destroy → orphan check.
# Orchestrated by docs/gettingstarted/dev-lifecycle.sh — keep in sync with gettingstarted/README.md §2.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
CLUSTER="${GKE_CLUSTER:-tripplanning-gke}"
SQL_INSTANCE="${CLOUDSQL_INSTANCE:-tripplanning-dev-pg}"
VPC_NETWORK="${VPC_NETWORK:-tripplanning-vpc}"
PRIVATE_RANGE_NAME="${SQL_INSTANCE}-private-range"
LOG_BUCKET="${PROJECT}-project-logs"
TF_DIR="${ROOT}/terraform/envs/dev"
SKIP_K8S="${SKIP_K8S:-false}"
SKIP_TF="${SKIP_TF:-false}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
SKIP_QUOTA_CHECK="${SKIP_QUOTA_CHECK:-true}"

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Cloud SQL private IP leaves a global reserved range + servicenetworking peering on the VPC.
# Must delete in GCP before terraform destroy can remove tripplanning-vpc (even if removed from state).
cleanup_cloudsql_private_service() {
  echo "== Release private service access (peering + ${PRIVATE_RANGE_NAME}) =="

  if gcloud compute networks peerings list --network="${VPC_NETWORK}" --project="${PROJECT}" \
    --format="value(name)" 2>/dev/null | grep -q servicenetworking; then
    echo "Deleting VPC peering servicenetworking-googleapis-com..."
    gcloud compute networks peerings delete servicenetworking-googleapis-com \
      --network="${VPC_NETWORK}" --project="${PROJECT}" --quiet 2>/dev/null || true
    sleep 10
  fi

  if gcloud compute addresses describe "${PRIVATE_RANGE_NAME}" --global --project="${PROJECT}" &>/dev/null; then
    echo "Deleting global address ${PRIVATE_RANGE_NAME}..."
    gcloud compute addresses delete "${PRIVATE_RANGE_NAME}" \
      --global --project="${PROJECT}" --quiet 2>/dev/null || true
    sleep 5
  fi
}

tf_destroy() {
  local -a extra=("$@")
  cd "${TF_DIR}"
  terraform init
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    terraform destroy -auto-approve "${extra[@]}"
  else
    terraform destroy "${extra[@]}"
  fi
}

echo "== Teardown dev stack in project ${PROJECT} (project is NOT deleted) =="

if [[ "${SKIP_K8S}" != "true" ]]; then
  if gcloud container clusters describe "${CLUSTER}" --region="${REGION}" --project="${PROJECT}" &>/dev/null; then
    echo "== kubectl: cluster ${CLUSTER} =="
    gcloud container clusters get-credentials "${CLUSTER}" --region="${REGION}" --project="${PROJECT}"

    echo "== Remove Redis + Elasticsearch (k8s dependencies) =="
    helm uninstall redis elasticsearch -n tripplanning 2>/dev/null || true
    kubectl delete -k "${ROOT}/k8s/dependencies" --ignore-not-found --wait=true || true

    kubectl delete -k "${ROOT}/gitops/tenants/tripplanning" --ignore-not-found --wait=true || true

    while read -r ns; do
      kubectl delete namespace "${ns}" --ignore-not-found --wait=false || true
    done < <(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -E '^(tripplanning|tenant-)' || true)

    for ns in cert-manager external-secrets observability flux-system; do
      kubectl delete namespace "${ns}" --ignore-not-found --wait=false || true
    done

    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml --ignore-not-found 2>/dev/null || true
    kubectl delete -f https://github.com/external-secrets/external-secrets/releases/download/v0.10.5/external-secrets.yaml --ignore-not-found 2>/dev/null || true

    echo "Waiting for Gateway / LoadBalancer cleanup..."
    for _ in $(seq 1 30); do
      lbs="$(kubectl get svc -A --field-selector spec.type=LoadBalancer -o name 2>/dev/null | wc -l || echo 0)"
      gws="$(kubectl get gateway -A -o name 2>/dev/null | wc -l || echo 0)"
      if [[ "${lbs}" -eq 0 && "${gws}" -eq 0 ]]; then
        break
      fi
      sleep 10
    done
  else
    echo "Cluster ${CLUSTER} not found; skipping kubectl teardown."
  fi
fi

if [[ "${SKIP_TF}" != "true" ]]; then
  echo "== Pre-destroy: empty log sink bucket (if present) =="
  if gsutil ls -b "gs://${LOG_BUCKET}" &>/dev/null; then
    gsutil -m rm -r "gs://${LOG_BUCKET}/**" 2>/dev/null || true
  fi

  echo "== Cloud SQL: delete instance via gcloud (avoids terraform -target user/DB ordering errors) =="
  if gcloud sql instances describe "${SQL_INSTANCE}" --project="${PROJECT}" &>/dev/null; then
    gcloud sql instances delete "${SQL_INSTANCE}" --project="${PROJECT}" --quiet || true
    echo "Waiting for Cloud SQL instance ${SQL_INSTANCE} to finish deleting..."
    for _ in $(seq 1 40); do
      if ! gcloud sql instances describe "${SQL_INSTANCE}" --project="${PROJECT}" &>/dev/null; then
        break
      fi
      sleep 15
    done
  fi

  cleanup_cloudsql_private_service

  if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q 'module.cloudsql'; then
    echo "== Terraform: remove Cloud SQL module from state (GCP resources already deleted) =="
    while read -r addr; do
      [[ -z "${addr}" ]] && continue
      terraform -chdir="${TF_DIR}" state rm "${addr}" 2>/dev/null || true
    done < <(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep '^module\.cloudsql\.' || true)
  fi

  # Identity / Firebase were removed from Terraform (manual setup). Old state still
  # references hashicorp/google-beta and blocks destroy unless removed.
  if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -qE '^module\.identity_platform'; then
    echo "== Terraform: remove legacy module.identity_platform from state (not in config; Identity is manual) =="
    while read -r addr; do
      [[ -z "${addr}" ]] && continue
      terraform -chdir="${TF_DIR}" state rm "${addr}" 2>/dev/null || true
    done < <(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -E '^module\.identity_platform' || true)
  fi

  echo "== terraform destroy: remaining resources =="
  if ! tf_destroy; then
    echo "== Fallback: release private service access and retry destroy =="
    cleanup_cloudsql_private_service
    while read -r addr; do
      [[ -z "${addr}" ]] && continue
      terraform -chdir="${TF_DIR}" state rm "${addr}" 2>/dev/null || true
    done < <(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep '^module\.cloudsql\.' || true)
    while read -r addr; do
      [[ -z "${addr}" ]] && continue
      terraform -chdir="${TF_DIR}" state rm "${addr}" 2>/dev/null || true
    done < <(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -E '^module\.identity_platform' || true)
    tf_destroy
  fi
fi

echo "== Orphan disks (Autopilot boot PDs often linger after scale-down) =="
if [[ -x "${ROOT}/scripts/cleanup-gke-disks.sh" ]]; then
  DRY_RUN="${DRY_RUN:-true}" "${ROOT}/scripts/cleanup-gke-disks.sh" || true
  echo "To delete unattached disks: DRY_RUN=false ${ROOT}/scripts/cleanup-gke-disks.sh"
else
  gcloud compute disks list --filter="zone~${REGION}" --project="${PROJECT}" \
    --format="table(name,sizeGb,users)" 2>/dev/null || true
fi
gcloud compute forwarding-rules list --regions="${REGION}" --project="${PROJECT}" 2>/dev/null || true
gcloud compute addresses list --regions="${REGION}" --project="${PROJECT}" 2>/dev/null || true
gsutil ls -p "${PROJECT}" 2>/dev/null || true

if [[ "${SKIP_QUOTA_CHECK}" != "true" ]]; then
  echo "== Quota usage (CPU / disk) — confirm headroom before terraform apply =="
  gcloud compute project-info describe --project="${PROJECT}" \
    --format="table(quotas.metric,quotas.limit,quotas.usage)" 2>/dev/null \
    | grep -iE 'CPU|DISK|STORAGE' || true
fi

echo "Done. Recreate with: ${ROOT}/docs/gettingstarted/dev-lifecycle.sh setup"
