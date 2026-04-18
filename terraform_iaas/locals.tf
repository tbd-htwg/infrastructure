locals {
  assets_bucket_name = coalesce(var.assets_bucket_name, "${var.project_id}-tbd-iaas-assets")
  tiers_enabled = {
    for k, v in var.tiers : k => v if coalesce(v.enabled, true)
  }

  ghcr_enabled = (
    var.ghcr_username != "" && var.ghcr_token_file != null && var.ghcr_token_file != ""
  )
}
