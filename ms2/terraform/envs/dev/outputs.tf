output "service_account_emails" {
  description = "Service account emails for integrations."
  value       = module.project_bootstrap.service_account_emails
}

output "secrets_deployer_sa_email" {
  description = "GitHub Actions service account email for Secret Manager syncs."
  value       = module.project_bootstrap.service_account_emails["secrets_deployer"]
}

output "backend_deployer_sa_email" {
  description = "GitHub Actions service account email for backend image deploys and Secret Manager syncs."
  value       = module.project_bootstrap.service_account_emails["secrets_deployer"]
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository name."
  value       = module.project_bootstrap.artifact_registry_repo
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name."
  value       = module.project_bootstrap.dns_zone_name
}

output "log_sink_bucket" {
  description = "Log sink bucket name."
  value       = module.project_bootstrap.log_sink_bucket
}

output "network_self_link" {
  description = "VPC network self link."
  value       = module.network.network_self_link
}

output "subnet_self_link" {
  description = "Subnet self link."
  value       = module.network.subnet_self_link
}

output "gke_cluster_name" {
  description = "GKE Autopilot cluster name."
  value       = module.gke_autopilot.cluster_name
}

output "gke_cluster_location" {
  description = "GKE Autopilot cluster location."
  value       = module.gke_autopilot.cluster_location
}

output "cloud_service_mesh" {
  description = "Fleet membership and managed Cloud Service Mesh feature."
  value = {
    membership_id         = module.cloud_service_mesh.membership_id
    membership_name       = module.cloud_service_mesh.membership_name
    feature_id            = module.cloud_service_mesh.feature_id
    feature_membership_id = module.cloud_service_mesh.feature_membership_id
  }
}


output "storage_buckets" {
  description = "Storage bucket names."
  value       = module.storage.bucket_names
}

output "frontend_domain" {
  description = "Frontend domain."
  value       = module.frontend_lb.frontend_domain
}

output "github_wif_provider" {
  description = "WIF provider name for GitHub Actions."
  value       = module.github_wif.workload_identity_provider
}

output "backend_wif_provider" {
  description = "WIF provider name for backend GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.backend.name
}

output "infra_wif_provider" {
  description = "WIF provider name for infrastructure GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.infra.name
}

output "infra_terraform_service_account" {
  description = "Service account email for infrastructure Terraform applies from GitHub Actions."
  value       = google_service_account.infra_terraform_deployer.email
}

output "frontend_deployer_sa" {
  description = "Frontend deployer service account email."
  value       = module.github_wif.deployer_service_account
}

output "frontend_ip" {
  description = "Frontend global IP address."
  value       = module.frontend_lb.frontend_ip
}

output "firestore_database_id" {
  description = "Firestore database id used by social-service."
  value       = module.project_bootstrap.firestore_database_id
}

output "standard_load_balancer_ip" {
  description = "Static regional IP address for the shared paid Standard tenant Kubernetes LoadBalancer."
  value       = google_compute_address.standard_tenant_lb_ip.address
}

output "enterprise_load_balancer_ips" {
  description = "Static regional IP addresses for Enterprise Kubernetes LoadBalancers."
  value       = { for tenant_id, ip in google_compute_address.enterprise_lb_ip : tenant_id => ip.address }
}

output "tenant_dns_records" {
  description = "Tenant DNS records managed by Terraform."
  value = {
    standard   = { for tenant_id, dns in module.standard_tenant_dns : tenant_id => dns.tenant_record_name }
    enterprise = { for tenant_id, dns in module.enterprise_tenant_dns : tenant_id => dns.tenant_record_name }
  }
}

output "identity_platform_tenant_ids" {
  description = "Identity Platform tenant IDs by tier and tenant key."
  value = {
    standard = {
      for tenant_id, tenant in var.standard_tenants : tenant_id => coalesce(
        try(tenant.identity_platform.tenant_id, null),
        try(regex("[^/]+$", google_identity_platform_tenant.standard[tenant_id].name), null),
        try(regex("[^/]+$", google_identity_platform_tenant.standard[tenant_id].id), null),
      )
    }
    enterprise = {
      for tenant_id, tenant in var.enterprise_tenants : tenant_id => coalesce(
        try(tenant.identity_platform.tenant_id, null),
        try(regex("[^/]+$", google_identity_platform_tenant.enterprise[tenant_id].name), null),
        try(regex("[^/]+$", google_identity_platform_tenant.enterprise[tenant_id].id), null),
      )
    }
  }
}

output "identity_platform" {
  description = "Project-level Identity Platform settings used by the frontend and platform service."
  value = {
    auth_domain        = "${var.project_id}.firebaseapp.com"
    web_api_key_secret = "tripplanning-firebase-web-api-key"
  }
}

output "standard_cloudsql" {
  description = "Shared Standard Cloud SQL outputs."
  value = var.standard_cloudsql.enabled ? {
    instance_name       = module.standard_cloudsql[0].instance_name
    connection_name     = module.standard_cloudsql[0].connection_name
    database_names      = module.standard_cloudsql[0].database_names
    user_names          = module.standard_cloudsql[0].user_names
    password_secret_ids = module.standard_cloudsql[0].password_secret_ids
  } : null
}

output "platform_cloudsql" {
  description = "Platform-service Cloud SQL outputs."
  value = {
    instance_name       = module.platform_cloudsql.instance_name
    connection_name     = module.platform_cloudsql.connection_name
    database_names      = module.platform_cloudsql.database_names
    user_names          = module.platform_cloudsql.user_names
    password_secret_ids = module.platform_cloudsql.password_secret_ids
  }
}

output "enterprise_cloudsql" {
  description = "Enterprise Cloud SQL outputs by tenant."
  value = {
    for tenant_id, sql in module.enterprise_cloudsql : tenant_id => {
      instance_name       = sql.instance_name
      connection_name     = sql.connection_name
      database_names      = sql.database_names
      user_names          = sql.user_names
      password_secret_ids = sql.password_secret_ids
    }
  }
}

output "flux_bootstrap_enabled" {
  description = "Whether Terraform is configured to bootstrap Flux into the cluster."
  value       = true
}
