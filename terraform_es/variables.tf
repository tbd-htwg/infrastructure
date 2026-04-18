variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region (bucket, metadata)."
  type        = string
}

variable "zone" {
  description = "Zone for the Compute Engine VM; use the same region as var.region, PaaS (infrastructure/terraform), and IaaS (terraform_iaas) VMs."
  type        = string
}

variable "elasticsearch_fqdn" {
  description = "Public hostname for this Elasticsearch endpoint (e.g. es.tbd-htwg.de). Caddy obtains a cert for this name."
  type        = string
}

variable "dns_managed_zone_name" {
  description = "Existing Cloud DNS managed zone name."
  type        = string
}

variable "manage_cloud_dns_records" {
  description = "Create an A record for elasticsearch_fqdn pointing at the VM public IP."
  type        = bool
  default     = true
}

variable "instance_name" {
  description = "GCE instance name."
  type        = string
  default     = "tbd-es-gateway"
}

variable "network_tag" {
  description = "Network tag for HTTP/HTTPS firewall rules."
  type        = string
  default     = "tripplanning-es-gateway"
}

variable "machine_type" {
  description = "Machine type for the Elasticsearch + Caddy VM."
  type        = string
  default     = "e2-standard-2"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size (GB); Docker volumes for ES live on this disk."
  type        = number
  default     = 50
}

variable "boot_image" {
  description = "Boot disk image."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "es_java_opts" {
  description = "JVM options for Elasticsearch (set on VM metadata and .env)."
  type        = string
  default     = "-Xms1g -Xmx1g"
}

variable "allow_ssh_ingress" {
  description = "Open TCP 22 from ssh_source_ranges (e.g. IAP)."
  type        = bool
  default     = false
}

variable "ssh_source_ranges" {
  type    = list(string)
  default = ["35.235.240.0/20"]
}

variable "es_vm_sa_id" {
  description = "Service account id (without @project) for the VM."
  type        = string
  default     = "tbd-es-vm"
}

variable "assets_bucket_name" {
  description = "GCS bucket for compose assets. Default: <project_id>-tbd-es-assets."
  type        = string
  default     = null
}

variable "gcp_sa_json_file" {
  description = "Local path to GCP SA JSON for Caddy DNS-01 (DNS admin on the zone)."
  type        = string
}

variable "ghcr_username" {
  description = "GitHub username for docker login to ghcr.io (private caddy image). Empty to skip."
  type        = string
  default     = ""
}

variable "ghcr_token_file" {
  type     = string
  nullable = true
  default  = null
}

variable "secret_accessor_members" {
  description = "IAM members (e.g. serviceAccount:RUNTIME_SA@project.iam.gserviceaccount.com) allowed to read the Elasticsearch password secret (Cloud Run PaaS)."
  type        = list(string)
  default     = []
}
