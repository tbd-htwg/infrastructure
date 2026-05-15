project_id = "milestone2-tbd-cad"
region     = "europe-west1"

# Root zone for tbd-htwg.de (registrar → terraform output parent_dns_zone_name_servers). Delegates k8s.* to the child zone below.
# If the same domain is already hosted in another GCP project, only one can be authoritative — pick one and update the registrar.
enable_parent_dns_zone = true
parent_dns_zone = {
  name        = "tbd-htwg-de-root"
  description = "tbd-htwg.de — delegate k8s to k8s-tbd-zone; set gke_gateway_ip after Gateway programs."
}
# After: kubectl get gateway tripplanning-api -n tripplanning -o jsonpath='{.status.addresses[0].value}{"\n"}'
gke_gateway_ip = ""

dns_zone = {
  name        = "k8s-tbd-zone"
  domain      = "k8s.tbd-htwg.de."
  description = "Tenant domains for GKE."
}

network = {
  name                    = "tripplanning-vpc"
  subnet_name             = "tripplanning-subnet"
  subnet_cidr             = "10.10.0.0/20"
  pods_secondary_name     = "pods"
  pods_secondary_cidr     = "10.20.0.0/16"
  services_secondary_name = "services"
  services_secondary_cidr = "10.30.0.0/20"
}

gke = {
  cluster_name           = "tripplanning-gke"
  release_channel        = "REGULAR"
  enable_gateway_api     = true
  private_cluster        = true
  master_ipv4_cidr_block = "172.16.0.0/28"
}

cloudsql = {
  instance_name        = "tripplanning-dev-pg"
  database_version     = "POSTGRES_15"
  tier                 = "db-g1-small"
  disk_size_gb         = 10
  disk_autoresize      = false
  availability_type    = "ZONAL"
  shared_database_name = "tripplanning"
  tenant_databases     = []
  app_user             = "tripplanning_app"
  private_ip_range     = "10.40.0.0"
}

kms = {
  enabled         = false
  location        = "europe-west1"
  key_ring_name   = "tripplanning-keyring"
  crypto_key_name = "tripplanning-key"
}

# Firestore DB tbd-firestore already exists in this project after first apply.
manage_firestore_database = false
