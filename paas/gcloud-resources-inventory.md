# GCP Inventory (project-9118634e-c9f1-4f29-804)

Collected via gcloud on 2026-05-01. This inventory focuses on resources typically represented in Terraform. Secret values are not included.

## Project and APIs
- Project ID: project-9118634e-c9f1-4f29-804
- Enabled APIs (subset): Cloud Run, Cloud SQL, Artifact Registry, Secret Manager, Cloud DNS, Compute Engine, IAM, Logging, Monitoring, Storage, Pub/Sub
- Disabled APIs observed during inventory attempts:
  - Cloud Functions (cloudfunctions.googleapis.com)
  - Cloud Scheduler (cloudscheduler.googleapis.com)

## IAM and Identity
### Service accounts
- tripplanning-dev-be-rt@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-dev-be-deploy@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-dev-fe-deploy@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-dev-image-url-sig@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-dev-img-store@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-dev-id-admin@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-be-rt@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-be-deploy@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-fe-deploy@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-image-url-si@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-img-store@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tripplanning-prod-id-admin@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- tbd-es-vm@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- firebase-adminsdk-fbsvc@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com
- 1001763908245-compute@developer.gserviceaccount.com
- tripplanning-run@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com (disabled)
- caddy-cert@project-9118634e-c9f1-4f29-804.iam.gserviceaccount.com (disabled)

### Custom roles
- tripplanningFrontendCdnInvalidator (projects/project-9118634e-c9f1-4f29-804/roles/tripplanningFrontendCdnInvalidator)

### Workload Identity Federation
- Pool: projects/1001763908245/locations/global/workloadIdentityPools/github-actions
- Provider: github-oidc
  - Issuer: https://token.actions.githubusercontent.com
  - Attribute condition: assertion.repository_owner == 'tbd-htwg'

### IAM policy bindings (project level)
- roles/run.admin: tripplanning-dev-be-deploy, tripplanning-prod-be-deploy
- roles/cloudsql.client: tripplanning-dev-be-rt, tripplanning-prod-be-rt
- roles/datastore.user: tripplanning-dev-be-rt, tripplanning-prod-be-rt
- roles/iam.serviceAccountTokenCreator: firebase-adminsdk-fbsvc, tripplanning-dev-image-url-sig, tripplanning-prod-image-url-si
- roles/identitytoolkit.admin: tripplanning-dev-id-admin, tripplanning-prod-id-admin
- Custom role tripplanningFrontendCdnInvalidator: tripplanning-dev-fe-deploy, tripplanning-prod-fe-deploy
- roles/dns.admin: caddy-cert
- roles/cloudbuild.builds.builder: 1001763908245@cloudbuild.gserviceaccount.com
- Standard service agents (artifactregistry, cloudbuild, compute, containerregistry, firebase, pubsub, run)
- roles/owner: bnthn@posteo.de, jakob03schwarz@gmail.com
- roles/editor: 666tttuuu666@gmail.com, sophiadeiser99@gmail.com
- roles/cloudquotas.admin: bnthn@posteo.de

## Cloud Run
### Services (region: europe-west1)
- tripplanning-backend
  - Image: europe-west1-docker.pkg.dev/project-9118634e-c9f1-4f29-804/tripplanning/tripplanning-backend:54ff5b48286a68fd118d1c896ec43fffd6da0731
  - Service account: tripplanning-prod-be-rt
  - Cloud SQL instance: project-9118634e-c9f1-4f29-804:europe-west1:tripplanning-pg
  - Env vars: SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, SPRING_DATASOURCE_DRIVER_CLASS_NAME, CORS_ALLOWED_ORIGINS, ELASTICSEARCH_*, TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID, TRIPPLANNING_AUTH_JWT_SECRET, TRIPPLANNING_SEARCH_ELASTICSEARCH_INDEX_NAME, SPRING_CLOUD_GCP_IMPERSONATE_SERVICE_ACCOUNT
  - Secret env vars: tripplanning-db-password, tbd-es-gateway-elastic-password
- tripplanning-dev-backend
  - Image: europe-west1-docker.pkg.dev/project-9118634e-c9f1-4f29-804/tripplanning/tripplanning-backend:628b8c14eb895c4dd74f8561b5be4434fd4be6cc
  - Service account: tripplanning-dev-be-rt
  - Cloud SQL instance: project-9118634e-c9f1-4f29-804:europe-west1:tripplanning-dev-pg
  - Env vars: SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, SPRING_DATASOURCE_DRIVER_CLASS_NAME, CORS_ALLOWED_ORIGINS, ELASTICSEARCH_*, TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID, TRIPPLANNING_AUTH_JWT_SECRET, TRIPPLANNING_SEARCH_ELASTICSEARCH_INDEX_NAME, SPRING_CLOUD_GCP_IMPERSONATE_SERVICE_ACCOUNT
  - Secret env vars: tripplanning-db-password, tbd-es-gateway-elastic-password
- tripplanning-frontend
  - Image: europe-west1-docker.pkg.dev/project-9118634e-c9f1-4f29-804/tripplanning/tripplanning-frontend:20260417-074411
  - Service account: 1001763908245-compute@developer.gserviceaccount.com

### Domain mappings (region: europe-west1)
- api.paas.tbd-htwg.de -> tripplanning-backend (automatic cert)
- paas.tbd-htwg.de -> tripplanning-frontend (automatic cert)

## Cloud SQL (PostgreSQL 15)
### Instances
- tripplanning-dev-pg (region: europe-west1, zone: europe-west1-b)
  - Tier: db-custom-1-3840, disk: 10 GB SSD, backups disabled
  - Public IP: 35.187.162.117
