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
