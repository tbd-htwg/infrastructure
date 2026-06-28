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

# Identity Platform is initialized once per project. Import an existing
# configuration after project migrations instead of trying to recreate it.
import {
  to = google_identity_platform_config.default
  id = "projects/${var.project_id}/config"
}

# Google OAuth provider was registered manually before Terraform owned Identity Platform.
import {
  to = google_identity_platform_default_supported_idp_config.google[0]
  id = "projects/${var.project_id}/defaultSupportedIdpConfigs/google.com"
}

# The browser Maps API key has a fixed key ID so frontend secrets can point at
# a stable resource. Import it if state was lost during a failed tenant delete
# instead of trying to recreate a soft-deleted key with the same ID.
import {
  to = google_apikeys_key.google_maps_browser
  id = "projects/${var.project_id}/locations/global/keys/2669c798-cc9a-4454-81e4-7d48af53218b"
}