- tripplanning-pg (region: europe-west1, zone: europe-west1-b)
  - Tier: db-custom-1-3840, disk: 10 GB SSD, backups disabled
  - Public IP: 146.148.120.187

### Databases
- tripplanning-dev-pg: postgres, tripplanning-dev
- tripplanning-pg: postgres, tripplanning

### Users
- tripplanning-dev-pg: postgres, tripplanning_app
- tripplanning-pg: postgres, tripplanning_app

## Artifact Registry
- Repository: tripplanning (europe-west1, format: DOCKER)

## Secret Manager
- tbd-es-gateway-elastic-password
- tbd-es-gateway-gcp-sa-json
- tbd-es-gateway-ghcr-token
- tripplanning-db-password

## Cloud Storage
### Buckets
- project-9118634e-c9f1-4f29-804-frontend-bucket (EU, website config: index.html)
- project-9118634e-c9f1-4f29-804-tripplanning-dev-frontend (EU, website config: index.html)
- project-9118634e-c9f1-4f29-804-images-bucket (EUROPE-WEST1, CORS configured, public access prevention enforced)
- project-9118634e-c9f1-4f29-804-tbd-es-assets (EUROPE-WEST1)

### Bucket CORS (images bucket)
- Origins: http://localhost:5173, http://127.0.0.1:5173, https://tbd-htwg.de, https://www.tbd-htwg.de, https://iaas.tbd-htwg.de, https://small-iaas.tbd-htwg.de, https://medium-iaas.tbd-htwg.de, https://large-iaas.tbd-htwg.de, https://paas-dev.tbd-htwg.de, https://paas.tbd-htwg.de
- Methods: OPTIONS, PUT, GET, HEAD

## Load Balancing (HTTPS, global)
### Forwarding rules
- tripplanning-lb-https-rule -> targetHttpsProxy tripplanning-lb-https-proxy (IP 34.49.234.167, port 443)
- tripplanning-dev-lb-https-rule -> targetHttpsProxy tripplanning-dev-lb-https-proxy (IP 34.102.253.112, port 443)

### Target HTTPS proxies
- tripplanning-lb-https-proxy -> urlMap tripplanning-lb, sslCert tripplanning-certs
- tripplanning-dev-lb-https-proxy -> urlMap tripplanning-dev-lb, sslCert tripplanning-dev-certs

### URL maps
- tripplanning-lb
  - Hosts: paas.tbd-htwg.de -> backend bucket tripplanning-frontend-backend
  - Hosts: api.paas.tbd-htwg.de -> backend service tripplanning-api-backend
- tripplanning-dev-lb
  - Hosts: paas-dev.tbd-htwg.de -> backend bucket tripplanning-dev-frontend-backend
  - Hosts: api.paas-dev.tbd-htwg.de -> backend service tripplanning-dev-api-backend

### Backend services (serverless NEGs)
- tripplanning-api-backend -> NEG tripplanning-backend-neg
- tripplanning-dev-api-backend -> NEG tripplanning-dev-neg

### Backend buckets (CDN enabled)
- tripplanning-frontend-backend -> bucket project-9118634e-c9f1-4f29-804-frontend-bucket
- tripplanning-dev-frontend-backend -> bucket project-9118634e-c9f1-4f29-804-tripplanning-dev-frontend

### SSL certificates (managed)
- tripplanning-certs (paas.tbd-htwg.de, api.paas.tbd-htwg.de)
- tripplanning-dev-certs (paas-dev.tbd-htwg.de, api.paas-dev.tbd-htwg.de)

### Network Endpoint Groups
- tripplanning-backend-neg (Cloud Run: tripplanning-backend, europe-west1)
- tripplanning-dev-neg (Cloud Run: tripplanning-dev-backend, europe-west1)

## Compute Engine
### Instances
- tbd-es-gateway (europe-west1-b, e2-standard-2)
  - External IP: 34.53.158.120
  - Service account: tbd-es-vm
  - Tags: tripplanning-es-gateway
  - Metadata includes startup script and ES config keys
- instance-20260330-145329 (europe-west3-c, e2-medium, terminated)
  - Service account: 1001763908245-compute@developer.gserviceaccount.com
  - Tags: http-server, https-server

### Firewall rules (default network)
- default-allow-ssh, default-allow-rdp, default-allow-icmp, default-allow-internal, default-allow-http, default-allow-https
- tbd-es-gateway-http-https (ports 80/443, tag: tripplanning-es-gateway)

### Network and subnets
- VPC: default (auto mode)
- Auto subnets exist in many regions, including europe-west1 (10.132.0.0/20) and europe-west3 (10.156.0.0/20)

## Cloud DNS
### Managed zones
- tbd-example-zone (public) for tbd-htwg.de.

### Record sets (A records)
- es.tbd-htwg.de -> 34.53.158.120
- iaas.tbd-htwg.de -> 34.185.182.163
- api.iaas.tbd-htwg.de -> 34.185.182.163
- paas.tbd-htwg.de -> 34.49.234.167
- api.paas.tbd-htwg.de -> 34.49.234.167
- paas-dev.tbd-htwg.de -> 34.102.253.112
- api.paas-dev.tbd-htwg.de -> 34.102.253.112
- paas-stag.tbd-htwg.de -> 34.96.64.41
- api.paas-stag.tbd-htwg.de -> 34.96.64.41

## Logging
- Log sinks: _Required, _Default

## Pub/Sub
- Topics: none
- Subscriptions: none

## Not found / not enabled
- Cloud Functions: API disabled (listing blocked, SERVICE_DISABLED)
- Cloud Scheduler: API disabled (listing blocked, SERVICE_DISABLED)
- Health checks: none
- Static IP addresses: none (explicit)