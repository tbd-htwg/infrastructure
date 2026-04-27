#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"
DRY_RUN=false
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      AUTO_APPROVE=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: bash setup-github-wif.sh [--env-file path] [--dry-run] [--yes]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

required=(
  PROJECT_ID
  ENVIRONMENT
)

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable: ${key}" >&2
    exit 1
  fi
done

if [[ "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ]]; then
  echo "ENVIRONMENT must be dev or prod (current: ${ENVIRONMENT})." >&2
  exit 1
fi

APP_PREFIX="${APP_PREFIX:-tripplanning}"
GITHUB_OWNER="${GITHUB_OWNER:-tbd-htwg}"
BACKEND_REPO="${BACKEND_REPO:-backend}"
FRONTEND_REPO="${FRONTEND_REPO:-frontend}"
WIF_POOL_ID="${WIF_POOL_ID:-github-actions}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github-oidc}"
DEV_ALLOWED_REFS="${DEV_ALLOWED_REFS:-refs/heads/develop,refs/heads/staging}"
PROD_ALLOWED_REFS="${PROD_ALLOWED_REFS:-refs/heads/main}"
DEV_ALLOWED_GH_ENVS="${DEV_ALLOWED_GH_ENVS:-develop,staging}"
PROD_ALLOWED_GH_ENVS="${PROD_ALLOWED_GH_ENVS:-production}"

normalize_sa_id() {
  local raw="$1"
  local cleaned
  cleaned="$(echo "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ ${#cleaned} -gt 30 ]]; then
    local hash
    hash="$(printf '%s' "${cleaned}" | sha1sum | cut -c1-7)"
    cleaned="${cleaned:0:22}-${hash}"
  fi
  if [[ ${#cleaned} -lt 6 ]]; then
    cleaned="${cleaned}said"
    cleaned="${cleaned:0:6}"
  fi
  echo "${cleaned}"
}

BACKEND_DEPLOYER_SA_ID="$(normalize_sa_id "${BACKEND_DEPLOYER_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-be-deploy}")"
FRONTEND_DEPLOYER_SA_ID="$(normalize_sa_id "${FRONTEND_DEPLOYER_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-fe-deploy}")"
BACKEND_DEPLOYER_SA_EMAIL="${BACKEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
FRONTEND_DEPLOYER_SA_EMAIL="${FRONTEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"
if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "Could not read project ${PROJECT_ID}. Check gcloud auth and project id." >&2
  exit 1
fi

ALLOWED_REFS="${DEV_ALLOWED_REFS}"
if [[ "${ENVIRONMENT}" == "prod" ]]; then
  ALLOWED_REFS="${PROD_ALLOWED_REFS}"
fi

ALLOWED_GH_ENVS="${DEV_ALLOWED_GH_ENVS}"
if [[ "${ENVIRONMENT}" == "prod" ]]; then
  ALLOWED_GH_ENVS="${PROD_ALLOWED_GH_ENVS}"
fi

POOL_FULL_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
PROVIDER_FULL_NAME="${POOL_FULL_NAME}/providers/${WIF_PROVIDER_ID}"

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

ensure_pool() {
  if gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" --project="${PROJECT_ID}" --location="global" >/dev/null 2>&1; then
    echo "Workload Identity Pool exists: ${WIF_POOL_ID}"
  else
    echo "Creating Workload Identity Pool: ${WIF_POOL_ID}"
    run_cmd gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --display-name="GitHub Actions Pool" \
      --description="OIDC trust for GitHub Actions" \
      --quiet >/dev/null
  fi
}

ensure_provider() {
  local mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.repository_owner=assertion.repository_owner"
  local condition="assertion.repository_owner=='${GITHUB_OWNER}'"

  if gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" --project="${PROJECT_ID}" --location="global" --workload-identity-pool="${WIF_POOL_ID}" >/dev/null 2>&1; then
    echo "Updating Workload Identity Provider: ${WIF_PROVIDER_ID}"
    run_cmd gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WIF_POOL_ID}" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${mapping}" \
      --attribute-condition="${condition}" \
      --quiet >/dev/null
  else
    echo "Creating Workload Identity Provider: ${WIF_PROVIDER_ID}"
    run_cmd gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WIF_POOL_ID}" \
      --display-name="GitHub OIDC Provider" \
      --description="OIDC provider for GitHub Actions" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${mapping}" \
      --attribute-condition="${condition}" \
      --quiet >/dev/null
  fi
}

bind_wif_user_for_ref() {
  local sa_email="$1"
  local repo_slug="$2"
  local ref="$3"

  local subject="repo:${repo_slug}:ref:${ref}"
  local member="principal://iam.googleapis.com/${POOL_FULL_NAME}/subject/${subject}"

  echo "Binding roles/iam.workloadIdentityUser on ${sa_email} for ${repo_slug} @ ${ref}"
  run_cmd gcloud iam service-accounts add-iam-policy-binding "${sa_email}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet >/dev/null
}

bind_wif_user_for_environment() {
  local sa_email="$1"
  local repo_slug="$2"
  local gh_env="$3"

  local subject="repo:${repo_slug}:environment:${gh_env}"
  local member="principal://iam.googleapis.com/${POOL_FULL_NAME}/subject/${subject}"

  echo "Binding roles/iam.workloadIdentityUser on ${sa_email} for ${repo_slug} environment ${gh_env}"
  run_cmd gcloud iam service-accounts add-iam-policy-binding "${sa_email}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet >/dev/null
}

echo "Setting up GitHub WIF"
echo "Project: ${PROJECT_ID}"
echo "Environment: ${ENVIRONMENT}"
echo "Pool: ${WIF_POOL_ID}"
echo "Provider: ${WIF_PROVIDER_ID}"
echo "Backend deployer SA: ${BACKEND_DEPLOYER_SA_EMAIL}"
echo "Frontend deployer SA: ${FRONTEND_DEPLOYER_SA_EMAIL}"
echo "Allowed refs: ${ALLOWED_REFS}"
echo "Allowed GitHub environments: ${ALLOWED_GH_ENVS}"

if [[ "${AUTO_APPROVE}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Continue applying WIF changes? [y/N] " answer
  if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

ensure_pool
ensure_provider

IFS=',' read -ra refs <<< "${ALLOWED_REFS}"
for ref in "${refs[@]}"; do
  cleaned_ref="$(echo "${ref}" | xargs)"
  if [[ -z "${cleaned_ref}" ]]; then
    continue
  fi
  bind_wif_user_for_ref "${BACKEND_DEPLOYER_SA_EMAIL}" "${GITHUB_OWNER}/${BACKEND_REPO}" "${cleaned_ref}"
  bind_wif_user_for_ref "${FRONTEND_DEPLOYER_SA_EMAIL}" "${GITHUB_OWNER}/${FRONTEND_REPO}" "${cleaned_ref}"
done

IFS=',' read -ra gh_envs <<< "${ALLOWED_GH_ENVS}"
for gh_env in "${gh_envs[@]}"; do
  cleaned_env="$(echo "${gh_env}" | xargs)"
  if [[ -z "${cleaned_env}" ]]; then
    continue
  fi
  bind_wif_user_for_environment "${BACKEND_DEPLOYER_SA_EMAIL}" "${GITHUB_OWNER}/${BACKEND_REPO}" "${cleaned_env}"
  bind_wif_user_for_environment "${FRONTEND_DEPLOYER_SA_EMAIL}" "${GITHUB_OWNER}/${FRONTEND_REPO}" "${cleaned_env}"
done

cat <<EOF

Completed WIF setup for ${ENVIRONMENT}.

Set these GitHub repository variables:
- GCP_WIF_PROVIDER=${PROVIDER_FULL_NAME}
- Backend repo: GCP_BACKEND_DEPLOYER_SA_EMAIL=${BACKEND_DEPLOYER_SA_EMAIL}
- Frontend repo: GCP_FRONTEND_DEPLOYER_SA_EMAIL=${FRONTEND_DEPLOYER_SA_EMAIL}

After first successful keyless deploy in each environment, remove secret GCP_SA_KEY.
EOF
