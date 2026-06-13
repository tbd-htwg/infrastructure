project_id = "tbd-cloudappdev"
region     = "europe-west1"

dns_zone = {
  name        = "tbd-dns-zone"
  domain      = "tbd-htwg.de."
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
  private_cluster        = true
  master_ipv4_cidr_block = "172.16.0.0/28"
}


kms = {
  enabled         = false
  location        = "europe-west1"
  key_ring_name   = "tripplanning-keyring"
  crypto_key_name = "tripplanning-key"
}

firestore = {
  enabled     = true
  database_id = "tbd-firestore"
  location_id = "europe-west1"
}

frontend = {
  domain     = "k8s.tbd-htwg.de"
  enable_cdn = false
  # api-router NEGs (both zones): routes /api/* to trip, social, and external-info.
  api_backend_neg_self_links = [
    "https://www.googleapis.com/compute/v1/projects/tbd-cloudappdev/zones/europe-west1-b/networkEndpointGroups/k8s1-5a871136-tripplanning-free-api-router-8088-dad08f08",
    "https://www.googleapis.com/compute/v1/projects/tbd-cloudappdev/zones/europe-west1-d/networkEndpointGroups/k8s1-5a871136-tripplanning-free-api-router-8088-dad08f08",
  ]
  api_health_check_path                  = "/healthz"
  api_health_check_port                  = 8088
  secondary_managed_ssl_certificate_name = "frontend-cert-v2"
}

github_wif = {
  owner                = "tbd-htwg"
  repo                 = "frontend"
  pool_id              = "github-actions"
  provider_id          = "github-oidc"
  service_account_name = "frontend-deployer"
}

backend_wif = {
  owner       = "tbd-htwg"
  repo        = "backend"
  provider_id = "github-oidc-backend"
}

flux_bootstrap = {
  namespace    = "flux-system"
  manifest_dir = "../../../gitops/clusters/dev/flux-system"
  git_username = "git"
}
