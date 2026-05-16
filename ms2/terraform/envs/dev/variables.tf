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
    enable_gateway_api     = bool
    private_cluster        = bool
    master_ipv4_cidr_block = string
  })
  description = "GKE Autopilot cluster settings."
}

variable "cloudsql" {
  type = object({
    instance_name        = string
    database_version     = string
    tier                 = string
    disk_size_gb         = number
    disk_autoresize      = bool
    availability_type    = string
    shared_database_name = string
    tenant_databases     = list(string)
    app_user             = string
    private_ip_range     = string
  })
  description = "Cloud SQL configuration."
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

variable "manage_firestore_database" {
  type        = bool
  description = "Create/manage Firestore database tbd-firestore. Set false if it already exists or you lack datastore admin permissions (import separately)."
  default     = false
}

variable "artifact_registry_enabled" {
  type        = bool
  description = "Create Artifact Registry repo tripplanning. Set false and import if the repo already exists."
  default     = true
}

variable "enable_parent_dns_zone" {
  type        = bool
  description = "Create managed zone tbd-htwg.de and NS-delegate k8s.tbd-htwg.de to the child zone in this project."
  default     = false
}

variable "parent_dns_zone" {
  type = object({
    name        = string
    description = string
  })
  description = "Terraform resource name + description for the parent zone (dns_name is always tbd-htwg.de.)."
  default = {
    name        = "tbd-htwg-de-root"
    description = "Root tbd-htwg.de — registrar NS here; child zone holds api.k8s A records."
  }
}

variable "gke_gateway_ip" {
  type        = string
  description = "If non-empty, create A records for api.k8s, social.api.k8s, and k8s.tbd-htwg.de in the k8s child zone. Set after Gateway has ADDRESS (PROGRAMMED=True)."
  default     = ""
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
