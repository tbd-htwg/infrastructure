#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"
ACTION="audit"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --action)
      ACTION="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: bash decommission-legacy-run-sa.sh [--env-file path] [--action audit|remove-bindings|disable|delete] [--force]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-europe-west1}"
LEGACY_RUN_SA_NAME="${LEGACY_RUN_SA_NAME:-tripplanning-run}"
LEGACY_RUN_SA_EMAIL="${LEGACY_RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Missing PROJECT_ID in env file." >&2
  exit 1
fi

if ! gcloud iam service-accounts describe "${LEGACY_RUN_SA_EMAIL}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Legacy SA not found: ${LEGACY_RUN_SA_EMAIL}" >&2
  exit 1
fi

services_using_legacy() {
  gcloud run services list \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --filter "spec.template.spec.serviceAccountName=${LEGACY_RUN_SA_EMAIL}" \
    --format "value(metadata.name)"
}

print_audit() {
  echo "Legacy SA audit"
  echo "Project: ${PROJECT_ID}"
  echo "Region: ${REGION}"
  echo "Legacy SA: ${LEGACY_RUN_SA_EMAIL}"
  echo

  echo "Cloud Run services using legacy SA:"
  local services
  services="$(services_using_legacy || true)"
  if [[ -z "${services}" ]]; then
    echo "- none"
  else
    echo "${services}" | sed 's/^/- /'
  fi
  echo

  echo "Project IAM roles on legacy SA:"
  gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter="bindings.members:serviceAccount:${LEGACY_RUN_SA_EMAIL}" \
    --format='value(bindings.role)' || true
  echo

  echo "Secret IAM bindings containing legacy SA:"
  gcloud secrets list --project "${PROJECT_ID}" --format='value(name)' | while read -r s; do
    if gcloud secrets get-iam-policy "$s" --project "${PROJECT_ID}" --format=json | grep -q "${LEGACY_RUN_SA_EMAIL}"; then
      echo "- $s"
    fi
  done
  echo

  echo "Members allowed to actAs legacy SA:"
  gcloud iam service-accounts get-iam-policy "${LEGACY_RUN_SA_EMAIL}" \
    --project "${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter='bindings.role:roles/iam.serviceAccountUser' \
    --format='value(bindings.members)' || true
}

assert_not_used_by_cloud_run() {
  local services
  services="$(services_using_legacy || true)"
  if [[ -n "${services}" && "${FORCE}" != "true" ]]; then
    echo "Refusing action because Cloud Run still uses legacy SA:" >&2
    echo "${services}" >&2
    echo "Re-run with --force if this is intentional." >&2
    exit 1
  fi
}

remove_project_roles() {
  gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter="bindings.members:serviceAccount:${LEGACY_RUN_SA_EMAIL}" \
    --format='value(bindings.role)' | while read -r role; do
      [[ -z "${role}" ]] && continue
      echo "Removing ${role} from ${LEGACY_RUN_SA_EMAIL}"
      gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
        --member "serviceAccount:${LEGACY_RUN_SA_EMAIL}" \
        --role "${role}" \
        --quiet >/dev/null || true
    done
}

remove_secret_roles() {
  gcloud secrets list --project "${PROJECT_ID}" --format='value(name)' | while read -r s; do
    if gcloud secrets get-iam-policy "$s" --project "${PROJECT_ID}" --format=json | grep -q "${LEGACY_RUN_SA_EMAIL}"; then
      echo "Removing secret accessor on $s from ${LEGACY_RUN_SA_EMAIL}"
      gcloud secrets remove-iam-policy-binding "$s" \
        --project "${PROJECT_ID}" \
        --member "serviceAccount:${LEGACY_RUN_SA_EMAIL}" \
        --role "roles/secretmanager.secretAccessor" \
        --quiet >/dev/null || true
    fi
  done
}

remove_actas_members() {
  gcloud iam service-accounts get-iam-policy "${LEGACY_RUN_SA_EMAIL}" \
    --project "${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter='bindings.role:roles/iam.serviceAccountUser' \
    --format='value(bindings.members)' | while read -r member; do
      [[ -z "${member}" ]] && continue
      echo "Removing ${member} actAs on ${LEGACY_RUN_SA_EMAIL}"
      gcloud iam service-accounts remove-iam-policy-binding "${LEGACY_RUN_SA_EMAIL}" \
        --project "${PROJECT_ID}" \
        --member "${member}" \
        --role "roles/iam.serviceAccountUser" \
        --quiet >/dev/null || true
    done
}

case "${ACTION}" in
  audit)
    print_audit
    ;;
  remove-bindings)
    assert_not_used_by_cloud_run
    remove_project_roles
    remove_secret_roles
    remove_actas_members
    echo "Removed IAM bindings for legacy SA: ${LEGACY_RUN_SA_EMAIL}"
    ;;
  disable)
    assert_not_used_by_cloud_run
    echo "Disabling service account ${LEGACY_RUN_SA_EMAIL}"
    gcloud iam service-accounts disable "${LEGACY_RUN_SA_EMAIL}" --project "${PROJECT_ID}"
    ;;
  delete)
    assert_not_used_by_cloud_run
    echo "Deleting service account ${LEGACY_RUN_SA_EMAIL}"
    gcloud iam service-accounts delete "${LEGACY_RUN_SA_EMAIL}" --project "${PROJECT_ID}" --quiet
    ;;
  *)
    echo "Invalid action: ${ACTION}" >&2
    exit 1
    ;;
esac
