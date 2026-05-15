terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.20.0"
    }
    # Still required for `terraform destroy` while state lists resources created with
    # the beta provider (e.g. legacy Identity Platform). Remove after state is empty.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.20.0"
    }
  }
}
