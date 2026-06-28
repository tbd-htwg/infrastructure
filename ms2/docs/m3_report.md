# M3 Report

## 2 Runtime View

### 2.1 Runtime Overview

TripPlanning runs on Google Cloud. The user opens the React frontend at
`https://k8s.tbd-htwg.de`. A global HTTPS load balancer serves static frontend
files from Cloud Storage and forwards API calls to GKE.

The backend runs on GKE Autopilot. API traffic first reaches the `api-router`,
which selects the tenant by hostname and forwards requests to the correct
microservice. Persistent data is stored in Cloud SQL, Firestore, Cloud Storage,
OpenSearch, and Valkey.

Tenant provisioning is asynchronous. The platform service triggers
infrastructure automation, Terraform creates cloud resources, and Flux applies
Kubernetes resources.

### 2.2 Microservices

| Service | Responsibility | Runtime and scaling | Security and tenant isolation |
| --- | --- | --- | --- |
| `api-router` | Routes API paths and injects tenant headers | nginx Deployment, 1-2 replicas depending on tier | Enforces known hosts for paid tiers and forwards tenant identity headers |
| `trip-service` | Main trip API, trips, users, search, image access | Spring Boot service, HPA in Standard and Enterprise | Uses tenant context, Cloud SQL routing, search/cache/storage tenant settings |
| `social-service` | Likes and comments | Spring Boot service, HPA in Standard and Enterprise | Uses tenant context and Firestore tenant data |
| `external-info-service` | External travel/detail data | Spring Boot service, HPA in Standard and Enterprise | Uses tenant context and cached external lookups |
| `customfield-service` | Enterprise custom fields | Spring Boot service, enabled for Enterprise | Enterprise-only feature, tenant-scoped Firestore data |
| `platform-service` | Tenant registry, admin APIs, provisioning | Spring Boot service in `tripplanning-system` | Admin-protected APIs, Identity Platform integration, provisioning callbacks |

Services are configured with environment variables, ConfigMaps, Secrets,
resource requests/limits, and health probes. This keeps images reusable across
environments and tiers.

### 2.3 Datastores

| Datastore | Used for | Tenant isolation |
| --- | --- | --- |
| Cloud SQL PostgreSQL | Trip data and platform tenant registry | Standard uses tenant databases/users on a shared instance; Enterprise uses dedicated instances |
| Firestore | Comments, likes, custom fields | Tenant-aware collections and IDs |
| Cloud Storage frontend bucket | Static React assets | Build channel prefixes such as dev/prod |
| Cloud Storage image bucket | Trip images and branding | Shared prefix for Free/Standard, dedicated image bucket for Enterprise |
| OpenSearch | Trip search | Tenant-specific index naming; Enterprise gets dedicated release/service |
| Valkey | Cache | Prefix-based isolation or dedicated Enterprise cache |

Data models are owned by the services. SQL schemas are versioned with service
migrations; Firestore collections are documented through service code and tests.

### 2.4 Security: Roles and Role Mapping

Google Cloud service accounts separate responsibilities:

- `frontend-deployer`: frontend deployment from GitHub Actions.
- backend deployer service account: backend image rollout to GKE.
- `terraform-deployer`: infrastructure changes.
- `workload`: Kubernetes application workloads.
- `platform-admin`: platform service operations.
- `image_url_sig`: signed image URL access.
- `gitops`: GitOps-related access.
- `gke-nodes`: GKE node service account.

Workload Identity Federation is used for GitHub Actions. Kubernetes workloads
use annotated service accounts where cloud access is needed. Secrets are kept in
Secret Manager and synced by External Secrets.

### 2.5 Infrastructure as Code

The infrastructure is organized in `infrastructure/ms2`:

- Terraform manages durable cloud resources.
- Flux manages Kubernetes state.
- Helm defines the application runtime.
- Tenant YAML files define tenant inputs.
- `render-tenants.py` generates Terraform and GitOps output.

This structure makes cloud resources reproducible while keeping runtime
configuration reviewable and tenant changes automated.

### 2.6 Monitoring

Monitoring uses Google Cloud Managed Service for Prometheus and normal GKE
observability. Spring Boot services expose Actuator Prometheus metrics, and
ClusterPodMonitoring resources scrape them every 30 seconds.

Logs are written to stdout/stderr and available in Cloud Logging. GKE workload
views show pod health, restarts, resource usage, service status, and rollouts.
Mesh telemetry adds request metrics, tracing, and access logs.

## 3 Development View

### 3.1 Software Components

Source repositories:

- Backend: `backend`
- Frontend: `frontend`
- Infrastructure: `infrastructure/ms2`

Backend:

- Java 21
- Spring Boot 3.5
- Maven multi-module project
- Modules: common, trip, social, external-info, platform, customfield, seed job
- Important libraries: Spring Security, OAuth2 Resource Server, Spring Data JPA,
  Spring Data Redis, Spring Cloud GCP, Hibernate Search, Actuator, Micrometer

Frontend:

- TypeScript
- React 19
- Vite
- Firebase client SDK
- Google Maps integration
- React Router
- Tailwind CSS

Infrastructure:

- Terraform for Google Cloud resources
- Flux and Kustomize for GitOps
- Helm for Kubernetes application templates
- GitHub Actions for build and deployment

### 3.2 Pipelines and Release of New Features

Backend releases use `docker-publish-gke.yml`. The pipeline detects changed
services, builds only needed images, pushes them to GHCR, updates Kubernetes
Deployment images, and waits for rollout. `develop` deploys to Free. `main`
deploys to Standard and Enterprise.

Frontend releases use `deploy-gcp-gke.yml`. The pipeline builds the React app,
uploads static files to Cloud Storage, writes version metadata, and invalidates
the load balancer cache. `develop` publishes the dev channel. `main` publishes
the prod channel.

Infrastructure and tenant lifecycle are handled separately through Terraform,
GitOps, tenant YAML, and the tenant renderer. This keeps application releases
fast while infrastructure changes remain controlled.

