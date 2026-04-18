variable "project_id" {
  description = "GCP project ID (billing enabled)."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (bucket, metadata)."
  type        = string
}

variable "zone" {
  description = "Zone for Compute Engine VMs and zonal disks (e.g. europe-west1-b)."
  type        = string
}

variable "iaas_domain_suffix" {
  description = "DNS suffix for tier hostnames: <tier>-iaas.<suffix> (e.g. tbd-htwg.de)."
  type        = string
}

variable "dns_managed_zone_name" {
  description = "Existing Cloud DNS managed zone name (zone is not created here)."
  type        = string
}

variable "manage_cloud_dns_records" {
  description = "When true, create A records for each enabled tier pointing at the VM public IP."
  type        = bool
  default     = true
}

variable "instance_name_prefix" {
  description = "Prefix for VM names (e.g. tbd-iaas)."
  type        = string
  default     = "tbd-iaas"
}

variable "network_tag" {
  description = "Network tag applied to VMs; firewall rules target this tag."
  type        = string
  default     = "tripplanning-iaas"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size (GB) for each VM (Docker + images + ES test data; no extra data disk)."
  type        = number
  default     = 40
}

variable "boot_image" {
  description = "Boot disk image (Ubuntu 22.04 LTS family recommended)."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "allow_ssh_ingress" {
  description = "When true, open TCP 22 from ssh_source_ranges (use IAP or narrow ranges)."
  type        = bool
  default     = false
}

variable "ssh_source_ranges" {
  description = "CIDRs allowed to SSH when allow_ssh_ingress is true."
  type        = list(string)
  default     = ["35.235.240.0/20"] # IAP TCP forwarding
}

variable "iaas_vm_sa_id" {
  description = "Service account id (without @project.iam) used by IaaS VMs."
  type        = string
  default     = "tbd-iaas-vm"
}

variable "assets_bucket_name" {
  description = "GCS bucket name for bootstrap assets (must be globally unique). Default: <project_id>-tbd-iaas-assets."
  type        = string
  default     = null
}

variable "tripplanning_env_file" {
  description = "Path to a local .env file (Postgres, etc.). CADDY_DOMAIN and GCP_PROJECT are appended on the VM. Contents are stored in Secret Manager and in Terraform state."
  type        = string
}

variable "gcp_sa_json_file" {
  description = "Path to a local GCP service account JSON for Caddy DNS-01 (and other GCP APIs). Stored in Secret Manager and in Terraform state."
  type        = string
}

variable "artifact_registry_repository_ids" {
  description = "Optional Artifact Registry repository ids (same region) whose images the VM may pull. Grants roles/artifactregistry.reader on each."
  type        = list(string)
  default     = []
}

variable "ghcr_username" {
  description = "GitHub username for docker login to ghcr.io (private images). Leave empty to skip GHCR login."
  type        = string
  default     = ""
}

variable "ghcr_token_file" {
  description = "Path to a local file containing a GitHub PAT with read:packages scope. Stored in Secret Manager; bootstrap runs docker login before compose pull. Null to skip."
  type        = string
  nullable    = true
  default     = null
}

variable "tiers" {
  description = <<-EOT
    Map of tier key -> shape. Each enabled tier gets its own VM and DNS name <key>-iaas.<iaas_domain_suffix>.
    All VMs run the same Docker Compose stack from GCS. es_java_opts is passed to Elasticsearch (fit heap to RAM).
  EOT
  type = map(object({
    machine_type = string
    es_java_opts = optional(string, "-Xms512m -Xmx512m")
    enabled      = optional(bool, true)
  }))
}

variable "elasticsearch_secret_accessor_members" {
  description = <<-EOT
    Extra IAM members allowed to read per-tier Elasticsearch passwords (e.g.
    serviceAccount:YOUR_CLOUD_RUN_RUNTIME@PROJECT.iam.gserviceaccount.com for PaaS).
  EOT
  type    = list(string)
  default = []
}
