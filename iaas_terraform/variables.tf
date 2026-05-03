variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "project-9118634e-c9f1-4f29-804"
}

variable "region" {
  description = "GCP region (must match the instance zone)"
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "GCP zone for the VM"
  type        = string
  default     = "europe-west3-c"
}

variable "instance_name" {
  description = "Compute Engine instance name"
  type        = string
  default     = "tripplanning-iaas-tf"
}

variable "machine_type" {
  description = "Compute Engine machine type"
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 32
}

variable "boot_image" {
  description = "Source image for the boot disk"
  type        = string
  default     = "projects/debian-cloud/global/images/family/debian-13"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Optional subnetwork name"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Network tags applied to the VM"
  type        = list(string)
  default     = ["http-server", "https-server"]
}

variable "service_account_email" {
  description = "Optional service account email for the VM"
  type        = string
  default     = "1001763908245-compute@developer.gserviceaccount.com"
}

variable "service_account_scopes" {
  description = "OAuth scopes for the VM service account"
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "enable_oslogin" {
  description = "Enable OS Login on the instance"
  type        = bool
  default     = true
}

variable "create_static_ip" {
  description = "Reserve and attach a static external IP"
  type        = bool
  default     = true
}

variable "static_ip_name" {
  description = "Name of the reserved static IP (when enabled)"
  type        = string
  default     = "tripplanning-iaas-tf-ip"
}

variable "create_firewall_rules" {
  description = "Create firewall rules for SSH/HTTP/HTTPS"
  type        = bool
  default     = false
}

variable "allow_ssh_cidrs" {
  description = "Allowed CIDR ranges for SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "infrastructure_repo_url" {
  description = "Git URL of the infrastructure repo"
  type        = string
  default     = "https://github.com/tbd-htwg/infrastructure.git"
}

variable "infrastructure_repo_branch" {
  description = "Branch to deploy (main for prod)"
  type        = string
  default     = "main"
}

variable "infrastructure_repo_subdir" {
  description = "Path to the infrastructure folder inside the repo"
  type        = string
  default     = "infrastructure"
}

variable "vm_user" {
  description = "Linux user to add to the docker group"
  type        = string
  default     = "debian"
}

variable "caddy_domain" {
  description = "Public domain served by Caddy on the VM"
  type        = string
  default     = "iaas-tf.tbd-htwg.de"
}


variable "google_application_credentials" {
  description = "Credential path used inside the Caddy container"
  type        = string
  default     = ""
}

variable "postgres_db" {
  description = "Postgres database name"
  type        = string
  default     = "tripplanning"
}

variable "postgres_user" {
  description = "Postgres username"
  type        = string
  default     = "postgres"
}


variable "elastic_password" {
  description = "Optional Elasticsearch password for the local container"
  type        = string
  default     = ""
  sensitive   = true
}

variable "elasticsearch_username" {
  description = "Optional Elasticsearch username"
  type        = string
  default     = ""
}


variable "elasticsearch_path_prefix" {
  description = "Optional Elasticsearch path prefix"
  type        = string
  default     = ""
}


variable "gcp_project" {
  description = "GCP project ID passed to Caddy"
  type        = string
  default     = "project-9118634e-c9f1-4f29-804"
}

variable "data_disk_name" {
  description = "Name of the persistent data disk for Docker"
  type        = string
  default     = "tripplanning-iaas-data"
}

variable "data_disk_size_gb" {
  description = "Size of the persistent data disk in GB"
  type        = number
  default     = 50
}

variable "data_disk_type" {
  description = "Disk type for the persistent data disk"
  type        = string
  default     = "pd-balanced"
}

variable "postgres_password_secret_id" {
  description = "Secret Manager secret ID for the Postgres password"
  type        = string
  default     = "tripplanning-db-password"
}

variable "elasticsearch_password_secret_id" {
  description = "Secret Manager secret ID for the Elasticsearch password"
  type        = string
  default     = "tbd-es-gateway-elastic-password"
}

variable "dns_zone" {
  description = "Cloud DNS managed zone name"
  type        = string
  default     = "tbd-example-zone"
}

variable "dns_record_name" {
  description = "DNS record to create (must end with a dot)"
  type        = string
  default     = "iaas-tf.tbd-htwg.de."
}

variable "dns_ttl" {
  description = "DNS TTL in seconds"
  type        = number
  default     = 300
}

variable "manage_dns" {
  description = "Create Cloud DNS A record pointing to the VM"
  type        = bool
  default     = true
}

variable "grant_dns_admin" {
  description = "Grant Cloud DNS admin role to the VM service account"
  type        = bool
  default     = true
}

variable "grant_secretmanager_access" {
  description = "Grant Secret Manager access to the VM service account"
  type        = bool
  default     = true
}

variable "metadata_ssh_keys" {
  description = "SSH keys metadata entry to mirror the old VM"
  type        = string
  default     = ""
}

variable "ghcr_username" {
  type    = string
  default = ""
}

variable "ghcr_token" {
  type      = string
  default   = ""
  sensitive = true
}