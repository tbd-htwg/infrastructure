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
#   gateway-info       Print Gateway IP + DNS / registrar hint (§9)
#   wire-dns           Wait for Gateway IP, terraform A records (§9)
#   setup-tls          Install cert-manager, wait for TLS cert (§9)
#   post-gateway       wire-dns + setup-tls + gateway-info (default end of setup)
#   frontend           Build and rsync frontend to GCS (§10)
#   setup-bucket-cors  Apply GCS CORS on images bucket (browser PUT/GET to signed URLs)
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
#   TRIP_ROLLOUT_TIMEOUT=600      trip-service only (Elasticsearch warmup; default 600)
#   REDIS_WAIT_TIMEOUT=120        kubectl wait for redis Deployment (install-k8s-dependencies.sh)
#   ES_WAIT_TIMEOUT=600           kubectl wait for elasticsearch pod Ready (scale-up + JVM start)
#   SKIP_ROLLOUT_WAIT=true        Skip rollout wait (script continues immediately)
#   SKIP_TERRAFORM, SKIP_SECRETS, SKIP_DEPLOY, SKIP_VERIFY
#   SKIP_FIRESTORE_INDEXES, SKIP_FRONTEND, SKIP_GATEWAY_INFO, SKIP_GATEWAY_POST
#   SKIP_DNS_WIRE, SKIP_TLS          Post-gateway steps (default: all enabled)
#   GATEWAY_WAIT_TIMEOUT=600        Seconds to wait for Gateway PROGRAMMED + IP
#   CERT_WAIT_TIMEOUT=900             Seconds to wait for Certificate Ready
#   JWT_SECRET, INTERNAL_SECRET  Required for secrets (≥32 chars for JWT)
#   API_HOST, SOCIAL_API_HOST, ACME_EMAIL (Let's Encrypt registration)
#   API_SCHEME=https|http             Public verify scheme (default https unless SKIP_TLS=true)
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
SOCIAL_API_HOST="${SOCIAL_API_HOST:-social.api.k8s.tbd-htwg.de}"
FRONTEND_HOST="${FRONTEND_HOST:-k8s.tbd-htwg.de}"
ACME_EMAIL="${ACME_EMAIL:-platform@tbd-htwg.de}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"
if [[ "${SKIP_TLS:-false}" == "true" ]]; then
  API_SCHEME="${API_SCHEME:-http}"
  VITE_API_BASE_URL="${VITE_API_BASE_URL:-http://${API_HOST}}"
else
  API_SCHEME="${API_SCHEME:-https}"
  VITE_API_BASE_URL="${VITE_API_BASE_URL:-https://${API_HOST}}"
fi
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
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "ERROR: required command not found: $c (see README §0 Prerequisites)"
      exit 1
    }
  done
}

ensure_gke_kubectl_context() {
  gcloud config set project "${PROJECT}" >/dev/null
  export USE_GKE_GCLOUD_AUTH_PLUGIN=True
  gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}"
}

# Point kubectl at GKE for every dev-lifecycle command (except help).
ensure_gke_kubectl_target() {
  local mode="" ctx=""
  if [[ -f "${BACKEND}/.local-dev/state.env" ]]; then
    # shellcheck source=/dev/null
    source "${BACKEND}/.local-dev/state.env"
    mode="${MODE:-}"
  fi
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${mode}" == "local" || "${ctx}" == "minikube" ]]; then
    echo "== kubectl → GKE (${CLUSTER}) =="
    if [[ -x "${BACKEND}/scripts/local-dev.sh" ]]; then
      MINIKUBE_STOP_ON_USE_GKE="${MINIKUBE_STOP_ON_USE_GKE:-true}" \
        "${BACKEND}/scripts/local-dev.sh" use-gke
    else
      ensure_gke_kubectl_context
      mkdir -p "${BACKEND}/.local-dev"
      echo "MODE=gke" >"${BACKEND}/.local-dev/state.env"
    fi
    return 0
  fi
  if gcloud container clusters describe "${CLUSTER}" --region "${REGION}" --project "${PROJECT}" &>/dev/null; then
    ensure_gke_kubectl_context >/dev/null
  fi
}

