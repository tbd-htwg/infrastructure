terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Use a dedicated backend for this root (copy from ../terraform/backend.tf.example and pick a new prefix).
}

provider "google" {
  project = var.project_id
  region  = var.region
}
