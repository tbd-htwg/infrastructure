#!/usr/bin/env bash
# Trip Planner ms2 — full dev teardown + setup (minimal GKE profile).
# Keep in sync with README.md in this directory.
#
# Usage:
#   ./dev-lifecycle.sh <command> [options]
#
# Commands:
#   audit              Read-only quota / resource audit (§1)
#   teardown           In-project wipe: K8s + Terraform (§2)
#   setup              Full setup after teardown: TF → secrets → deploy → verify (§3–7)
#   reset              teardown + setup (§2 + §3–10, optional steps via env)
#   terraform-apply    Terraform init/apply only (§3)
#   secrets            GSM secret versions (§4)
#   deploy             Build, push, kubectl apply, bootstrap secrets (§6)
#   verify             Pod health + smoke checks (§7)
#   firestore-indexes  Create composite index (§8)
#   gateway-info       Print Gateway IP + DNS hint (§9)
#   frontend           Build and rsync frontend to GCS (§10)
#   help               Show this help
#
# Common environment variables:
#   GOOGLE_PROJECT, GOOGLE_REGION, GKE_CLUSTER, CLOUDSQL_INSTANCE
#   AUTO_APPROVE=false      Prompt for terraform apply/destroy (default: true = -auto-approve)
#   AUTO_CONTINUE=false     After teardown in reset, prompt before setup (default: true = continue)
#   SKIP_K8S, SKIP_TF          Teardown toggles (see §2)
#   SKIP_AUDIT=true (default)     Skip slow quota audit in reset/teardown
#   RUN_AUDIT=true                Force audit (overrides SKIP_AUDIT)
#   SKIP_QUOTA_CHECK=true (default)  Skip quota lines in teardown-dev.sh
#   ROLLOUT_TIMEOUT=180           Max seconds to wait per deployment (default 180)
#   SKIP_ROLLOUT_WAIT=true        Skip rollout wait (script continues immediately)
#   SKIP_TERRAFORM, SKIP_SECRETS, SKIP_DEPLOY, SKIP_VERIFY
#   SKIP_FIRESTORE_INDEXES, SKIP_FRONTEND, SKIP_GATEWAY_INFO
#   JWT_SECRET, INTERNAL_SECRET  Required for secrets (≥32 chars for JWT)
#   IMAGE_TAG, VITE_API_BASE_URL, VITE_FIREBASE_API_KEY, VITE_FIREBASE_AUTH_DOMAIN, VITE_FIREBASE_PROJECT_ID
#   .env in this directory is sourced automatically (if present); exports all assignments.
#   LIFECYCLE_LOG_FILE=path   Override log path (default: logs/dev-lifecycle-YYYYMMDD-HHMMSS.log)
#   NO_LOG=true               Do not write a log file (stdout only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/.env"
  set +a
fi
MS2_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${MS2_ROOT}/../.." && pwd)"
TF_DIR="${MS2_ROOT}/terraform/envs/dev"
BACKEND="${REPO_ROOT}/backend"
FRONTEND="${REPO_ROOT}/frontend"

PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
CLUSTER="${GKE_CLUSTER:-tripplanning-gke}"
SQL_INSTANCE="${CLOUDSQL_INSTANCE:-tripplanning-dev-pg}"
TAG="${IMAGE_TAG:-dev}"
API_HOST="${API_HOST:-api.k8s.tbd-htwg.de}"
VITE_API_BASE_URL="${VITE_API_BASE_URL:-http://${API_HOST}}"
FRONTEND_BUCKET="${PROJECT}-frontend-bucket"
AR="${REGION}-docker.pkg.dev/${PROJECT}/tripplanning"

AUTO_APPROVE="${AUTO_APPROVE:-true}"
AUTO_CONTINUE="${AUTO_CONTINUE:-true}"

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

LOG_FILE=""

init_logging() {
  [[ "${NO_LOG:-false}" == "true" ]] && return 0
  local log_dir="${SCRIPT_DIR}/logs"
  mkdir -p "${log_dir}"
  LOG_FILE="${LIFECYCLE_LOG_FILE:-${log_dir}/dev-lifecycle-$(date +%Y%m%d-%H%M%S).log}"
  ln -sfn "$(basename "${LOG_FILE}")" "${log_dir}/latest.log"
  exec > >(tee -a "${LOG_FILE}") 2>&1
  echo "== dev-lifecycle log: ${LOG_FILE} =="
  echo "Started: $(date -Is)  command=${1:-}  project=${PROJECT}"
}

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "ERROR: required command not found: $c (see README §0 Prerequisites)"
      exit 1
    }
  done
}

cmd_prerequisites() {
  require_cmd gcloud kubectl terraform mvn docker jq
  gcloud config set project "${PROJECT}" >/dev/null
  gcloud auth application-default set-quota-project "${PROJECT}" 2>/dev/null \
    || echo "WARN: could not set ADC quota project (run: gcloud auth application-default set-quota-project ${PROJECT})"
  echo "Project: ${PROJECT}  Region: ${REGION}  Cluster: ${CLUSTER}"
}

