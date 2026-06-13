output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.instance.name
}

output "connection_name" {
  description = "Cloud SQL instance connection name."
  value       = google_sql_database_instance.instance.connection_name
}

output "database_names" {
  description = "Database names by tenant key."
  value       = { for key, db in google_sql_database.databases : key => db.name }
}

output "user_names" {
  description = "Database users by tenant key."
  value       = { for key, user in google_sql_user.db_users : key => user.name }
}

output "password_secret_ids" {
  description = "Secret Manager password secret IDs by tenant key."
  value       = { for key, secret in google_secret_manager_secret.db_passwords : key => secret.secret_id }
}
