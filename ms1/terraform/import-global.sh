#!/bin/bash

PROJECT="project-9118634e-c9f1-4f29-804"
PROJECT_NUMBER="1001763908245"

set -e

tf_import() {
	local addr="$1"
	local id="$2"

	if terraform state list | grep -qx "$addr"; then
		echo "Skipping $addr (already in state)"
		return 0
	fi

	terraform import "$addr" "$id"
}

echo "Importing project APIs..."
for api in \
	artifactregistry.googleapis.com \
	compute.googleapis.com \
	dns.googleapis.com \
	iam.googleapis.com \
	iamcredentials.googleapis.com \
	run.googleapis.com \
	secretmanager.googleapis.com \
	sqladmin.googleapis.com \
	storage.googleapis.com; do
	tf_import "google_project_service.apis[\"$api\"]" "$PROJECT/$api"
done

echo "Importing Artifact Registry..."
tf_import google_artifact_registry_repository.repo \
	"projects/$PROJECT/locations/europe-west1/repositories/tripplanning"

echo "Importing DNS zone and records..."
tf_import google_dns_managed_zone.main "$PROJECT/tbd-example-zone"
tf_import google_dns_record_set.es "tbd-example-zone/es.tbd-htwg.de./A"
tf_import google_dns_record_set.iaas "tbd-example-zone/iaas.tbd-htwg.de./A"
tf_import google_dns_record_set.api_iaas "tbd-example-zone/api.iaas.tbd-htwg.de./A"
tf_import google_dns_record_set.paas_stag "tbd-example-zone/paas-stag.tbd-htwg.de./A"
tf_import google_dns_record_set.api_paas_stag "tbd-example-zone/api.paas-stag.tbd-htwg.de./A"

echo "Importing IAM..."
tf_import google_project_iam_custom_role.frontend_cdn_invalidator \
	"projects/$PROJECT/roles/tripplanningFrontendCdnInvalidator"
tf_import google_service_account.tbd_es_vm \
	"projects/$PROJECT/serviceAccounts/tbd-es-vm@$PROJECT.iam.gserviceaccount.com"
tf_import google_service_account.caddy_cert \
	"projects/$PROJECT/serviceAccounts/caddy-cert@$PROJECT.iam.gserviceaccount.com"
tf_import google_project_iam_member.caddy_dns_admin \
	"$PROJECT roles/dns.admin serviceAccount:caddy-cert@$PROJECT.iam.gserviceaccount.com"
tf_import google_project_iam_member.cloudbuild_builder \
	"$PROJECT roles/cloudbuild.builds.builder serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"

echo "Importing Secret Manager..."
tf_import google_secret_manager_secret.tripplanning_db_password \
	"projects/$PROJECT/secrets/tripplanning-db-password"
tf_import google_secret_manager_secret.es_elastic_password \
	"projects/$PROJECT/secrets/tbd-es-gateway-elastic-password"
tf_import google_secret_manager_secret.es_gcp_sa_json \
	"projects/$PROJECT/secrets/tbd-es-gateway-gcp-sa-json"
tf_import google_secret_manager_secret.es_ghcr_token \
	"projects/$PROJECT/secrets/tbd-es-gateway-ghcr-token"
tf_import google_secret_manager_secret_iam_member.es_vm_elastic_password \
	"projects/$PROJECT/secrets/tbd-es-gateway-elastic-password roles/secretmanager.secretAccessor serviceAccount:tbd-es-vm@$PROJECT.iam.gserviceaccount.com"
tf_import google_secret_manager_secret_iam_member.es_vm_gcp_sa_json \
	"projects/$PROJECT/secrets/tbd-es-gateway-gcp-sa-json roles/secretmanager.secretAccessor serviceAccount:tbd-es-vm@$PROJECT.iam.gserviceaccount.com"
tf_import google_secret_manager_secret_iam_member.es_vm_ghcr_token \
	"projects/$PROJECT/secrets/tbd-es-gateway-ghcr-token roles/secretmanager.secretAccessor serviceAccount:tbd-es-vm@$PROJECT.iam.gserviceaccount.com"

echo "Importing shared buckets..."
tf_import google_storage_bucket.images "$PROJECT-images-bucket"
tf_import google_storage_bucket.es_assets "$PROJECT-tbd-es-assets"
tf_import google_storage_bucket_iam_member.es_assets_vm_viewer \
	"b/$PROJECT-tbd-es-assets roles/storage.objectViewer serviceAccount:tbd-es-vm@$PROJECT.iam.gserviceaccount.com"

echo "Importing ES gateway compute resources..."
tf_import google_compute_firewall.es_gateway_http_https \
	"projects/$PROJECT/global/firewalls/tbd-es-gateway-http-https"
tf_import google_compute_instance.es_gateway \
	"projects/$PROJECT/zones/europe-west1-b/instances/tbd-es-gateway"

echo "Importing Workload Identity..."
tf_import google_iam_workload_identity_pool.github \
	"projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions"
tf_import google_iam_workload_identity_pool_provider.github \
	"projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-oidc"

echo "DONE"
