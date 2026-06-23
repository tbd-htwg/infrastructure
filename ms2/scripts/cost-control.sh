#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-tbd-cloudappdev}"
REGION="${GCP_REGION:-europe-west1}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-tripplanning-gke}"
SQL_WAIT_TIMEOUT_SECONDS="${SQL_WAIT_TIMEOUT_SECONDS:-1800}"
SQL_POLL_INTERVAL_SECONDS="${SQL_POLL_INTERVAL_SECONDS:-15}"

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

wait_for_sql_state() {
  local instance="$1"
  local policy="$2"
  local desired_state
  local state
  local activation_policy
  local elapsed=0

  case "${policy}" in
    ALWAYS) desired_state="RUNNABLE" ;;
    NEVER) desired_state="STOPPED" ;;
    *)
      echo "Unsupported Cloud SQL activation policy: ${policy}" >&2
      return 1
      ;;
  esac

  while ((elapsed < SQL_WAIT_TIMEOUT_SECONDS)); do
    read -r state activation_policy < <(
      gcloud sql instances describe "${instance}" \
        --project "${PROJECT_ID}" \
        --format='value(state,settings.activationPolicy)'
    )

    if [[ "${state}" == "${desired_state}" && "${activation_policy}" == "${policy}" ]]; then
      echo "Cloud SQL ${instance} is ${state} with activation policy ${policy}."
      return 0
    fi

    if [[ "${state}" == "FAILED" || "${state}" == "SUSPENDED" ]]; then
      echo "Cloud SQL ${instance} entered unexpected state ${state}." >&2
      return 1
    fi

    echo "Waiting for Cloud SQL ${instance}: state=${state}, activationPolicy=${activation_policy} (${elapsed}s elapsed)..."
    sleep "${SQL_POLL_INTERVAL_SECONDS}"
    ((elapsed += SQL_POLL_INTERVAL_SECONDS))
  done

  echo "Timed out after ${SQL_WAIT_TIMEOUT_SECONDS}s waiting for Cloud SQL ${instance} to become ${desired_state}." >&2
  echo "Inspect it with: gcloud sql operations list --instance=${instance} --project=${PROJECT_ID}" >&2
  return 1
}

set_sql_activation_policy() {
  local policy="$1"
  local instance
  local current_policy
  local -a instances

  mapfile -t instances < <(sql_instances)
  if ((${#instances[@]} == 0)); then
    echo "No tripplanning Cloud SQL instances found in project ${PROJECT_ID}."
    return
  fi

  for instance in "${instances[@]}"; do
    current_policy="$(
      gcloud sql instances describe "${instance}" \
        --project "${PROJECT_ID}" \
        --format='value(settings.activationPolicy)'
    )"

    if [[ "${current_policy}" == "${policy}" ]]; then
      echo "Cloud SQL ${instance} already has activation policy ${policy}; checking readiness..."
      continue
    fi

    echo "Setting Cloud SQL ${instance} activation policy to ${policy}..."
    gcloud sql instances patch "${instance}" \
      --project "${PROJECT_ID}" \
      --activation-policy="${policy}" \
      --async \
      --quiet \
      --format='value(name)'
  done

  for instance in "${instances[@]}"; do
    wait_for_sql_state "${instance}" "${policy}"
  done
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
  local token
  token="$(date +%s)-${RANDOM}"
  kubectl -n "${namespace}" patch "${kind}/${name}" \
    --type=merge \
    -p '{"spec":{"suspend":false}}' >/dev/null
  kubectl -n "${namespace}" annotate "${kind}/${name}" \
    kustomize.toolkit.fluxcd.io/reconcile- >/dev/null 2>&1 || true
  kubectl -n "${namespace}" annotate "${kind}/${name}" \
    "reconcile.fluxcd.io/requestedAt=${token}" \
    "reconcile.fluxcd.io/forceAt=${token}" \
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

  echo "Cloud SQL is ready and Flux has been asked to restore MS2 workloads."
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
