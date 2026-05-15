#!/usr/bin/env bash
# Create Kubernetes secrets in tripplanning namespace from GCP Secret Manager
# (use when External Secrets Operator is not ready yet).
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
NS="${K8S_NAMESPACE:-tripplanning}"

fetch_secret() {
  gcloud secrets versions access latest --secret="$1" --project="$PROJECT" 2>/dev/null || echo ""
}

echo "Project: ${PROJECT}  Namespace: ${NS}"

kubectl get namespace "${NS}" >/dev/null 2>&1 || kubectl create namespace "${NS}"

DB_PASS="$(fetch_secret tripplanning-db-password)"
JWT="$(fetch_secret tripplanning-auth-jwt-secret)"
INTERNAL="$(fetch_secret tripplanning-internal-secret)"
ES_PASS="$(fetch_secret tbd-es-gateway-elastic-password)"

if [[ -z "${JWT}" ]]; then
  echo "ERROR: tripplanning-auth-jwt-secret has no version in Secret Manager."
  echo "  echo -n 'your-32-byte-minimum-secret' | gcloud secrets versions add tripplanning-auth-jwt-secret --data-file=- --project=${PROJECT}"
  exit 1
fi

kubectl create secret generic trip-service-secrets \
  --namespace="${NS}" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="${DB_PASS}" \
  --from-literal=TRIPPLANNING_AUTH_JWT_SECRET="${JWT}" \
  --from-literal=ELASTICSEARCH_PASSWORD="${ES_PASS}" \
  --from-literal=TRIPPLANNING_INTERNAL_SECRET="${INTERNAL}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic social-service-secrets \
  --namespace="${NS}" \
  --from-literal=TRIPPLANNING_AUTH_JWT_SECRET="${JWT}" \
  --from-literal=TRIPPLANNING_INTERNAL_SECRET="${INTERNAL}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied in ${NS}."
