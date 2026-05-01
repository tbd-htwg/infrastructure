output "backend_url" {
  value = try(google_cloud_run_service.backend.status[0].url, null)
}
