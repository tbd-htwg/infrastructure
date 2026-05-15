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

echo "== Maven package =="
(cd "${BACKEND}" && mvn -q -pl tripplanning-trip-service,tripplanning-social-service -am package -DskipTests)

echo "== Docker build & push =="
gcloud config set project "${PROJECT}" >/dev/null
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

(cd "${BACKEND}" && docker build --build-arg SERVICE=trip -t "${AR}/tripplanning-trip-service:${TAG}" .)
(cd "${BACKEND}" && docker build --build-arg SERVICE=social -t "${AR}/tripplanning-social-service:${TAG}" .)
docker push "${AR}/tripplanning-trip-service:${TAG}"
docker push "${AR}/tripplanning-social-service:${TAG}"

echo "== kubectl context =="
gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT}"

echo "== App tenant (kubectl only; no Flux / cert-manager / ESO) =="
kubectl apply -k "${ROOT}/gitops/tenants/tripplanning"

echo "== Secrets (from Secret Manager via bootstrap script) =="
"${ROOT}/scripts/bootstrap-k8s-secrets.sh"

# kubelet pulls images with the node SA (Autopilot default compute SA)
PROJECT_NUM="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.reader" \
  --condition=None >/dev/null 2>&1 || true

echo "== Rollout =="
kubectl rollout restart deployment/trip-service deployment/social-service -n tripplanning 2>/dev/null || true
kubectl get pods -n tripplanning -w
