#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp-dev.env"
DRY_RUN=false
AUTO_APPROVE=false
ACCESS_LEVEL="write"
BUCKET_NAME=""
SA_ID_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --bucket)
      BUCKET_NAME="$2"
      shift 2
      ;;
    --access)
      ACCESS_LEVEL="$2"
      shift 2
      ;;
    --sa-id)
      SA_ID_OVERRIDE="$2"
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
      echo "Usage: bash create-images-storage-sa.sh [--env-file path] [--bucket name] [--access read|write] [--sa-id id] [--dry-run] [--yes]" >&2
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

PROJECT_ID="${PROJECT_ID:-}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
APP_PREFIX="${APP_PREFIX:-tripplanning}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Missing required variable PROJECT_ID in ${ENV_FILE}" >&2
  exit 1
fi

if [[ "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ]]; then
  echo "ENVIRONMENT must be dev or prod (current: ${ENVIRONMENT})" >&2
  exit 1
fi

if [[ "${ACCESS_LEVEL}" != "read" && "${ACCESS_LEVEL}" != "write" ]]; then
  echo "--access must be read or write (current: ${ACCESS_LEVEL})" >&2
  exit 1
fi

if [[ -z "${BUCKET_NAME}" ]]; then
  BUCKET_NAME="${IMAGES_BUCKET_NAME:-}"
fi

if [[ -z "${BUCKET_NAME}" ]]; then
  echo "Missing bucket name. Provide --bucket or IMAGES_BUCKET_NAME in env file." >&2
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

DEFAULT_SA_ID="${APP_PREFIX}-${ENVIRONMENT}-img-store"
SA_ID="$(normalize_sa_id "${SA_ID_OVERRIDE:-${DEFAULT_SA_ID}}")"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

sa_exists() {
  gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1
}

grant_bucket_role() {
  local role="$1"
  run_cmd gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" >/dev/null
}

if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket not found: gs://${BUCKET_NAME}" >&2
  exit 1
fi

cat <<EOF
Images object-store SA setup
Project: ${PROJECT_ID}
Environment: ${ENVIRONMENT}
Bucket: gs://${BUCKET_NAME}
Service account: ${SA_EMAIL}
Access level: ${ACCESS_LEVEL}
Dry run: ${DRY_RUN}
EOF

if [[ "${AUTO_APPROVE}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Continue applying changes? [y/N] " answer
  if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

if sa_exists; then
  echo "Service account exists: ${SA_EMAIL}"
else
  echo "Creating service account: ${SA_EMAIL}"
  run_cmd gcloud iam service-accounts create "${SA_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="${APP_PREFIX} ${ENVIRONMENT} images object store"
fi

echo "Granting bucket viewer role"
grant_bucket_role "roles/storage.bucketViewer"

if [[ "${ACCESS_LEVEL}" == "write" ]]; then
  echo "Granting object admin role"
  grant_bucket_role "roles/storage.objectAdmin"
else
  echo "Granting object viewer role"
  grant_bucket_role "roles/storage.objectViewer"
fi

cat <<EOF

Done.

Service account created/configured:
${SA_EMAIL}

Next (admin): grant developer impersonation on this SA
gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
  --project=${PROJECT_ID} \
  --member=user:DEVELOPER_EMAIL \
  --role=roles/iam.serviceAccountTokenCreator

Next (developer): use SA impersonation, no JSON key required
gcloud auth login
gcloud config set project ${PROJECT_ID}
gcloud storage ls gs://${BUCKET_NAME} --impersonate-service-account=${SA_EMAIL}
EOF
