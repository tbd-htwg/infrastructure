variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "location" {
  type        = string
  description = "KMS location."
  default     = "europe-west1"
}

variable "key_ring_name" {
  type        = string
  description = "KMS key ring name."
  default     = "tripplanning-keyring"
}

variable "crypto_key_name" {
  type        = string
  description = "KMS crypto key name."
  default     = "tripplanning-key"
}

variable "enabled" {
  type        = bool
  description = "Whether to create KMS resources."
  default     = false
}
