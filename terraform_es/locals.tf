locals {
  assets_bucket_name = coalesce(var.assets_bucket_name, "${var.project_id}-tbd-es-assets")

  ghcr_enabled = (
    var.ghcr_username != "" && var.ghcr_token_file != null && var.ghcr_token_file != ""
  )
}
