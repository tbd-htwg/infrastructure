#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 gcp-stag.env"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$1" = /* ]]; then
  ENV_FILE="$1"
else
  ENV_FILE="${SCRIPT_DIR}/$1"
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: Environment file ${ENV_FILE} not found!"
  exit 1
fi

source "${ENV_FILE}"

required=(PROJECT_ID REGION BACKEND_SERVICE DB_INSTANCE RUN_SA_NAME DB_PASSWORD_SECRET)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then echo "Missing ${key} in ${ENV_FILE}"; exit 1; fi
done

echo "=========================================================================="
echo "🧨 WARNING: DESTRUCTIVE ACTION 🧨"
echo "You are about to delete the following GCP resources for project: ${PROJECT_ID}"
echo "- Cloud Run Service: ${BACKEND_SERVICE}"
echo "- Cloud SQL Instance: ${DB_INSTANCE}"
echo "- All associated Load Balancers, Certificates, Buckets, NEGs, and Secrets"
echo "=========================================================================="
read -p "Are you absolutely sure you want to permanently delete this environment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Teardown aborted."
    exit 0
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

# Derive exact resource names used in the setup scripts
APP_PREFIX="${BACKEND_SERVICE%-backend}"

if [ "$APP_PREFIX" = "tripplanning" ]; then
  BUCKET_NAME="${PROJECT_ID}-frontend-bucket"
else
  BUCKET_NAME="${PROJECT_ID}-${APP_PREFIX}-frontend"
fi

LB_NAME="${APP_PREFIX}-lb"
FRONTEND_BACKEND_SERVICE="${APP_PREFIX}-frontend-backend"
BACKEND_NEG="${APP_PREFIX}-neg"
BACKEND_BACKEND_SERVICE="${APP_PREFIX}-api-backend"
CERT_NAME="${APP_PREFIX}-certs"
RUN_SA_EMAIL="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "1. Deleting Load Balancer Forwarding Rules..."
gcloud compute forwarding-rules delete "${LB_NAME}-https-rule" --global --quiet || echo "Forwarding rule not found or already deleted."

echo "2. Deleting Target HTTPS Proxy..."
gcloud compute target-https-proxies delete "${LB_NAME}-https-proxy" --quiet || echo "HTTPS proxy not found or already deleted."

echo "3. Deleting SSL Certificates..."
gcloud compute ssl-certificates delete "${CERT_NAME}" --global --quiet || echo "SSL certificate not found or already deleted."

echo "4. Deleting URL Map (Routing rules)..."
gcloud compute url-maps delete "${LB_NAME}" --global --quiet || echo "URL map not found or already deleted."

echo "5. Deleting Backend Services & Buckets..."
gcloud compute backend-services delete "${BACKEND_BACKEND_SERVICE}" --global --quiet || echo "Backend service not found or already deleted."
gcloud compute backend-buckets delete "${FRONTEND_BACKEND_SERVICE}" --quiet || echo "Backend bucket not found or already deleted."

echo "6. Deleting Serverless NEG..."
gcloud compute network-endpoint-groups delete "${BACKEND_NEG}" --region="${REGION}" --quiet || echo "Serverless NEG not found or already deleted."

echo "7. Deleting Frontend Cloud Storage Bucket..."
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  gcloud storage rm --recursive "gs://${BUCKET_NAME}/**" --quiet || true
  gcloud storage buckets delete "gs://${BUCKET_NAME}" --quiet || echo "Bucket could not be deleted."
else
  echo "Bucket not found or already deleted."
fi

echo "8. Deleting Cloud Run Backend Service..."
gcloud run services delete "${BACKEND_SERVICE}" --region="${REGION}" --quiet || echo "Cloud Run service not found or already deleted."

if [[ -n "${FRONTEND_SERVICE:-}" ]]; then
  echo "8b. Deleting Cloud Run Frontend Service..."
  gcloud run services delete "${FRONTEND_SERVICE}" --region="${REGION}" --quiet || echo "Frontend Cloud Run service not found or already deleted."
fi

echo "9. Deleting Cloud SQL Instance (This drops all databases & users inside)..."
gcloud sql instances delete "${DB_INSTANCE}" --quiet || echo "Cloud SQL instance not found or already deleted."

echo "10. Deleting Secret Manager Secret..."
gcloud secrets delete "${DB_PASSWORD_SECRET}" --quiet || echo "Secret not found or already deleted."

echo "11. Deleting Service Account..."
gcloud iam service-accounts delete "${RUN_SA_EMAIL}" --quiet || echo "Service account not found or already deleted."

echo "======================================================="
echo "Teardown of environment ${APP_PREFIX} completed!"
if [[ -n "${ARTIFACT_REPO:-}" ]]; then
  echo "Note: The Artifact Registry repository (${ARTIFACT_REPO}) was NOT deleted as it might be shared across environments."
else
  echo "Note: Artifact Registry repository was not deleted (ARTIFACT_REPO not set in env file)."
fi
echo "======================================================="
