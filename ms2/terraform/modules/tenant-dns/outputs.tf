output "tenant_fqdn" {
  description = "Tenant FQDN without trailing dot."
  value       = trimsuffix(local.fqdn, ".")
}

output "tenant_record_name" {
  description = "Tenant DNS record name with trailing dot."
  value       = local.fqdn
}
