#!/bin/bash

PROJECT="project-9118634e-c9f1-4f29-804"

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

echo "Importing Cloud Run..."
tf_import module.app.google_cloud_run_service.backend \
europe-west1/$PROJECT/tripplanning-backend

echo "Importing Service Accounts..."
tf_import module.app.google_service_account.backend_runtime \
projects/$PROJECT/serviceAccounts/tripplanning-prod-be-rt@$PROJECT.iam.gserviceaccount.com

tf_import module.app.google_service_account.backend_deploy \
projects/$PROJECT/serviceAccounts/tripplanning-prod-be-deploy@$PROJECT.iam.gserviceaccount.com

tf_import module.app.google_service_account.frontend_deploy \
projects/$PROJECT/serviceAccounts/tripplanning-prod-fe-deploy@$PROJECT.iam.gserviceaccount.com

echo "Importing Cloud SQL..."
tf_import module.app.google_sql_database_instance.db \
$PROJECT/tripplanning-pg

echo "Importing SQL DB..."
tf_import module.app.google_sql_database.app \
$PROJECT/tripplanning-pg/tripplanning

echo "Importing SQL user..."
tf_import module.app.google_sql_user.app \
$PROJECT/tripplanning-pg/tripplanning_app

echo "Importing Storage..."
tf_import module.app.google_storage_bucket.frontend \
project-9118634e-c9f1-4f29-804-frontend-bucket

echo "Importing NEG..."
tf_import module.app.google_compute_region_network_endpoint_group.backend_neg \
projects/$PROJECT/regions/europe-west1/networkEndpointGroups/tripplanning-backend-neg

echo "Importing Backend Service..."
tf_import module.app.google_compute_backend_service.api_backend \
tripplanning-api-backend

echo "Importing Backend Bucket..."
tf_import module.app.google_compute_backend_bucket.frontend_backend \
tripplanning-frontend-backend

echo "Importing URL Map..."
tf_import module.app.google_compute_url_map.lb \
tripplanning-lb

echo "Importing HTTPS Proxy..."
tf_import module.app.google_compute_target_https_proxy.https \
tripplanning-lb-https-proxy

echo "Importing Forwarding Rule..."
tf_import module.app.google_compute_global_forwarding_rule.https \
tripplanning-lb-https-rule

echo "Importing SSL Cert..."
tf_import module.app.google_compute_managed_ssl_certificate.cert \
tripplanning-certs

echo "Importing DNS..."
tf_import module.app.google_dns_record_set.main \
tbd-example-zone/paas.tbd-htwg.de./A

tf_import module.app.google_dns_record_set.api \
tbd-example-zone/api.paas.tbd-htwg.de./A

echo "Importing IAM bindings..."
tf_import module.app.google_project_iam_member.run_admin \
"$PROJECT roles/run.admin serviceAccount:tripplanning-prod-be-deploy@$PROJECT.iam.gserviceaccount.com"

tf_import module.app.google_project_iam_member.cloudsql_client \
"$PROJECT roles/cloudsql.client serviceAccount:tripplanning-prod-be-rt@$PROJECT.iam.gserviceaccount.com"

echo "DONE"
