locals {
  service_account_emails = {
    platform-admin   = "platform-admin@${var.project_id}.iam.gserviceaccount.com"
    image_url_sig    = "tripplanning-image-url-sig@${var.project_id}.iam.gserviceaccount.com"
    secrets_deployer = "secrets-deployer@${var.project_id}.iam.gserviceaccount.com"
    gitops           = "gitops@${var.project_id}.iam.gserviceaccount.com"
    workload         = "workload@${var.project_id}.iam.gserviceaccount.com"
  }

  standard_tenant_databases = {
    for tenant_id, tenant in var.standard_tenants : tenant_id => {
      name               = tenant.database.name
      user_name          = tenant.database.user_name
      password_secret_id = "tripplanning-standard-${tenant_id}-db-password"
    }
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
          origin          = [for hostname in tenant.hostnames : "https://${hostname}"]
          method          = ["GET", "HEAD", "OPTIONS", "PUT"]
          response_header = ["Content-Type", "Authorization"]
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
}
