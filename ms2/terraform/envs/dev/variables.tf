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
