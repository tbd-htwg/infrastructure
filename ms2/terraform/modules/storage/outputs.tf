output "bucket_names" {
  description = "Created bucket names."
  value       = { for key, bucket in google_storage_bucket.buckets : key => bucket.name }
}
