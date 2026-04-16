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
  BACKEND_SERVICE
  RUN_SA_NAME
  DB_INSTANCE
  DB_NAME
  DB_USER
  DB_PASSWORD_SECRET
  CORS_ALLOWED_ORIGINS
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

RUN_SA_EMAIL="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CONNECTION_NAME="$(gcloud sql instances describe "${DB_INSTANCE}" --format='value(connectionName)')"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/tripplanning-backend:${IMAGE_TAG}"

############################################################################
# BUILD AND PUSH CONTAINER IMAGE
############################################################################

gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo "Building backend image: ${IMAGE_URI}"
docker build -t "${IMAGE_URI}" "${REPO_ROOT}/backend"
docker push "${IMAGE_URI}"

############################################################################
# DEPLOY TO CLOUD RUN
############################################################################

echo "Deploying Cloud Run service: ${BACKEND_SERVICE}"
gcloud run deploy "${BACKEND_SERVICE}" \
  --image="${IMAGE_URI}" \
  --region="${REGION}" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --service-account="${RUN_SA_EMAIL}" \
  --set-cloudsql-instances="${CONNECTION_NAME}" \
  --set-env-vars="^@^SPRING_DATASOURCE_URL=jdbc:postgresql:///${DB_NAME}?socketFactory=com.google.cloud.sql.postgres.SocketFactory&cloudSqlInstance=${CONNECTION_NAME}@SPRING_DATASOURCE_USERNAME=${DB_USER}@SPRING_DATASOURCE_DRIVER_CLASS_NAME=org.postgresql.Driver@CORS_ALLOWED_ORIGINS=${CORS_ALLOWED_ORIGINS}" \
  --set-secrets="SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD_SECRET}:latest"

echo "Deploy completed."
