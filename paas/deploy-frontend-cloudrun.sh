#!/usr/bin/env bash
set -euo pipefail

############################################################################
# ENVIRONMENT SETUP
############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "Missing ${ENV_FILE}. Copy gcp.env.example to gcp.env and fill it." >&2
  exit 1
fi

required=(
  PROJECT_ID
  REGION
  ARTIFACT_REPO
  FRONTEND_SERVICE
  PAAS_BACKEND_URL
)

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable: ${key}" >&2
    exit 1
  fi
done

############################################################################
# IMAGE BUILD/PUBLISH PARAMETERS
############################################################################

IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/tripplanning-frontend:${IMAGE_TAG}"

############################################################################
# BUILD AND PUSH CONTAINER IMAGE
############################################################################

gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo "Building frontend image: ${IMAGE_URI}"
docker build \
  --build-arg "VITE_API_BASE_URL=${PAAS_BACKEND_URL}" \
  -t "${IMAGE_URI}" \
  "${REPO_ROOT}/frontend"

docker push "${IMAGE_URI}"

############################################################################
# DEPLOY TO CLOUD RUN
############################################################################

echo "Deploying Cloud Run service: ${FRONTEND_SERVICE}"
gcloud run deploy "${FRONTEND_SERVICE}" \
  --image="${IMAGE_URI}" \
  --region="${REGION}" \
  --platform=managed \
  --allow-unauthenticated \
  --port=80

echo "Frontend deploy completed."