cmd_prerequisites() {
  require_cmd gcloud kubectl terraform mvn docker jq
  gcloud auth application-default set-quota-project "${PROJECT}" 2>/dev/null \
    || echo "WARN: could not set ADC quota project (run: gcloud auth application-default set-quota-project ${PROJECT})"
  echo "Project: ${PROJECT}  Region: ${REGION}  Cluster: ${CLUSTER}"
  echo "kubectl context: $(kubectl config current-context 2>/dev/null || echo n/a)"
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
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

  echo "== Maven package =="
  (cd "${BACKEND}" && mvn -q -pl tripplanning-trip-service,tripplanning-social-service,tripplanning-external-info-service -am package -DskipTests)

  echo "== Docker build & push =="
  (cd "${BACKEND}" && docker build --build-arg SERVICE=trip -t "${AR}/tripplanning-trip-service:${TAG}" .)
  (cd "${BACKEND}" && docker build --build-arg SERVICE=social -t "${AR}/tripplanning-social-service:${TAG}" .)
  (cd "${BACKEND}" && docker build --build-arg SERVICE=external-info -t "${AR}/tripplanning-external-info-service:${TAG}" .)
  docker push "${AR}/tripplanning-trip-service:${TAG}"
  docker push "${AR}/tripplanning-social-service:${TAG}"
  docker push "${AR}/tripplanning-external-info-service:${TAG}"

  echo "== In-cluster dependencies (Redis + Elasticsearch) =="
  NS=tripplanning \
    REDIS_WAIT_TIMEOUT="${REDIS_WAIT_TIMEOUT:-120}" \
    ES_WAIT_TIMEOUT="${ES_WAIT_TIMEOUT:-600}" \
    "${MS2_ROOT}/scripts/install-k8s-dependencies.sh"

  echo "== kubectl apply tenant =="
  kubectl apply -k "${MS2_ROOT}/gitops/tenants/tripplanning"
  GOOGLE_PROJECT="${PROJECT}" "${MS2_ROOT}/scripts/bootstrap-k8s-secrets.sh"

  ensure_gke_node_artifact_registry_reader

  local timeout="${ROLLOUT_TIMEOUT:-180}"
  local trip_timeout="${TRIP_ROLLOUT_TIMEOUT:-600}"
  # Recreate strategy + sequential restart: dependencies first, trip-service last (needs ES, Redis, social).
  kubectl rollout restart deployment/social-service -n tripplanning 2>/dev/null || true
  if [[ "${SKIP_ROLLOUT_WAIT:-false}" != "true" ]]; then
    echo "Waiting for social-service rollout (max ${timeout}s)..."
    kubectl rollout status deployment/social-service -n tripplanning --timeout="${timeout}s" || {
      echo "WARN: social-service not ready — check: kubectl logs -n tripplanning deployment/social-service --tail=30"
    }
  fi
  kubectl rollout restart deployment/external-info-service -n tripplanning 2>/dev/null || true
  if [[ "${SKIP_ROLLOUT_WAIT:-false}" != "true" ]]; then
    echo "Waiting for external-info-service rollout (max ${timeout}s)..."
    kubectl rollout status deployment/external-info-service -n tripplanning --timeout="${timeout}s" || {
      echo "WARN: external-info-service not ready — check: kubectl logs -n tripplanning deployment/external-info-service --tail=30"
    }
  fi
  kubectl rollout restart deployment/trip-service -n tripplanning 2>/dev/null || true
  if [[ "${SKIP_ROLLOUT_WAIT:-false}" == "true" ]]; then
    echo "Skipping rollout wait (SKIP_ROLLOUT_WAIT=true)."
  else
    echo "Waiting for trip-service rollout (max ${trip_timeout}s; needs Redis + Elasticsearch + social)..."
    if ! kubectl rollout status deployment/trip-service -n tripplanning --timeout="${trip_timeout}s"; then
      echo "ERROR: trip-service not ready — check: kubectl get pods -n tripplanning"
      echo "  Redis/ES: kubectl get pods -n tripplanning -l 'app.kubernetes.io/name in (redis,elasticsearch)'"
      kubectl logs -n tripplanning deployment/trip-service -c trip-service --tail=30 2>/dev/null || true
      exit 1
    fi
  fi
  kubectl get pods -n tripplanning
  cmd_setup_bucket_cors
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

cmd_verify() {
  cmd_prerequisites
  API_HOST="${API_HOST}" API_SCHEME="${API_SCHEME}" "${MS2_ROOT}/scripts/verify-gke-deployment.sh"
}

gateway_programmed() {
  local prog
  prog="$(kubectl get gateway tripplanning-api -n tripplanning \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
  [[ "${prog}" == "True" ]]
}

gateway_ip() {
  kubectl get gateway tripplanning-api -n tripplanning \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true
}

wait_for_gateway() {
  local timeout="${GATEWAY_WAIT_TIMEOUT:-600}" elapsed=0 ip=""
  ensure_gke_kubectl_context >/dev/null 2>&1 || true
  echo "== Waiting for Gateway PROGRAMMED + external IP (max ${timeout}s) ==" >&2
  while (( elapsed < timeout )); do
    if gateway_programmed; then
      ip="$(gateway_ip)"
      if [[ -n "${ip}" ]]; then
        echo "Gateway ready: ${ip}" >&2
        printf '%s' "${ip}"
        return 0
      fi
    fi
    sleep 15
    elapsed=$((elapsed + 15))
    echo "  … still waiting (${elapsed}s)" >&2
    kubectl get gateway tripplanning-api -n tripplanning -o wide 2>/dev/null >&2 || true
  done
  echo "ERROR: Gateway not programmed within ${timeout}s (see: kubectl describe gateway tripplanning-api -n tripplanning)" >&2
  return 1
}

print_registrar_hint() {
  cd "${TF_DIR}"
  echo ""
  echo "=== Registrar (apex domain) ==="
  echo "At your domain registrar set ONLY these nameservers (no A/CNAME records for api.* at the registrar):"
  if terraform output -json parent_dns_zone_name_servers 2>/dev/null | jq -e '. != null and length > 0' >/dev/null; then
    terraform output -json parent_dns_zone_name_servers | jq -r '.[]'
  else
    echo "(parent zone disabled — use child zone NS at registrar for the delegated subdomain)"
    terraform output -json k8s_subdomain_dns_zone_name_servers 2>/dev/null | jq -r '.[]' || true
  fi
  echo ""
  echo "A records for ${API_HOST}, ${SOCIAL_API_HOST}, and ${FRONTEND_HOST} are created in Cloud DNS by wire-dns (terraform gke_gateway_ip)."
  echo "Firebase / Identity Platform: add authorized domains for ${API_HOST} (and frontend host if used)."
  echo "No Cloud Run domain-mapping or Google-managed SSL trust step is required for this GKE + cert-manager path."
}

cmd_wire_dns() {
  cmd_prerequisites
  require_cmd terraform jq
  local ip
  ip="$(wait_for_gateway)" || return 1
  cd "${TF_DIR}"
  if [[ ! -f terraform.tfvars ]]; then
    cp terraform.tfvars.example terraform.tfvars
  fi
  echo "== Terraform: A records → ${ip} =="
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    terraform apply -auto-approve -var="gke_gateway_ip=${ip}"
  else
    terraform apply -var="gke_gateway_ip=${ip}"
  fi
  print_registrar_hint
  echo ""
  echo "Waiting for DNS propagation (up to 120s)..."
  local n=0
  while (( n < 12 )); do
    if dig +short "${API_HOST}" 2>/dev/null | grep -qFx "${ip}" \
      && dig +short "${FRONTEND_HOST}" 2>/dev/null | grep -qFx "${ip}"; then
      echo "DNS OK: ${API_HOST}, ${FRONTEND_HOST} → ${ip}"
      return 0
    fi
    sleep 10
    n=$((n + 1))
  done
  echo "WARN: ${API_HOST} does not resolve to ${ip} yet — ACME may fail until propagation completes."
}

cert_manager_installed() {
  kubectl get deployment cert-manager-webhook -n cert-manager >/dev/null 2>&1
}

# GKE Autopilot blocks leader-election leases in kube-system; cainjector never injects webhook CA without this.
patch_cert_manager_autopilot() {
  local dep
  echo "== Patching cert-manager leader-election namespace for GKE Autopilot =="
  for dep in cert-manager cert-manager-cainjector cert-manager-webhook; do
    kubectl get deployment "${dep}" -n cert-manager -o yaml |
      sed 's/--leader-election-namespace=kube-system/--leader-election-namespace=cert-manager/g' |
      kubectl apply -f -
  done
  kubectl rollout restart deployment/cert-manager-cainjector deployment/cert-manager deployment/cert-manager-webhook \
    -n cert-manager
  kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s
}

webhook_ca_bundle_len() {
  kubectl get validatingwebhookconfiguration cert-manager-webhook \
    -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null | wc -c | tr -d ' '
}

inject_cert_manager_webhook_ca() {
  local ca_b64
  ca_b64="$(kubectl get secret cert-manager-webhook-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
  if [[ -z "${ca_b64}" ]]; then
    return 1
  fi
  echo "== Injecting cert-manager webhook CA from secret (fallback) =="
  kubectl patch validatingwebhookconfiguration cert-manager-webhook --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${ca_b64}\"}]" \
    >/dev/null 2>&1 || true
  kubectl patch mutatingwebhookconfiguration cert-manager-webhook --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${ca_b64}\"}]" \
    >/dev/null 2>&1 || true
}

ensure_gke_node_artifact_registry_reader() {
  local project_num
  project_num="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
  echo "== Ensuring Autopilot node SA can pull from Artifact Registry =="
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${project_num}-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.reader" \
    --condition=None >/dev/null 2>&1 || true
}

wait_for_cert_manager() {
  echo "== Waiting for cert-manager (webhook CA must be injected by cainjector) =="
  kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=300s
  kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
  kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
  local n=0 ca_len
  while (( n < 60 )); do
    ca_len="$(webhook_ca_bundle_len)"
    if [[ "${ca_len:-0}" -gt 10 ]]; then
      echo "cert-manager webhook CA bundle ready."
      sleep 5
      return 0
    fi
    sleep 5
    n=$((n + 1))
  done
  inject_cert_manager_webhook_ca || true
  ca_len="$(webhook_ca_bundle_len)"
  if [[ "${ca_len:-0}" -gt 10 ]]; then
    echo "cert-manager webhook CA bundle ready (manual inject)."
    sleep 5
    return 0
  fi
  echo "WARN: webhook CA bundle not visible yet; will retry applies."
}

kubectl_apply_cert_resources() {
  local issuer="${MS2_ROOT}/gitops/tenants/tripplanning/gateway/cluster-issuer.yaml"
  local cert="${MS2_ROOT}/gitops/tenants/tripplanning/gateway/certificate.yaml"
  local n=0 errf ok
  while (( n < 12 )); do
    errf="$(mktemp)"
    ok=true
    if [[ -n "${ACME_EMAIL}" ]]; then
      sed "s/email: .*/email: ${ACME_EMAIL}/" "${issuer}" | kubectl apply -f - 2>"${errf}" || ok=false
    else
      kubectl apply -f "${issuer}" 2>"${errf}" || ok=false
    fi
    if [[ "${ok}" == "true" ]]; then
      kubectl apply -n tripplanning -f "${cert}" 2>>"${errf}" || ok=false
    fi
    if [[ "${ok}" == "true" ]]; then
      rm -f "${errf}"
      return 0
    fi
    if grep -qE 'webhook\.cert-manager\.io|unknown authority|failed calling webhook' "${errf}" 2>/dev/null; then
      echo "  … cert-manager webhook not trusted yet, retry in 15s (${n}/11)"
      rm -f "${errf}"
      sleep 15
      n=$((n + 1))
      continue
    fi
    cat "${errf}" >&2
    rm -f "${errf}"
    return 1
  done
  echo "ERROR: could not apply ClusterIssuer/Certificate after webhook retries."
  return 1
}

print_tls_diagnostics() {
  local gw_ip api_ip
  gw_ip="$(gateway_ip)"
  api_ip="$(dig +short "${API_HOST}" 2>/dev/null | head -1 || true)"
  echo ""
  echo "== TLS / ACME diagnostics =="
  echo "Gateway IP: ${gw_ip:-<none>}"
  echo "dig ${API_HOST}: ${api_ip:-<no A record>}"
  if [[ -n "${gw_ip}" && -n "${api_ip}" && "${api_ip}" != "${gw_ip}" ]]; then
    echo "WARN: API host does not match Gateway IP — run ./dev-lifecycle.sh wire-dns first."
  fi
  kubectl describe certificate tripplanning-api-tls -n tripplanning 2>/dev/null | tail -25 || true
  kubectl get challenge,order -n tripplanning 2>/dev/null || true
  kubectl describe challenge -n tripplanning 2>/dev/null | tail -40 || true
}

cmd_setup_tls() {
  cmd_prerequisites
  ensure_gke_kubectl_context >/dev/null

  if ! cert_manager_installed; then
    echo "== Installing cert-manager ${CERT_MANAGER_VERSION} =="
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  else
    echo "cert-manager already installed."
  fi
  patch_cert_manager_autopilot
  wait_for_cert_manager
  kubectl_apply_cert_resources

  local gw_ip api_ip
  gw_ip="$(gateway_ip)"
  api_ip="$(dig +short "${API_HOST}" 2>/dev/null | head -1 || true)"
  if [[ -z "${gw_ip}" ]]; then
    echo "WARN: Gateway has no IP yet — ACME HTTP-01 may fail until the Gateway is PROGRAMMED."
  elif [[ -z "${api_ip}" || "${api_ip}" != "${gw_ip}" ]]; then
    echo "WARN: ${API_HOST} does not resolve to Gateway IP ${gw_ip} (got: ${api_ip:-none})."
    echo "      Run ./dev-lifecycle.sh wire-dns and wait for DNS propagation before setup-tls."
  fi

  echo "== Waiting for TLS certificate (max ${CERT_WAIT_TIMEOUT:-900}s) =="
  if kubectl wait --for=condition=Ready "certificate/tripplanning-api-tls" -n tripplanning \
    --timeout="${CERT_WAIT_TIMEOUT:-900}s"; then
    echo "Certificate Ready — enabling HTTPS listeners on Gateway."
    kubectl apply -f "${MS2_ROOT}/gitops/tenants/tripplanning/gateway/gateway-https.yaml"
    echo "Waiting for Gateway to reprogram (30s)..."
    sleep 30
  else
    echo "WARN: certificate not Ready yet."
    print_tls_diagnostics
    return 1
  fi
}

cmd_post_gateway() {
  [[ "${SKIP_DNS_WIRE:-false}" == "true" ]] || cmd_wire_dns
  [[ "${SKIP_TLS:-false}" == "true" ]] || cmd_setup_tls
  [[ "${SKIP_GATEWAY_INFO:-false}" == "true" ]] || cmd_gateway_info
}

cmd_gateway_info() {
  cmd_prerequisites
  ensure_gke_kubectl_context 2>/dev/null || true
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
    echo "DNS: ${API_HOST}, ${SOCIAL_API_HOST}, ${FRONTEND_HOST} → ${IP} (via wire-dns / terraform gke_gateway_ip)"
    echo "Test API: curl -sS ${API_SCHEME}://${API_HOST}/actuator/health/readiness"
    echo "Test UI:  curl -sS -o /dev/null -w '%{http_code}\n' ${API_SCHEME}://${FRONTEND_HOST}/"
    print_registrar_hint
  else
    echo "Gateway IP not ready yet; kubectl describe gateway tripplanning-api -n tripplanning"
  fi
}

cmd_setup_bucket_cors() {
  cmd_prerequisites
  require_cmd gsutil
  local cors_file="${REPO_ROOT}/frontend/doc/image-bucket-cors/cors.json"
  local bucket="${PROJECT}-images-bucket"
  if [[ ! -f "${cors_file}" ]]; then
    echo "ERROR: CORS policy not found: ${cors_file}"
    exit 1
  fi
  echo "== GCS images bucket CORS (signed upload/read from browser) =="
  gsutil cors set "${cors_file}" "gs://${bucket}"
  echo "CORS applied on gs://${bucket}"
}

cmd_frontend() {
  cmd_prerequisites
  require_cmd npm gsutil
  (cd "${FRONTEND}" && npm ci)
  (cd "${FRONTEND}" && VITE_API_BASE_URL="${VITE_API_BASE_URL}" npm run build)
  gsutil -m rsync -r "${FRONTEND}/dist" "gs://${FRONTEND_BUCKET}/"
  echo "Frontend synced to gs://${FRONTEND_BUCKET}/"
  ensure_gke_kubectl_context >/dev/null 2>&1 || true
  if kubectl get deployment frontend -n tripplanning >/dev/null 2>&1; then
    echo "Restarting frontend deployment (re-sync assets from bucket)..."
    kubectl rollout restart deployment/frontend -n tripplanning
    kubectl rollout status deployment/frontend -n tripplanning --timeout="${ROLLOUT_TIMEOUT:-180}s" || \
      echo "WARN: frontend rollout not ready — check: kubectl logs -n tripplanning deployment/frontend -c sync-assets"
  else
    echo "frontend deployment not found yet; run deploy first, then frontend again (or rely on init container on first start)."
  fi
  echo "Public UI: ${API_SCHEME}://${FRONTEND_HOST}/"
}

cmd_setup() {
  echo "== Setup: minimal dev stack in ${PROJECT} =="
  cmd_prerequisites
  [[ "${SKIP_TERRAFORM:-false}" == "true" ]] || cmd_terraform_apply
  [[ "${SKIP_SECRETS:-false}" == "true" ]] || cmd_secrets
  [[ "${SKIP_DEPLOY:-false}" == "true" ]] || cmd_deploy
  [[ "${SKIP_VERIFY:-false}" == "true" ]] || cmd_verify
  [[ "${SKIP_FIRESTORE_INDEXES:-false}" == "true" ]] || cmd_firestore_indexes
  if [[ "${SKIP_GATEWAY_POST:-false}" != "true" ]]; then
    cmd_post_gateway || echo "WARN: post-gateway (DNS/TLS) had errors — see log; fix DNS/certs and re-run: ./dev-lifecycle.sh post-gateway"
  elif [[ "${SKIP_GATEWAY_INFO:-false}" != "true" ]]; then
    cmd_gateway_info
  fi
  [[ "${SKIP_FRONTEND:-false}" == "true" ]] || cmd_frontend
  echo ""
  echo "Setup complete. See README.md §6 (Redis + Elasticsearch) and SSD quota if disks fill."
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
    help|-h|--help) usage ;;
    *)
      ensure_gke_kubectl_target
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
        wire-dns|dns) cmd_wire_dns "$@" ;;
        setup-tls|tls) cmd_setup_tls "$@" ;;
        post-gateway) cmd_post_gateway "$@" ;;
        frontend) cmd_frontend "$@" ;;
        setup-bucket-cors|bucket-cors) cmd_setup_bucket_cors "$@" ;;
        *)
          echo "Unknown command: ${cmd}"
          usage
          exit 1
          ;;
      esac
      ;;
  esac
}

main "$@"
