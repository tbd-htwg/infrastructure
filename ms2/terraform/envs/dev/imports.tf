# These resources exist before the first Terraform apply in a new project:
# - the public DNS zone is created externally;
# - the state bucket is bootstrapped so the GCS backend can initialize.
import {
  to = module.project_bootstrap.google_dns_managed_zone.zone[0]
  id = "projects/${var.project_id}/managedZones/${var.dns_zone.name}"
}

import {
  to = module.storage.google_storage_bucket.buckets["terraform_state"]
  id = "${var.project_id}-tfstate"
}
