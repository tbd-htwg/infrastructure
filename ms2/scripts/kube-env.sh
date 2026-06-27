#!/usr/bin/env bash
# Source this file to connect kubectl/k9s to the MS2 dev GKE cluster.
# Usage: source infrastructure/ms2/scripts/kube-env.sh

export GCP_PROJECT_ID="${GCP_PROJECT_ID:-tbd-cloudappdev}"
export GCP_REGION="${GCP_REGION:-europe-west1}"
export GKE_CLUSTER_NAME="${GKE_CLUSTER_NAME:-tripplanning-gke}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi

gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
  --region "${GCP_REGION}" \
  --project "${GCP_PROJECT_ID}" >/dev/null

echo "kubectl context: $(kubectl config current-context)"

alias k8s='kubectl'
alias k9s-free='k9s -n tripplanning-free'
alias k9s-standard='k9s -n tripplanning-standard'
alias k9s-system='k9s -n tripplanning-system'
alias k9s-flux='k9s -n flux-system'
alias k8s-watch-free='watch -n2 kubectl get pods,hpa -n tripplanning-free'
alias k8s-status='kubectl get pods,deploy,sts,hpa -A | grep tripplanning'
