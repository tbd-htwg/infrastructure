variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Default region."
  default     = "europe-west1"
}

variable "enable_dns" {
  type        = bool
  description = "Whether to create Cloud DNS managed zone."
  default     = true
}

variable "dns_zone" {
  type = object({
    name        = string
    domain      = string
    description = string
  })
  description = "Cloud DNS zone settings."
}

variable "network" {
  type = object({
    name                    = string
    subnet_name             = string
    subnet_cidr             = string
    pods_secondary_name     = string
    pods_secondary_cidr     = string
    services_secondary_name = string
    services_secondary_cidr = string
  })
  description = "Network settings for the GKE cluster."
}

variable "gke" {
  type = object({
    cluster_name           = string
    release_channel        = string
    private_cluster        = bool
    master_ipv4_cidr_block = string
  })
  description = "GKE Autopilot cluster settings."
}


variable "storage" {
  type = object({
    location = string
  })
  description = "Storage bucket defaults."
  default = {
    location = "EU"
  }
}

variable "kms" {
  type = object({
    enabled         = bool
    location        = string
    key_ring_name   = string
    crypto_key_name = string
  })
  description = "Optional KMS configuration."
  default = {
    enabled         = false
    location        = "europe-west1"
    key_ring_name   = "tripplanning-keyring"
    crypto_key_name = "tripplanning-key"
  }
}

variable "firestore" {
  type = object({
    enabled     = bool
    database_id = string
    location_id = string
  })
  description = "Firestore database settings for social-service comments and likes."
  default = {
    enabled     = true
    database_id = "tbd-firestore"
    location_id = "europe-west1"
  }
}

variable "frontend" {
  type = object({
    domain                     = string
    enable_cdn                 = bool
    api_backend_neg_self_links = optional(list(string))
    api_paths                  = optional(list(string))
    api_health_check_path      = optional(string)
    api_health_check_port      = optional(number)
  })
  description = "Frontend bucket + HTTPS load balancer settings."
}

variable "github_wif" {
  type = object({
    owner                = string
    repo                 = string
    pool_id              = string
    provider_id          = string
    service_account_name = string
  })
  description = "GitHub Workload Identity Federation settings for frontend deploy."
}

variable "backend_wif" {
  type = object({
    owner       = string
    repo        = string
    provider_id = string
  })
  description = "GitHub Workload Identity Federation settings for backend secret sync."
}

variable "infra_wif" {
  type = object({
    owner                = optional(string, "tbd-htwg")
    repo                 = optional(string, "infrastructure")
    provider_id          = optional(string, "github-oidc-infrastructure")
    service_account_name = optional(string, "terraform-deployer")
  })
  description = "GitHub Workload Identity Federation settings for infrastructure repo Terraform applies."
  default     = {}
}

variable "flux_bootstrap" {
  type = object({
    namespace    = optional(string, "flux-system")
    manifest_dir = optional(string, "../../../gitops/clusters/dev/flux-system")
    git_username = optional(string, "git")
  })
  description = "Terraform-driven Flux bootstrap settings. Bootstrap is always enabled for this environment."
  default     = {}
}

variable "flux_bootstrap_git_password" {
  type        = string
  description = "Optional Git token/password used for the flux-system Git auth secret when the Git repository is private."
  sensitive   = true
  default     = null
  nullable    = true
}

variable "platform_github_dispatch_token" {
  type        = string
  description = "Optional GitHub token stored in Secret Manager for platform-service repository_dispatch calls."
  sensitive   = true
  default     = null
}

variable "standard_cloudsql" {
  type = object({
    enabled                        = optional(bool, true)
    instance_name                  = optional(string, "tripplanning-standard")
    database_version               = optional(string, "POSTGRES_15")
    tier                           = optional(string, "db-custom-1-3840")
    disk_size_gb                   = optional(number, 20)
    disk_autoresize                = optional(bool, true)
    availability_type              = optional(string, "ZONAL")
    backup_enabled                 = optional(bool, true)
    point_in_time_recovery_enabled = optional(bool, false)
    private_ip_range               = optional(string, "10.40.0.0")
  })
  description = "Shared Cloud SQL instance for Standard tenants."
  default     = {}
}

variable "platform_cloudsql" {
  type = object({
    instance_name                  = optional(string, "tripplanning-platform")
    database_name                  = optional(string, "tripplanning_platform")
    user_name                      = optional(string, "tripplanning_platform")
    database_version               = optional(string, "POSTGRES_15")
    tier                           = optional(string, "db-f1-micro")
    disk_size_gb                   = optional(number, 10)
    disk_autoresize                = optional(bool, true)
    availability_type              = optional(string, "ZONAL")
    backup_enabled                 = optional(bool, true)
    point_in_time_recovery_enabled = optional(bool, false)
  })
  description = "Small Cloud SQL instance for the platform-service tenant registry."
  default     = {}
}

variable "standard_load_balancer" {
  type = object({
    name = optional(string, "tripplanning-standard-lb-ip")
  })
  description = "Static regional IP used by the Free API pool and the frontend load balancer's default API backend."
  default     = {}
}

variable "standard_tenant_load_balancer" {
  type = object({
    name = optional(string, "tripplanning-standard-tenant-lb-ip")
  })
  description = "Static regional IP settings for the shared paid Standard tenant Kubernetes LoadBalancer."
  default     = {}
}

variable "standard_tenants" {
  type = map(object({
    hostnames = list(string)
    identity_platform = object({
      display_name           = string
      tenant_id              = optional(string)
      email_password_enabled = optional(bool, true)
      email_link_signin      = optional(bool, false)
      mfa_enabled            = optional(bool, false)
      auth_disabled          = optional(bool, false)
    })
    database = object({
      name      = string
      user_name = optional(string, "tripplanning_app")
    })
    frontend = object({
      bucket_prefix = string
      brand_name    = string
      color_scheme  = string
      brand_icon    = string
    })
    storage = object({
      images_prefix = string
    })
    search = object({
      index_name = string
    })
    cache = object({
      key_prefix = string
    })
  }))
  description = "Standard tenant definitions."
  default     = {}
}

variable "enterprise_tenants" {
  type = map(object({
    namespace = string
    hostnames = list(string)
    identity_platform = object({
      display_name           = string
      tenant_id              = optional(string)
      email_password_enabled = optional(bool, true)
      email_link_signin      = optional(bool, false)
      mfa_enabled            = optional(bool, false)
      auth_disabled          = optional(bool, false)
    })
    load_balancer = optional(object({
      name = optional(string)
    }), {})
    database = object({
      instance_name                  = string
      name                           = optional(string, "tripplanning")
      user_name                      = optional(string, "tripplanning_app")
      database_version               = optional(string, "POSTGRES_15")
      tier                           = optional(string, "db-custom-1-3840")
      disk_size_gb                   = optional(number, 20)
      disk_autoresize                = optional(bool, true)
      availability_type              = optional(string, "ZONAL")
      backup_enabled                 = optional(bool, true)
      point_in_time_recovery_enabled = optional(bool, false)
    })
    frontend = object({
      bucket_prefix = string
      brand_name    = string
      color_scheme  = string
      brand_icon    = string
    })
    storage = object({
      image_bucket_name = string
    })
    search = object({
      release_name = string
    })
    cache = object({
      dedicated = optional(bool, true)
    })
  }))
  description = "Enterprise tenant definitions."
  default     = {}
}
