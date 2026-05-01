terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state: copy ../backend.tf.example into this directory and use a stage-specific prefix
  # (e.g. terraform/state/stage1) so stage1 and stage2 do not share state.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
