#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"

if [[ -f "${ENV_FILE}" ]]; then source "${ENV_FILE}"; else echo "Missing gcp.env"; exit 1; fi

required=(PROJECT_ID REGION FRONTEND_DOMAIN BACKEND_DOMAIN BACKEND_SERVICE)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then echo "Missing ${key}"; exit 1; fi
done

gcloud config set project "${PROJECT_ID}"
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")

BUCKET_NAME="${PROJECT_ID}-frontend-bucket"
LB_NAME="tripplanning-lb"
FRONTEND_BACKEND_SERVICE="tripplanning-frontend-backend"
BACKEND_NEG="tripplanning-backend-neg"
BACKEND_BACKEND_SERVICE="tripplanning-api-backend"

echo "1. Creating Cloud Storage bucket for frontend..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="EU" --uniform-bucket-level-access
  gcloud storage buckets update "gs://${BUCKET_NAME}" --web-main-page-suffix=index.html --web-error-page=index.html
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="allUsers" --role="roles/storage.objectViewer"
fi

echo "2. Creating Serverless NEG for Cloud Run Backend..."
if ! gcloud compute network-endpoint-groups describe "${BACKEND_NEG}" --region="${REGION}" >/dev/null 2>&1; then
  gcloud compute network-endpoint-groups create "${BACKEND_NEG}" \
    --region="${REGION}" \
    --network-endpoint-type=serverless  \
    --cloud-run-service="${BACKEND_SERVICE}"
fi

echo "3. Creating Backend Services..."
# Frontend Bucket Backend Service with CDN
if ! gcloud compute backend-buckets describe "${FRONTEND_BACKEND_SERVICE}" >/dev/null 2>&1; then
  gcloud compute backend-buckets create "${FRONTEND_BACKEND_SERVICE}" \
    --gcs-bucket-name="${BUCKET_NAME}" --enable-cdn
fi

# Cloud Run Backend Service
if ! gcloud compute backend-services describe "${BACKEND_BACKEND_SERVICE}" --global >/dev/null 2>&1; then
  gcloud compute backend-services create "${BACKEND_BACKEND_SERVICE}" --global --load-balancing-scheme=EXTERNAL
  gcloud compute backend-services add-backend "${BACKEND_BACKEND_SERVICE}" --global \
    --network-endpoint-group="${BACKEND_NEG}" --network-endpoint-group-region="${REGION}"
fi

echo "4. Creating URL Map (Routing rules)..."
cat <<EOF > url-map.yaml
name: ${LB_NAME}
defaultService: global/backendBuckets/${FRONTEND_BACKEND_SERVICE}
hostRules:
- hosts:
  - "${FRONTEND_DOMAIN}"
  pathMatcher: path-matcher-frontend
- hosts:
  - "${BACKEND_DOMAIN}"
  pathMatcher: path-matcher-backend
pathMatchers:
- defaultService: global/backendBuckets/${FRONTEND_BACKEND_SERVICE}
  name: path-matcher-frontend
- defaultService: global/backendServices/${BACKEND_BACKEND_SERVICE}
  name: path-matcher-backend
EOF

if ! gcloud compute url-maps describe "${LB_NAME}" >/dev/null 2>&1; then
  gcloud compute url-maps import "${LB_NAME}" --source=url-map.yaml --global
else
  gcloud compute url-maps import "${LB_NAME}" --source=url-map.yaml --global
fi
rm url-map.yaml

echo "5. Creating SSL Certificates (Google Managed)..."
if ! gcloud compute ssl-certificates describe "tripplanning-certs" >/dev/null 2>&1; then
  gcloud compute ssl-certificates create "tripplanning-certs" \
    --domains="${FRONTEND_DOMAIN},${BACKEND_DOMAIN}" --global
fi

echo "6. Creating HTTP/HTTPS Proxies and Forwarding Rules..."
if ! gcloud compute target-https-proxies describe "${LB_NAME}-https-proxy" >/dev/null 2>&1; then
  gcloud compute target-https-proxies create "${LB_NAME}-https-proxy" \
    --url-map="${LB_NAME}" --ssl-certificates="tripplanning-certs"
fi

if ! gcloud compute forwarding-rules describe "${LB_NAME}-https-rule" --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create "${LB_NAME}-https-rule" \
    --load-balancing-scheme=EXTERNAL \
    --network-tier=PREMIUM \
    --target-https-proxy="${LB_NAME}-https-proxy" \
    --global \
    --ports=443
fi

IP_ADDRESS=$(gcloud compute forwarding-rules describe "${LB_NAME}-https-rule" --global --format="value(IPAddress)")

echo "======================================================="
echo "Load Balancer Setup Complete!"
echo "Bucket Name: ${BUCKET_NAME}"
echo "Load Balancer IP: ${IP_ADDRESS}"
echo "IMPORTANT: Update your DNS A records for ${FRONTEND_DOMAIN} and ${BACKEND_DOMAIN} to point to ${IP_ADDRESS}"
echo "The Google Managed SSL Certificate can take 30-60 minutes to provision after DNS is updated."
echo "======================================================="
