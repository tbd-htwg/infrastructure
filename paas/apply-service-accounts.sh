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
      echo "Usage: bash apply-service-accounts.sh [--env-file path] [--dry-run] [--yes]" >&2
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
)

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable: ${key}" >&2
    exit 1
  fi
done

APP_PREFIX="${APP_PREFIX:-tripplanning}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${REGION:-europe-west1}"
RUN_DEPLOY_ROLE="${RUN_DEPLOY_ROLE:-roles/run.admin}"
ENABLE_IDENTITY_ADMIN_SA="${ENABLE_IDENTITY_ADMIN_SA:-true}"
ENABLE_FIRESTORE_MIGRATOR_SA="${ENABLE_FIRESTORE_MIGRATOR_SA:-false}"
ENABLE_CUSTOM_CDN_INVALIDATOR_ROLE="${ENABLE_CUSTOM_CDN_INVALIDATOR_ROLE:-true}"
SKIP_MISSING_SECRET_BINDINGS="${SKIP_MISSING_SECRET_BINDINGS:-true}"
SKIP_MISSING_BUCKET_BINDING="${SKIP_MISSING_BUCKET_BINDING:-true}"

if [[ "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ]]; then
  echo "ENVIRONMENT must be dev or prod (current: ${ENVIRONMENT})." >&2
  exit 1
fi

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

BACKEND_RUNTIME_SA_ID="$(normalize_sa_id "${BACKEND_RUNTIME_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-be-rt}")"
BACKEND_DEPLOYER_SA_ID="$(normalize_sa_id "${BACKEND_DEPLOYER_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-be-deploy}")"
FRONTEND_DEPLOYER_SA_ID="$(normalize_sa_id "${FRONTEND_DEPLOYER_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-fe-deploy}")"
IDENTITY_ADMIN_SA_ID="$(normalize_sa_id "${IDENTITY_ADMIN_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-id-admin}")"
FIRESTORE_MIGRATOR_SA_ID="$(normalize_sa_id "${FIRESTORE_MIGRATOR_SA_ID:-${APP_PREFIX}-${ENVIRONMENT}-fs-migr}")"
CUSTOM_CDN_ROLE_ID="${CUSTOM_CDN_ROLE_ID:-${APP_PREFIX}FrontendCdnInvalidator}"

BACKEND_RUNTIME_SA_EMAIL="${BACKEND_RUNTIME_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
BACKEND_DEPLOYER_SA_EMAIL="${BACKEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
FRONTEND_DEPLOYER_SA_EMAIL="${FRONTEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
IDENTITY_ADMIN_SA_EMAIL="${IDENTITY_ADMIN_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
FIRESTORE_MIGRATOR_SA_EMAIL="${FIRESTORE_MIGRATOR_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# Runtime SA used by deploy pipelines (can still be legacy RUN_SA_NAME during migration).
DEPLOY_RUNTIME_SA_EMAIL="${GCP_RUN_SA_EMAIL:-}"
if [[ -z "${DEPLOY_RUNTIME_SA_EMAIL}" && -n "${RUN_SA_NAME:-}" ]]; then
  DEPLOY_RUNTIME_SA_EMAIL="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
fi

# Keep compatibility with existing deploy scripts: if no explicit bucket is set,
# derive it from BACKEND_SERVICE naming convention.
if [[ -z "${FRONTEND_BUCKET_NAME:-}" ]]; then
  if [[ -n "${BACKEND_SERVICE:-}" ]]; then
    app_prefix_from_service="${BACKEND_SERVICE%-backend}"
    if [[ "${app_prefix_from_service}" == "tripplanning" ]]; then
      FRONTEND_BUCKET_NAME="${PROJECT_ID}-frontend-bucket"
    else
      FRONTEND_BUCKET_NAME="${PROJECT_ID}-${app_prefix_from_service}-frontend"
    fi
    echo "Derived FRONTEND_BUCKET_NAME=${FRONTEND_BUCKET_NAME} from BACKEND_SERVICE=${BACKEND_SERVICE}"
  else
    echo "Missing FRONTEND_BUCKET_NAME and BACKEND_SERVICE; set one of them in env file." >&2
    exit 1
  fi
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"
if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "Could not read project ${PROJECT_ID}. Check gcloud auth and project id." >&2
  exit 1
fi

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

sa_exists() {
  local email="$1"
  gcloud iam service-accounts describe "${email}" --project="${PROJECT_ID}" >/dev/null 2>&1
}

create_sa_if_missing() {
  local sa_id="$1"
  local display_name="$2"
  local sa_email="${sa_id}@${PROJECT_ID}.iam.gserviceaccount.com"

  if sa_exists "${sa_email}"; then
    echo "Service account exists: ${sa_email}"
    return
  fi

  echo "Creating service account: ${sa_email}"
  run_cmd gcloud iam service-accounts create "${sa_id}" \
    --project="${PROJECT_ID}" \
    --display-name="${display_name}"
}

grant_project_role() {
  local member="$1"
  local role="$2"
  echo "Granting ${role} on project to ${member}"
  run_cmd gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${member}" \
    --role="${role}" \
    --quiet >/dev/null
}

grant_secret_role() {
  local secret_id="$1"
  local member="$2"
  if ! gcloud secrets describe "${secret_id}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    if [[ "${SKIP_MISSING_SECRET_BINDINGS}" == "true" ]]; then
      echo "WARN: Secret ${secret_id} not found. Skipping secret accessor binding for ${member}."
      return
    fi
    echo "ERROR: Secret ${secret_id} not found." >&2
    exit 1
  fi
  echo "Granting roles/secretmanager.secretAccessor on secret ${secret_id} to ${member}"
  run_cmd gcloud secrets add-iam-policy-binding "${secret_id}" \
    --project="${PROJECT_ID}" \
    --member="${member}" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet >/dev/null
}

grant_bucket_role() {
  local bucket="$1"
  local member="$2"
  local role="$3"
  if ! gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    if [[ "${SKIP_MISSING_BUCKET_BINDING}" == "true" ]]; then
      echo "WARN: Bucket gs://${bucket} not found. Skipping ${role} for ${member}."
      return
    fi
    echo "ERROR: Bucket gs://${bucket} not found." >&2
    exit 1
  fi
  echo "Granting ${role} on bucket ${bucket} to ${member}"
  run_cmd gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
    --member="${member}" \
    --role="${role}" >/dev/null
}

grant_sa_user() {
  local target_sa_email="$1"
  local member_sa_email="$2"
  echo "Granting roles/iam.serviceAccountUser on ${target_sa_email} to ${member_sa_email}"
  run_cmd gcloud iam service-accounts add-iam-policy-binding "${target_sa_email}" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${member_sa_email}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet >/dev/null
}

create_or_update_custom_cdn_role() {
  local role_id="$1"
  local title="${APP_PREFIX} Frontend CDN Invalidator"
  local description="Invalidate CDN cache and read URL maps for frontend deploy pipeline"
  local perms="compute.urlMaps.get,compute.urlMaps.invalidateCache"

  if gcloud iam roles describe "${role_id}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Updating custom role ${role_id}"
    run_cmd gcloud iam roles update "${role_id}" \
      --project="${PROJECT_ID}" \
      --title="${title}" \
      --description="${description}" \
      --permissions="${perms}" \
      --stage="GA" \
      --quiet >/dev/null
  else
    echo "Creating custom role ${role_id}"
    run_cmd gcloud iam roles create "${role_id}" \
      --project="${PROJECT_ID}" \
      --title="${title}" \
      --description="${description}" \
      --permissions="${perms}" \
      --stage="GA" \
      --quiet >/dev/null
  fi
}

echo "Applying service-account and IAM setup"
echo "Project: ${PROJECT_ID}"
echo "Environment: ${ENVIRONMENT}"
echo "Dry run: ${DRY_RUN}"

cat <<EOF

Service accounts:
- ${BACKEND_RUNTIME_SA_EMAIL}
- ${BACKEND_DEPLOYER_SA_EMAIL}
- ${FRONTEND_DEPLOYER_SA_EMAIL}
EOF

if [[ "${ENABLE_IDENTITY_ADMIN_SA}" == "true" ]]; then
  echo "- ${IDENTITY_ADMIN_SA_EMAIL}"
fi

if [[ "${ENABLE_FIRESTORE_MIGRATOR_SA}" == "true" ]]; then
  echo "- ${FIRESTORE_MIGRATOR_SA_EMAIL}"
fi

if [[ "${AUTO_APPROVE}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Continue applying IAM changes? [y/N] " answer
  if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# Create service accounts.
create_sa_if_missing "${BACKEND_RUNTIME_SA_ID}" "${APP_PREFIX} ${ENVIRONMENT} backend runtime"
create_sa_if_missing "${BACKEND_DEPLOYER_SA_ID}" "${APP_PREFIX} ${ENVIRONMENT} backend deployer"
create_sa_if_missing "${FRONTEND_DEPLOYER_SA_ID}" "${APP_PREFIX} ${ENVIRONMENT} frontend deployer"

if [[ "${ENABLE_IDENTITY_ADMIN_SA}" == "true" ]]; then
  create_sa_if_missing "${IDENTITY_ADMIN_SA_ID}" "${APP_PREFIX} ${ENVIRONMENT} identity admin"
fi

if [[ "${ENABLE_FIRESTORE_MIGRATOR_SA}" == "true" ]]; then
  create_sa_if_missing "${FIRESTORE_MIGRATOR_SA_ID}" "${APP_PREFIX} ${ENVIRONMENT} firestore migrator"
fi

# Backend runtime role bindings.
grant_project_role "serviceAccount:${BACKEND_RUNTIME_SA_EMAIL}" "roles/cloudsql.client"
grant_project_role "serviceAccount:${BACKEND_RUNTIME_SA_EMAIL}" "roles/datastore.user"

if [[ -n "${DB_PASSWORD_SECRET:-}" ]]; then
  grant_secret_role "${DB_PASSWORD_SECRET}" "serviceAccount:${BACKEND_RUNTIME_SA_EMAIL}"
fi

IFS=',' read -ra EXTRA_SECRETS <<< "${OPTIONAL_SECRET_NAMES:-}"
for secret_name in "${EXTRA_SECRETS[@]}"; do
  secret_trimmed="$(echo "${secret_name}" | xargs)"
  if [[ -n "${secret_trimmed}" ]]; then
    grant_secret_role "${secret_trimmed}" "serviceAccount:${BACKEND_RUNTIME_SA_EMAIL}"
  fi
done

# Backend deployer role bindings.
grant_project_role "serviceAccount:${BACKEND_DEPLOYER_SA_EMAIL}" "${RUN_DEPLOY_ROLE}"
grant_sa_user "${BACKEND_RUNTIME_SA_EMAIL}" "${BACKEND_DEPLOYER_SA_EMAIL}"

# Backward-compatible binding for workflows still pointing at legacy runtime SA values.
if [[ -n "${DEPLOY_RUNTIME_SA_EMAIL}" && "${DEPLOY_RUNTIME_SA_EMAIL}" != "${BACKEND_RUNTIME_SA_EMAIL}" ]]; then
  if sa_exists "${DEPLOY_RUNTIME_SA_EMAIL}"; then
    grant_sa_user "${DEPLOY_RUNTIME_SA_EMAIL}" "${BACKEND_DEPLOYER_SA_EMAIL}"
  else
    echo "WARN: DEPLOY runtime SA ${DEPLOY_RUNTIME_SA_EMAIL} does not exist; skipped extra roles/iam.serviceAccountUser binding."
  fi
fi

if [[ -n "${ARTIFACT_REPO:-}" ]]; then
  if gcloud artifacts repositories describe "${ARTIFACT_REPO}" --project="${PROJECT_ID}" --location="${REGION}" >/dev/null 2>&1; then
    echo "Granting Artifact Registry writer on repository ${ARTIFACT_REPO}"
    run_cmd gcloud artifacts repositories add-iam-policy-binding "${ARTIFACT_REPO}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --member="serviceAccount:${BACKEND_DEPLOYER_SA_EMAIL}" \
      --role="roles/artifactregistry.writer" \
      --quiet >/dev/null
  else
    echo "WARN: Artifact Registry repo ${ARTIFACT_REPO} not found in ${REGION}. Falling back to project-level writer role."
    grant_project_role "serviceAccount:${BACKEND_DEPLOYER_SA_EMAIL}" "roles/artifactregistry.writer"
  fi
else
  grant_project_role "serviceAccount:${BACKEND_DEPLOYER_SA_EMAIL}" "roles/artifactregistry.writer"
fi

# Frontend deployer role bindings (bucket + CDN invalidation).
grant_bucket_role "${FRONTEND_BUCKET_NAME}" "serviceAccount:${FRONTEND_DEPLOYER_SA_EMAIL}" "roles/storage.objectAdmin"
grant_bucket_role "${FRONTEND_BUCKET_NAME}" "serviceAccount:${FRONTEND_DEPLOYER_SA_EMAIL}" "roles/storage.bucketViewer"

if [[ "${ENABLE_CUSTOM_CDN_INVALIDATOR_ROLE}" == "true" ]]; then
  create_or_update_custom_cdn_role "${CUSTOM_CDN_ROLE_ID}"
  grant_project_role "serviceAccount:${FRONTEND_DEPLOYER_SA_EMAIL}" "projects/${PROJECT_ID}/roles/${CUSTOM_CDN_ROLE_ID}"
else
  echo "Granting fallback roles/compute.loadBalancerAdmin to frontend deployer"
  grant_project_role "serviceAccount:${FRONTEND_DEPLOYER_SA_EMAIL}" "roles/compute.loadBalancerAdmin"
fi

# Optional admin/migrator bindings.
if [[ "${ENABLE_IDENTITY_ADMIN_SA}" == "true" ]]; then
  grant_project_role "serviceAccount:${IDENTITY_ADMIN_SA_EMAIL}" "roles/identitytoolkit.admin"
fi

if [[ "${ENABLE_FIRESTORE_MIGRATOR_SA}" == "true" ]]; then
  grant_project_role "serviceAccount:${FIRESTORE_MIGRATOR_SA_EMAIL}" "roles/datastore.indexAdmin"
fi

cat <<EOF

Completed.

Recommended next checks:
1) gcloud iam service-accounts list --project "${PROJECT_ID}"
2) gcloud run services describe "${BACKEND_SERVICE:-<backend-service>}" --region "${REGION}" --format='value(template.serviceAccount)'
3) gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' --format='table(bindings.role,bindings.members)' --filter='bindings.members:serviceAccount:${APP_PREFIX}-${ENVIRONMENT}'
EOF