cmd_audit() {
  cmd_prerequisites
  "${MS2_ROOT}/scripts/audit-dev-quotas.sh"
}

cmd_teardown() {
  cmd_prerequisites
  local quota_skip=true
  if should_run_audit; then
    quota_skip=false
  fi
  AUTO_APPROVE="${AUTO_APPROVE}" SKIP_K8S="${SKIP_K8S:-false}" SKIP_TF="${SKIP_TF:-false}" \
    SKIP_QUOTA_CHECK="${quota_skip}" \
    "${MS2_ROOT}/scripts/teardown-dev.sh"
}

cmd_terraform_apply() {
  cmd_prerequisites
  require_cmd terraform
  cd "${TF_DIR}"
  if [[ ! -f terraform.tfvars ]]; then
    cp terraform.tfvars.example terraform.tfvars
    echo "Created terraform.tfvars from example — review before apply."
  fi
  terraform init
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    terraform apply -auto-approve
  else
    terraform apply
  fi
}

secret_has_version() {
  gcloud secrets versions access latest --secret="$1" --project="${PROJECT}" &>/dev/null
}

cmd_secrets() {
  cmd_prerequisites
  if secret_has_version tripplanning-auth-jwt-secret && secret_has_version tripplanning-internal-secret; then
    echo "GSM secrets already have versions; skipping (set FORCE_SECRETS=true to overwrite)."
    [[ "${FORCE_SECRETS:-false}" == "true" ]] || return 0
  fi
  if [[ -z "${JWT_SECRET:-}" ]]; then
    echo "ERROR: Set JWT_SECRET (≥32 characters) for tripplanning-auth-jwt-secret"
    echo "  export JWT_SECRET='your-dev-jwt-secret-min-32-chars!!'"
    exit 1
  fi
  if [[ ${#JWT_SECRET} -lt 32 ]]; then
    echo "ERROR: JWT_SECRET must be at least 32 characters"
    exit 1
  fi
  INTERNAL_SECRET="${INTERNAL_SECRET:-dev-internal-service-secret}"
  echo -n "${JWT_SECRET}" | gcloud secrets versions add tripplanning-auth-jwt-secret \
    --data-file=- --project="${PROJECT}"
  echo -n "${INTERNAL_SECRET}" | gcloud secrets versions add tripplanning-internal-secret \
    --data-file=- --project="${PROJECT}"
  if [[ -n "${ES_PASSWORD:-}" ]]; then
    echo -n "${ES_PASSWORD}" | gcloud secrets versions add tbd-es-gateway-elastic-password \
      --data-file=- --project="${PROJECT}"
  fi
  echo "Secret Manager versions updated."
}

cmd_deploy() {
  cmd_prerequisites
  require_cmd npm
  gcloud config set project "${PROJECT}" >/dev/null
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

  echo "== Maven package =="
  (cd "${BACKEND}" && mvn -q -pl tripplanning-trip-service,tripplanning-social-service -am package -DskipTests)

  echo "== Docker build & push =="
  (cd "${BACKEND}" && docker build --build-arg SERVICE=trip -t "${AR}/tripplanning-trip-service:${TAG}" .)
  (cd "${BACKEND}" && docker build --build-arg SERVICE=social -t "${AR}/tripplanning-social-service:${TAG}" .)
  docker push "${AR}/tripplanning-trip-service:${TAG}"
  docker push "${AR}/tripplanning-social-service:${TAG}"

  echo "== kubectl =="
  gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}"
  kubectl delete deployment elasticsearch -n tripplanning --ignore-not-found 2>/dev/null || true
  kubectl apply -k "${MS2_ROOT}/gitops/tenants/tripplanning"
  GOOGLE_PROJECT="${PROJECT}" "${MS2_ROOT}/scripts/bootstrap-k8s-secrets.sh"

  PROJECT_NUM="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.reader" \
    --condition=None >/dev/null 2>&1 || true

  local timeout="${ROLLOUT_TIMEOUT:-180}"
  # Recreate strategy + sequential restart: at most one extra pod per deploy, not two rollouts in parallel.
  kubectl rollout restart deployment/trip-service -n tripplanning 2>/dev/null || true
  if [[ "${SKIP_ROLLOUT_WAIT:-false}" == "true" ]]; then
    echo "Skipping rollout wait (SKIP_ROLLOUT_WAIT=true)."
  else
    echo "Waiting for trip-service rollout (max ${timeout}s)..."
    kubectl rollout status deployment/trip-service -n tripplanning --timeout="${timeout}s" || {
      echo "WARN: trip-service not ready — rebuild image after application-gke-dev.yml changes; see README §6."
      kubectl logs -n tripplanning deployment/trip-service -c trip-service --tail=20 2>/dev/null || true
    }
  fi
  kubectl rollout restart deployment/social-service -n tripplanning 2>/dev/null || true
  if [[ "${SKIP_ROLLOUT_WAIT:-false}" != "true" ]]; then
    echo "Waiting for social-service rollout (max ${timeout}s)..."
    kubectl rollout status deployment/social-service -n tripplanning --timeout="${timeout}s" || {
      echo "WARN: social-service not ready — check: kubectl logs -n tripplanning deployment/social-service --tail=30"
    }
  fi
  kubectl get pods -n tripplanning
}

cmd_verify() {
  cmd_prerequisites
  API_HOST="${API_HOST}" "${MS2_ROOT}/scripts/verify-gke-deployment.sh"
}

cmd_firestore_indexes() {
  cmd_prerequisites
  gcloud firestore indexes composite create \
    --database=tbd-firestore --project="${PROJECT}" \
    --collection-group=comments --query-scope=COLLECTION \
    --field-config field-path=tripId,order=ASCENDING \
    --field-config field-path=createdAt,order=DESCENDING \
    2>/dev/null || echo "Index may already exist (OK)."
}

cmd_gateway_info() {
  cmd_prerequisites
  gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}" 2>/dev/null || true
  echo "== Gateway / HTTPRoute =="
  kubectl get gateway,httproute -n tripplanning 2>/dev/null || {
    echo "Namespace tripplanning not found; run deploy first."
    exit 1
  }
  IP="$(kubectl get gateway tripplanning-api -n tripplanning \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
  if [[ -n "${IP}" ]]; then
    echo ""
    echo "Gateway IP: ${IP}"
    echo "Point DNS A/AAAA for ${API_HOST} → ${IP}"
    echo "Optional: social.api.k8s.tbd-htwg.de → ${IP} (direct social-service)"
    echo "Test: curl -sS http://${API_HOST}/actuator/health"
  else
    echo "Gateway IP not ready yet; kubectl describe gateway tripplanning-api -n tripplanning"
  fi
}

cmd_frontend() {
  cmd_prerequisites
  require_cmd npm gsutil
  (cd "${FRONTEND}" && npm ci)
  (cd "${FRONTEND}" && VITE_API_BASE_URL="${VITE_API_BASE_URL}" npm run build)
  gsutil -m rsync -r "${FRONTEND}/dist" "gs://${FRONTEND_BUCKET}/"
  echo "Frontend synced to gs://${FRONTEND_BUCKET}/"
}

cmd_setup() {
  echo "== Setup: minimal dev stack in ${PROJECT} =="
  [[ "${SKIP_TERRAFORM:-false}" == "true" ]] || cmd_terraform_apply
  [[ "${SKIP_SECRETS:-false}" == "true" ]] || cmd_secrets
  [[ "${SKIP_DEPLOY:-false}" == "true" ]] || cmd_deploy
  [[ "${SKIP_VERIFY:-false}" == "true" ]] || cmd_verify
  [[ "${SKIP_FIRESTORE_INDEXES:-false}" == "true" ]] || cmd_firestore_indexes
  [[ "${SKIP_GATEWAY_INFO:-false}" == "true" ]] || cmd_gateway_info
  [[ "${SKIP_FRONTEND:-false}" == "true" ]] || cmd_frontend
  echo ""
  echo "Setup complete. See README.md §6 (gke-dev / Lucene) and SSD quota if disks fill."
}

should_run_audit() {
  [[ "${RUN_AUDIT:-false}" == "true" ]] && return 0
  [[ "${SKIP_AUDIT:-true}" != "true" ]]
}

cmd_reset() {
  echo "== Full reset: teardown → setup =="
  if should_run_audit; then
    cmd_audit
  fi
  cmd_teardown
  if should_run_audit; then
    echo ""
    echo "== Quota check (RUN_AUDIT=true) =="
    cmd_audit
  fi
  if [[ "${AUTO_CONTINUE}" != "true" ]]; then
    read -r -p "Continue with terraform apply and deploy? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || {
      echo "Aborted. Run: ./dev-lifecycle.sh setup"
      exit 0
    }
  fi
  cmd_setup
}

main() {
  local cmd="${1:-help}"
  if [[ "${cmd}" != "help" && "${cmd}" != "-h" && "${cmd}" != "--help" ]]; then
    init_logging "${cmd}"
  fi
  shift || true
  case "${cmd}" in
    audit) cmd_audit "$@" ;;
    teardown) cmd_teardown "$@" ;;
    setup) cmd_setup "$@" ;;
    reset) cmd_reset "$@" ;;
    terraform-apply|terraform) cmd_terraform_apply "$@" ;;
    secrets) cmd_secrets "$@" ;;
    deploy) cmd_deploy "$@" ;;
    verify) cmd_verify "$@" ;;
    firestore-indexes|firestore) cmd_firestore_indexes "$@" ;;
    gateway-info|gateway) cmd_gateway_info "$@" ;;
    frontend) cmd_frontend "$@" ;;
    help|-h|--help) usage ;;
    *)
      echo "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
