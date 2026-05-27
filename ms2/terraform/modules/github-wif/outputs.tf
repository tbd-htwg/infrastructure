output "workload_identity_provider" {
  description = "WIF provider resource name."
  value       = google_iam_workload_identity_pool_provider.provider.name
}

output "deployer_service_account" {
  description = "Deployer service account email."
  value       = google_service_account.deployer.email
}
