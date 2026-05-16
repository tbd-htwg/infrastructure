#!/usr/bin/env bash
# Build backend images, push to Artifact Registry, apply GitOps tenant manifests.
# Prefer: docs/gettingstarted/dev-lifecycle.sh deploy (keep in sync with gettingstarted/README.md §6).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
BACKEND="${REPO_ROOT}/backend"
PROJECT="${GOOGLE_PROJECT:-milestone2-tbd-cad}"
REGION="${GOOGLE_REGION:-europe-west1}"
CLUSTER="${GKE_CLUSTER:-tripplanning-gke}"
TAG="${IMAGE_TAG:-dev}"
AR="${REGION}-docker.pkg.dev/${PROJECT}/tripplanning"

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

command -v kubectl >/dev/null 2>&1 || {
  echo "ERROR: kubectl not found (see docs/gettingstarted README §0)"
  exit 1
}

echo "== Maven package =="
(cd "${BACKEND}" && mvn -q -pl tripplanning-trip-service,tripplanning-social-service,tripplanning-external-info-service -am package -DskipTests)

echo "== Docker build & push =="
gcloud config set project "${PROJECT}" >/dev/null
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

(cd "${BACKEND}" && docker build --build-arg SERVICE=trip -t "${AR}/tripplanning-trip-service:${TAG}" .)
(cd "${BACKEND}" && docker build --build-arg SERVICE=social -t "${AR}/tripplanning-social-service:${TAG}" .)
(cd "${BACKEND}" && docker build --build-arg SERVICE=external-info -t "${AR}/tripplanning-external-info-service:${TAG}" .)
docker push "${AR}/tripplanning-trip-service:${TAG}"
docker push "${AR}/tripplanning-social-service:${TAG}"
docker push "${AR}/tripplanning-external-info-service:${TAG}"

echo "== kubectl context =="
gcloud config set project "${PROJECT}" >/dev/null
gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}"

echo "== In-cluster dependencies (Redis + Elasticsearch) =="
NS=tripplanning "${ROOT}/scripts/install-k8s-dependencies.sh"

echo "== App tenant (kubectl only; no Flux / cert-manager / ESO) =="
kubectl apply -k "${ROOT}/gitops/tenants/tripplanning"

echo "== Secrets (from Secret Manager via bootstrap script) =="
"${ROOT}/scripts/bootstrap-k8s-secrets.sh"

# Autopilot kubelet pulls with the default compute SA — needs artifactregistry.reader (also in Terraform).
PROJECT_NUM="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.reader" \
  --condition=None >/dev/null 2>&1 || true
echo "Artifact Registry reader granted to ${PROJECT_NUM}-compute@developer.gserviceaccount.com"

echo "== Rollout =="
kubectl rollout restart deployment/trip-service deployment/social-service deployment/external-info-service -n tripplanning 2>/dev/null || true
kubectl get pods -n tripplanning -w
