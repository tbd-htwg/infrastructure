#!/usr/bin/env bash
# Import GCP resources that already exist into Terraform state (dev env).
# Run once after a partial apply or when adopting pre-existing infrastructure.
#
# Usage:
#   export GOOGLE_PROJECT=milestone2-tbd-cad   # optional; reads from terraform.tfvars
#   ./scripts/terraform-import-existing-dev.sh
#
# Requires: terraform, gcloud (optional for verification)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform/envs/dev"
cd "${TF_DIR}"

PROJECT="${GOOGLE_PROJECT:-$(grep -E '^project_id' terraform.tfvars | sed 's/.*= *"\(.*\)".*/\1/')}"
REGION="${GOOGLE_REGION:-$(grep -E '^region' terraform.tfvars | sed 's/.*= *"\(.*\)".*/\1/' || echo europe-west1)}"

if [[ -z "${PROJECT}" ]]; then
  echo "Set GOOGLE_PROJECT or project_id in terraform.tfvars"
  exit 1
fi

echo "Project: ${PROJECT}  Region: ${REGION}"
terraform init -input=false

import_if_missing() {
  local addr="$1"
  local id="$2"
  if terraform state show "${addr}" &>/dev/null; then
    echo "  skip (in state): ${addr}"
  elif terraform import "${addr}" "${id}" 2>/dev/null; then
    echo "  imported: ${addr}"
  else
    echo "  skip (not in GCP yet): ${addr}"
  fi
}

echo "== Service accounts =="
import_if_missing \
  'module.project_bootstrap.google_service_account.service_accounts["platform-admin"]' \
  "projects/${PROJECT}/serviceAccounts/platform-admin@${PROJECT}.iam.gserviceaccount.com"
import_if_missing \
  'module.project_bootstrap.google_service_account.service_accounts["gitops"]' \
  "projects/${PROJECT}/serviceAccounts/gitops@${PROJECT}.iam.gserviceaccount.com"
import_if_missing \
  'module.project_bootstrap.google_service_account.service_accounts["workload"]' \
  "projects/${PROJECT}/serviceAccounts/workload@${PROJECT}.iam.gserviceaccount.com"

echo "== Artifact Registry =="
import_if_missing \
  'module.project_bootstrap.google_artifact_registry_repository.repo[0]' \
  "projects/${PROJECT}/locations/${REGION}/repositories/tripplanning"

echo "== Secret Manager (bootstrap secrets) =="
import_if_missing \
  'module.project_bootstrap.google_secret_manager_secret.secrets["tripplanning-db-password"]' \
  "projects/${PROJECT}/secrets/tripplanning-db-password"
import_if_missing \
  'module.project_bootstrap.google_secret_manager_secret.secrets["tbd-es-gateway-elastic-password"]' \
  "projects/${PROJECT}/secrets/tbd-es-gateway-elastic-password"

echo "== App workload secrets =="
import_if_missing \
  'google_secret_manager_secret.auth_jwt' \
  "projects/${PROJECT}/secrets/tripplanning-auth-jwt-secret"
import_if_missing \
  'google_secret_manager_secret.internal_api' \
  "projects/${PROJECT}/secrets/tripplanning-internal-secret"

echo "== DNS =="
import_if_missing \
  'module.project_bootstrap.google_dns_managed_zone.zone[0]' \
  "projects/${PROJECT}/managedZones/k8s-tbd-zone"

echo "== Log sink bucket =="
import_if_missing \
  'module.project_bootstrap.google_storage_bucket.log_sink[0]' \
  "${PROJECT}-project-logs"

echo "== Storage buckets =="
import_if_missing \
  'module.storage.google_storage_bucket.buckets["images"]' \
  "${PROJECT}-images-bucket"
import_if_missing \
  'module.storage.google_storage_bucket.buckets["frontend_assets"]' \
  "${PROJECT}-frontend-bucket"
import_if_missing \
  'module.storage.google_storage_bucket.buckets["terraform_state"]' \
  "${PROJECT}-tfstate"

echo "== VPC / subnet / NAT =="
import_if_missing \
  'module.network.google_compute_network.vpc' \
  "projects/${PROJECT}/global/networks/tripplanning-vpc"
import_if_missing \
  'module.network.google_compute_subnetwork.primary' \
  "projects/${PROJECT}/regions/${REGION}/subnetworks/tripplanning-subnet"
import_if_missing \
  'module.network.google_compute_router.router' \
  "projects/${PROJECT}/regions/${REGION}/routers/tripplanning-router"
import_if_missing \
  'module.network.google_compute_router_nat.nat' \
  "${PROJECT}/${REGION}/tripplanning-router/tripplanning-nat"

echo "== GKE =="
import_if_missing \
  'module.gke_autopilot.google_container_cluster.autopilot' \
  "projects/${PROJECT}/locations/${REGION}/clusters/tripplanning-gke"

echo "== Cloud SQL (if instance exists) =="
import_if_missing \
  'module.cloudsql.google_compute_global_address.private_service_range' \
  "projects/${PROJECT}/global/addresses/tripplanning-dev-pg-private-range"
import_if_missing \
  'module.cloudsql.google_sql_database_instance.instance' \
  "projects/${PROJECT}/instances/tripplanning-dev-pg"
import_if_missing \
  'module.cloudsql.google_sql_database.shared' \
  "projects/${PROJECT}/instances/tripplanning-dev-pg/databases/tripplanning"
import_if_missing \
  'module.cloudsql.google_sql_user.app_user' \
  "${PROJECT}/tripplanning-dev-pg/tripplanning_app"

echo "== Firestore (only if manage_firestore_database = true) =="
import_if_missing \
  'google_firestore_database.social[0]' \
  "projects/${PROJECT}/databases/tbd-firestore"
import_if_missing \
  'google_firestore_database.social' \
  "projects/${PROJECT}/databases/tbd-firestore"

echo ""
echo "Done. Run: terraform plan && terraform apply"
echo "Resources skipped as 'not in GCP yet' (e.g. GKE cluster) will be created on apply."
echo "If Firestore returns 403: grant roles/datastore.owner (or manage_firestore_database = false)."
echo "If Artifact Registry returns 403: grant roles/artifactregistry.admin or artifact_registry_enabled = false."
