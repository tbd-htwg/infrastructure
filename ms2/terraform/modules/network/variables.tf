variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for subnet and NAT."
}

variable "network_name" {
  type        = string
  description = "VPC network name."
  default     = "tripplanning-vpc"
}

variable "subnet_name" {
  type        = string
  description = "Primary subnet name."
  default     = "tripplanning-subnet"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary subnet CIDR."
}

variable "pods_secondary_range" {
  type = object({
    name = string
    cidr = string
  })
  description = "Secondary range for GKE pods."
}

variable "services_secondary_range" {
  type = object({
    name = string
    cidr = string
  })
  description = "Secondary range for GKE services."
}

variable "router_name" {
  type        = string
  description = "Cloud Router name."
  default     = "tripplanning-router"
}

variable "nat_name" {
  type        = string
  description = "Cloud NAT name."
  default     = "tripplanning-nat"
}
