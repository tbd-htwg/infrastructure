resource "google_kms_key_ring" "key_ring" {
  count    = var.enabled ? 1 : 0
  project  = var.project_id
  name     = var.key_ring_name
  location = var.location
}

resource "google_kms_crypto_key" "crypto_key" {
  count           = var.enabled ? 1 : 0
  name            = var.crypto_key_name
  key_ring        = google_kms_key_ring.key_ring[0].id
  rotation_period = "7776000s"
}
