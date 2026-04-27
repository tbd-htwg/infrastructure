#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"

if [[ $# -ge 1 ]]; then
  ENV_FILE="$1"
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  echo "Usage: bash plan-service-accounts.sh [path-to-env-file]" >&2
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

ENABLE_IDENTITY_ADMIN_SA="${ENABLE_IDENTITY_ADMIN_SA:-true}"
ENABLE_FIRESTORE_MIGRATOR_SA="${ENABLE_FIRESTORE_MIGRATOR_SA:-false}"

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"

if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "Could not read project ${PROJECT_ID}. Check gcloud auth and project id." >&2
  exit 1
fi

cat <<EOF
Phase 1 Service Account Plan
============================
Project ID: ${PROJECT_ID}
Project Number: ${PROJECT_NUMBER}
Environment: ${ENVIRONMENT}
App Prefix: ${APP_PREFIX}

Service Accounts
----------------
Backend runtime:  ${BACKEND_RUNTIME_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com
Backend deployer: ${BACKEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com
Frontend deployer:${FRONTEND_DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com
EOF

if [[ "${ENABLE_IDENTITY_ADMIN_SA}" == "true" ]]; then
  echo "Identity admin:   ${IDENTITY_ADMIN_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
fi

if [[ "${ENABLE_FIRESTORE_MIGRATOR_SA}" == "true" ]]; then
  echo "Firestore migrator:${FIRESTORE_MIGRATOR_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
fi

cat <<EOF

Planned Roles
-------------
Backend runtime:
  - roles/cloudsql.client (project)
  - roles/datastore.user (project)
  - roles/secretmanager.secretAccessor (secret-level)

Backend deployer:
  - roles/run.admin (project)
  - roles/artifactregistry.writer (project or repository-level)
  - roles/iam.serviceAccountUser (on backend runtime SA)

Frontend deployer:
  - roles/storage.objectAdmin (frontend bucket only)
  - custom role with compute.urlMaps.invalidateCache (project)
EOF

if [[ "${ENABLE_IDENTITY_ADMIN_SA}" == "true" ]]; then
  cat <<EOF

Identity admin:
  - roles/identitytoolkit.admin (project)
EOF
fi

if [[ "${ENABLE_FIRESTORE_MIGRATOR_SA}" == "true" ]]; then
  cat <<EOF

Firestore migrator:
  - roles/datastore.indexAdmin (project)
EOF
fi

cat <<EOF

Expected env variables for Phase 2 script
-----------------------------------------
ENVIRONMENT=${ENVIRONMENT}
APP_PREFIX=${APP_PREFIX}
FRONTEND_BUCKET_NAME=<optional override; otherwise derived from BACKEND_SERVICE>
DB_PASSWORD_SECRET=<recommended secret to bind backend runtime>
OPTIONAL_SECRET_NAMES=<comma-separated additional secret ids>
ARTIFACT_REPO=<optional; if set with REGION grants repo-level writer>

Next:
  bash apply-service-accounts.sh --env-file "${ENV_FILE}" --dry-run
EOF
