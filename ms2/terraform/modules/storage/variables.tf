variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "location" {
  type        = string
  description = "Bucket location."
  default     = "EU"
}

variable "buckets" {
  type = map(object({
    name_suffix    = string
    storage_class  = string
    versioning     = bool
    uniform_access = bool
    force_destroy  = bool
    cors = optional(list(object({
      origin          = list(string)
      method          = list(string)
      response_header = list(string)
      max_age_seconds = number
    })), [])
  }))
  description = "Buckets to create."
}
