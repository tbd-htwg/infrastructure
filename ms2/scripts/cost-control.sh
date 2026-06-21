#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-project-f7f74d87-072b-4e92-9c6}"
REGION="${GCP_REGION:-europe-west1}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-tripplanning-gke}"

usage() {
  cat <<'EOF'
Usage: ./scripts/cost-control.sh stop|start|status

stop    Suspend MS2 GitOps workloads, scale application workloads to zero,
        and stop all tripplanning Cloud SQL instances.
start   Start Cloud SQL, resume GitOps, and restore desired workloads.
status  Show Cloud SQL, Flux, HelmRelease, and application workload status.

This preserves databases, disks, buckets, load balancers, and Terraform state.
It does not delete the GKE control plane or networking resources.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

cluster_exists() {
  gcloud container clusters describe "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}" >/dev/null 2>&1
}

connect_cluster() {
  gcloud container clusters get-credentials "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}" >/dev/null
}

sql_instances() {
  gcloud sql instances list \
    --project "${PROJECT_ID}" \
    --filter='name~^tripplanning-' \
    --format='value(name)'
}

set_sql_activation_policy() {
  local policy="$1"
  local instance
  while read -r instance; do
    [[ -n "${instance}" ]] || continue
    echo "Setting Cloud SQL ${instance} activation policy to ${policy}..."
    gcloud sql instances patch "${instance}" \
      --project "${PROJECT_ID}" \
      --activation-policy="${policy}" \
      --quiet
  done < <(sql_instances)
}

suspend_flux_resource() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  kubectl -n "${namespace}" annotate "${kind}/${name}" \
    kustomize.toolkit.fluxcd.io/reconcile=disabled \
    --overwrite >/dev/null
  kubectl -n "${namespace}" patch "${kind}/${name}" \
    --type=merge \
    -p '{"spec":{"suspend":true}}' >/dev/null
}

resume_flux_resource() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  kubectl -n "${namespace}" patch "${kind}/${name}" \
    --type=merge \
    -p '{"spec":{"suspend":false}}' >/dev/null
  kubectl -n "${namespace}" annotate "${kind}/${name}" \
    kustomize.toolkit.fluxcd.io/reconcile- >/dev/null 2>&1 || true
  kubectl -n "${namespace}" annotate "${kind}/${name}" \
    "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
    --overwrite >/dev/null
}

stop_resources() {
  if cluster_exists; then
    connect_cluster

    for name in platform-workloads tenants; do
      if kubectl -n flux-system get "kustomization/${name}" >/dev/null 2>&1; then
        suspend_flux_resource kustomization flux-system "${name}"
      fi
    done

    while read -r namespace name; do
      [[ -n "${namespace}" && -n "${name}" ]] || continue
      suspend_flux_resource helmrelease "${namespace}" "${name}"
    done < <(
      kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'
    )

    mapfile -t namespaces < <(
      kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' |
        awk '/^tripplanning-/'
    )
    for namespace in "${namespaces[@]}"; do
      mapfile -t workloads < <(
        kubectl -n "${namespace}" get deployment,statefulset -o name 2>/dev/null || true
      )
      if ((${#workloads[@]})); then
        kubectl -n "${namespace}" scale "${workloads[@]}" --replicas=0
      fi
    done
  else
    echo "GKE cluster ${CLUSTER_NAME} does not exist; skipping Kubernetes workloads."
  fi

  set_sql_activation_policy NEVER
  echo "MS2 application workloads and Cloud SQL instances are stopped."
}

start_resources() {
  set_sql_activation_policy ALWAYS

  if ! cluster_exists; then
    echo "GKE cluster ${CLUSTER_NAME} does not exist." >&2
    echo "Recreate it with: terraform -chdir=ms2/terraform/envs/dev apply" >&2
    exit 1
  fi

  connect_cluster
  while read -r namespace name; do
    [[ -n "${namespace}" && -n "${name}" ]] || continue
    resume_flux_resource helmrelease "${namespace}" "${name}"
  done < <(
    kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces \
      -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'
  )

  for name in platform-workloads tenants; do
    if kubectl -n flux-system get "kustomization/${name}" >/dev/null 2>&1; then
      resume_flux_resource kustomization flux-system "${name}"
    fi
  done

  echo "Cloud SQL is starting and Flux has been asked to restore MS2 workloads."
}

show_status() {
  echo "Cloud SQL:"
  gcloud sql instances list \
    --project "${PROJECT_ID}" \
    --filter='name~^tripplanning-' \
    --format='table(name,state,settings.activationPolicy,region)'

  if cluster_exists; then
    connect_cluster
    echo
    echo "Flux:"
    kubectl -n flux-system get kustomizations
    echo
    echo "Helm releases:"
    kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces
    echo
    echo "MS2 workloads:"
    kubectl get deployment,statefulset --all-namespaces |
      awk 'NR == 1 || $1 ~ /^tripplanning-/'
  else
    echo
    echo "GKE cluster ${CLUSTER_NAME}: absent"
  fi
}

require_command gcloud
require_command kubectl

case "${1:-}" in
  stop) stop_resources ;;
  start) start_resources ;;
  status) show_status ;;
  *) usage; exit 2 ;;
esac
