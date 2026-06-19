variable "project_id" {
  type        = string
  description = "GCP project ID that owns the fleet and GKE cluster."
}

variable "cluster_id" {
  type        = string
  description = "Fully qualified GKE cluster resource ID."
}

variable "membership_id" {
  type        = string
  description = "Fleet membership ID for the GKE cluster."
}
