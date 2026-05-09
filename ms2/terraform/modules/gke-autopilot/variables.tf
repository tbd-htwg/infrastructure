variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for the cluster."
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name."
  default     = "tripplanning-gke"
}

variable "network_self_link" {
  type        = string
  description = "VPC network self link."
}

variable "subnet_self_link" {
  type        = string
  description = "Subnetwork self link."
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Secondary range for pods."
}

variable "services_secondary_range_name" {
  type        = string
  description = "Secondary range for services."
}

variable "release_channel" {
  type        = string
  description = "GKE release channel."
  default     = "REGULAR"
}

variable "enable_gateway_api" {
  type        = bool
  description = "Enable Gateway API support."
  default     = true
}

variable "private_cluster" {
  type        = bool
  description = "Whether to enable private nodes."
  default     = true
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR block for the GKE control plane when using private nodes."
  default     = "172.16.0.0/28"
}
