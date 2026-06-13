variable "project_id" {
  type        = string
  description = "GCP project ID to bootstrap."
}

variable "api_services" {
  type        = list(string)
  description = "APIs to enable in the project."
  default = [
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "identitytoolkit.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "places.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ]
}

variable "firestore" {
  type = object({
    enabled     = bool
    database_id = string
    location_id = string
    type        = optional(string, "FIRESTORE_NATIVE")
    indexes = optional(map(object({
      collection  = string
      query_scope = optional(string, "COLLECTION")
      fields = list(object({
        field_path = string
        order      = string
      }))
    })), {})
  })
  description = "Optional Firestore Native database and composite indexes."
  default = {
    enabled     = false
    database_id = "(default)"
    location_id = "europe-west1"
    type        = "FIRESTORE_NATIVE"
    indexes     = {}
  }
}

variable "service_accounts" {
  type = map(object({
    display_name = string
    description  = string
  }))
  description = "Service accounts to create."
  default = {
    platform-admin = {
      display_name = "platform-admin"
      description  = "Platform automation and cluster bootstrap."
    }
    image_url_sig = {
      display_name = "tripplanning-image-url-sig"
      description  = "Signer service account for GCS upload URLs."
    }
    secrets_deployer = {
      display_name = "secrets-deployer"
      description  = "GitHub Actions service account for Secret Manager syncs."
    }
    gitops = {
      display_name = "gitops"
      description  = "FluxCD and GitOps operations."
    }
    workload = {
      display_name = "workload"
      description  = "In-cluster workloads using Workload Identity."
    }
  }
}

variable "iam_bindings" {
  type        = map(list(string))
  description = "Project-level IAM bindings (role => members)."
  default     = {}
}

variable "artifact_registry_enabled" {
  type        = bool
  description = "Whether to create Artifact Registry repository."
  default     = true
}

variable "artifact_registry" {
  type = object({
    name        = string
    location    = string
    format      = string
    description = string
  })
  description = "Artifact Registry repository settings."
  default = {
    name        = "tripplanning"
    location    = "europe-west1"
    format      = "DOCKER"
    description = "Container images and Helm charts."
  }
}

variable "secrets" {
  type = list(object({
    name   = string
    labels = optional(map(string), {})
  }))
  description = "Secret Manager secrets to create (no values)."
  default     = []
}

variable "enable_dns" {
  type        = bool
  description = "Whether to create a Cloud DNS managed zone."
  default     = false
}

variable "dns_zone" {
  type = object({
    name        = string
    domain      = string
    description = string
  })
  description = "Cloud DNS managed zone settings."
  default = {
    name        = ""
    domain      = ""
    description = ""
  }
}

variable "log_sink" {
  type = object({
    enabled         = bool
    name            = string
    filter          = string
    bucket_location = string
  })
  description = "Optional log sink to Cloud Storage."
  default = {
    enabled         = false
    name            = "project-logs"
    filter          = ""
    bucket_location = "EU"
  }
}
