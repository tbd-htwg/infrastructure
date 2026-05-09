output "instance_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = google_sql_database_instance.instance.connection_name
}

output "shared_database_name" {
  description = "Shared database name."
  value       = google_sql_database.shared.name
}

output "tenant_database_names" {
  description = "Tenant database names."
  value       = [for db in google_sql_database.tenants : db.name]
}
