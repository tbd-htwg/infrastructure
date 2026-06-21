#!/usr/bin/env bash
set -euo pipefail



# #Delete the cluster
# gcloud container clusters delete tripplanning-gke \
#   --region europe-west1 \
#   --project "$PROJECT"

PROJECT="${GCP_PROJECT_ID:-project-f7f74d87-072b-4e92-9c6}"
REGION="europe-west1"
CLUSTER="tripplanning-gke"
REPO_OWNER="tbd-htwg"
REPO_NAME="infrastructure"
REPO_BRANCH="main"
REPO_PATH="ms2/gitops/clusters/dev"

gcloud container clusters delete "$CLUSTER" \
  --region "$REGION" \
  --project "$PROJECT" \
  --quiet

cd /home/htwg/cloud-app-dev/infrastructure/ms2/terraform/envs/dev
terraform apply -auto-approve

gcloud container clusters get-credentials "$CLUSTER" \
  --region "$REGION" \
  --project "$PROJECT"

flux bootstrap github \
  --owner="$REPO_OWNER" \
  --repository="$REPO_NAME" \
  --branch="$REPO_BRANCH" \
  --path="$REPO_PATH" \
  --token-auth
