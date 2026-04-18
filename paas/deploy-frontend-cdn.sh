#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"

if [[ -f "${ENV_FILE}" ]]; then source "${ENV_FILE}"; else echo "Missing gcp.env"; exit 1; fi

required=(PROJECT_ID PAAS_BACKEND_URL)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then echo "Missing ${key}"; exit 1; fi
done

BUCKET_NAME="${PROJECT_ID}-frontend-bucket"
FRONTEND_BACKEND_SERVICE="tripplanning-frontend-backend"

PAAS_API_BASE_URL="${PAAS_BACKEND_URL%/}"
if [[ "${PAAS_API_BASE_URL}" != */api/v2 ]]; then
  PAAS_API_BASE_URL="${PAAS_API_BASE_URL}/api/v2"
fi

gcloud config set project "${PROJECT_ID}"

echo "Building frontend application..."
cd "${REPO_ROOT}/frontend"
npm install
VITE_API_BASE_URL="${PAAS_API_BASE_URL}" npm run build

echo "Uploading files to Cloud Storage Bucket (gs://${BUCKET_NAME})..."
gcloud storage rsync dist "gs://${BUCKET_NAME}" --recursive

echo "Invalidating Cloud CDN Cache..."
gcloud compute backend-buckets invalidate-cache "${FRONTEND_BACKEND_SERVICE}" --path="/*"

echo "Frontend deploy completed."
