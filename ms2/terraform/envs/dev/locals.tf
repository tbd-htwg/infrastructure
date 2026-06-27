locals {
  service_account_emails = {
    platform-admin   = "platform-admin@${var.project_id}.iam.gserviceaccount.com"
    image_url_sig    = "tripplanning-image-url-sig@${var.project_id}.iam.gserviceaccount.com"
    secrets_deployer = "secrets-deployer@${var.project_id}.iam.gserviceaccount.com"
    gitops           = "gitops@${var.project_id}.iam.gserviceaccount.com"
    gke_nodes        = "gke-nodes@${var.project_id}.iam.gserviceaccount.com"
    workload         = "workload@${var.project_id}.iam.gserviceaccount.com"
  }
  infra_terraform_service_account_email = "${var.infra_wif.service_account_name}@${var.project_id}.iam.gserviceaccount.com"
  standard_tenant_databases = {
    for tenant_id, tenant in var.standard_tenants : tenant_id => {
      name               = tenant.database.name
      user_name          = tenant.database.user_name
      password_secret_id = "tripplanning-standard-${tenant_id}-db-password"
    }
  }

  standard_identity_platform_tenants = {
    for tenant_id, tenant in var.standard_tenants : tenant_id => tenant
    if try(tenant.identity_platform.tenant_id, null) == null || try(tenant.identity_platform.tenant_id, "") == ""
  }

  enterprise_identity_platform_tenants = {
    for tenant_id, tenant in var.enterprise_tenants : tenant_id => tenant
    if try(tenant.identity_platform.tenant_id, null) == null || try(tenant.identity_platform.tenant_id, "") == ""
  }

  standard_identity_platform_display_name_candidates = {
    for tenant_id, tenant in local.standard_identity_platform_tenants : tenant_id => replace(lower(tenant.identity_platform.display_name), "/[^a-z0-9-]/", "-")
  }

  enterprise_identity_platform_display_name_candidates = {
    for tenant_id, tenant in local.enterprise_identity_platform_tenants : tenant_id => replace(lower(tenant.identity_platform.display_name), "/[^a-z0-9-]/", "-")
  }

  standard_identity_platform_display_names = {
    for tenant_id, display_name in local.standard_identity_platform_display_name_candidates : tenant_id => substr(
      "${can(regex("^[a-z]", display_name)) ? "" : "t-"}${length(display_name) >= 4 ? display_name : "${display_name}-tenant"}",
      0,
      20,
    )
  }

  enterprise_identity_platform_display_names = {
    for tenant_id, display_name in local.enterprise_identity_platform_display_name_candidates : tenant_id => substr(
      "${can(regex("^[a-z]", display_name)) ? "" : "t-"}${length(display_name) >= 4 ? display_name : "${display_name}-tenant"}",
      0,
      20,
    )
  }

  enterprise_tenant_databases = {
    for tenant_id, tenant in var.enterprise_tenants : tenant_id => {
      primary = {
        name               = tenant.database.name
        user_name          = tenant.database.user_name
        password_secret_id = "tripplanning-enterprise-${tenant_id}-db-password"
      }
    }
  }

  enterprise_image_buckets = {
    for tenant_id, tenant in var.enterprise_tenants : "enterprise_${tenant_id}_images" => {
      name           = tenant.storage.image_bucket_name
      name_suffix    = "${tenant_id}-images-bucket"
      storage_class  = "STANDARD"
      versioning     = false
      uniform_access = true
      force_destroy  = true
      cors = [
        {
          origin = concat(
            [
              "http://localhost:5173",
              "http://127.0.0.1:5173",
              "http://localhost:4173",
              "http://127.0.0.1:4173",
            ],
            [for hostname in tenant.hostnames : "https://${hostname}"],
          )
          method          = ["GET", "HEAD", "OPTIONS", "PUT"]
          response_header = ["Content-Type", "Authorization", "x-goog-resumable", "x-goog-meta-*"]
          max_age_seconds = 3600
        }
      ]
    }
  }

  flux_bootstrap_manifest_dir = abspath("${path.module}/${var.flux_bootstrap.manifest_dir}")
  flux_bootstrap_files        = fileset(local.flux_bootstrap_manifest_dir, "**/*.yaml")
  flux_bootstrap_hash = sha256(join("", [
    for file in local.flux_bootstrap_files : filesha256("${local.flux_bootstrap_manifest_dir}/${file}")
  ]))

  infra_terraform_project_roles = toset([
    "roles/certificatemanager.admin",
    "roles/compute.admin",
    "roles/container.admin",
    "roles/dns.admin",
    "roles/gkehub.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/logging.admin",
    "roles/monitoring.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/serviceusage.apiKeysAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/artifactregistry.admin",
    "roles/cloudsql.admin",
    "roles/storage.admin",
    "roles/datastore.owner",
  ])

  google_oauth_authorized_javascript_origins = distinct(concat(
    [
      "http://localhost:5173",
      "http://127.0.0.1:5173",
      "https://${var.frontend.domain}",
      "https://www.tbd-htwg.de",
    ],
    [for hostname in flatten([for tenant in values(var.standard_tenants) : tenant.hostnames]) : "https://${hostname}"],
    [for hostname in flatten([for tenant in values(var.enterprise_tenants) : tenant.hostnames]) : "https://${hostname}"],
  ))
}
