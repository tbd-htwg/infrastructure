output "instance_name" {
  value = google_compute_instance.vm.name
}

output "instance_zone" {
  value = google_compute_instance.vm.zone
}

output "instance_external_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "dns_record_name" {
  value = var.dns_record_name
}
