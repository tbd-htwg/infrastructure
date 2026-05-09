output "crypto_key_id" {
  description = "KMS crypto key ID."
  value       = var.enabled ? google_kms_crypto_key.crypto_key[0].id : null
}
