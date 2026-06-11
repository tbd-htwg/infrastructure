# 2 Runtime View

## 2.1 Runtime Overview

Runtime is on GCP project `tbd-cloudappdev` in `europe-west1`.

- Frontend: React/Vite static build served from Cloud Storage bucket `tbd-cloudappdev-frontend-bucket` through a global HTTPS Load Balancer on `https://k8s.tbd-htwg.de`. HTTP is redirected to HTTPS.
- Backend: GKE Autopilot cluster `tripplanning-gke`, private nodes, Gateway API enabled, VPC-native networking.
- API gateway: GKE Gateway `tripplanning-gateway` with class `gke-l7-global-external-managed`, static address `tripplanning-api-gateway-ip`, TLS from cert-manager/Let's Encrypt, host `https://api.k8s.tbd-htwg.de`.
- Routing: API traffic is intended to use `https://api.k8s.tbd-htwg.de`. `HTTPRoute tripplanning-api` maps API paths to `trip-service`, `social-service`, `external-info-service`, or `api-router`.
- Async/background services: none visible in the active deployment manifests. `seedJob` exists in the chart but is disabled.
- Supporting services: External Secrets Operator syncs GCP Secret Manager secrets into Kubernetes; cert-manager issues TLS certs; Flux reconciles GitOps manifests. This follows the 12-Factor idea of externalized config/secrets and treating backing services as attached resources.

#TODO: Current Terraform/frontend workflow files still contain the older same-origin `/api/*` frontend-LB setup (`api_backend_neg_self_links` and frontend build logic that forces an empty `VITE_API_BASE_URL`). If the final architecture only uses `api.k8s.tbd-htwg.de` for backend traffic, remove or update those parts.

Running links:

- Frontend: `https://k8s.tbd-htwg.de`
- API: `https://api.k8s.tbd-htwg.de`
- GCP project/environment: `tbd-cloudappdev`

## 2.2 Microservices

### api-router

- Runtime: Nginx `1.27-alpine`, port `8088`, 2 replicas in the active `tripplanning-free` values.
- Purpose: routes selected `/api/v2/...` requests internally to `trip-service`, `social-service`, or `external-info-service`.
- Scaling: manual replicas only; no HPA for `api-router`.
- Security: exposed through GCP NEG and load balancer/Gateway routes; health endpoint `/healthz`.
- External services: none directly. The router is stateless and disposable, which matches the 12-Factor process model.

### trip-service

- Runtime: image `ghcr.io/tbd-htwg/backend/tripplanning-trip-service:latest`, Spring profile `k8s`, port `8080`, 2 replicas.
- Scaling: HPA enabled, min 2, max 4, CPU target 70%.
- Security: Firebase project configured via `TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`; JWT/internal/test bearer secrets come from Secret Manager via External Secrets. Uses Workload Identity through the namespace default service account.
- External services: PostgreSQL, OpenSearch, Valkey, `social-service`, `external-info-service`, GCS image bucket `tbd-cloudappdev-images-bucket`, Firebase auth. Runtime config is provided through Kubernetes ConfigMaps, Secrets, and environment variables instead of hard-coded values.

### social-service

- Runtime: image `ghcr.io/tbd-htwg/backend/tripplanning-social-service:latest`, Spring profile `cloud`, port `8081`, 1 replica.
- Scaling: HPA enabled, min 1, max 4.
- Security: Firebase project configured; JWT/internal/test bearer secrets from Secret Manager.
- External services: Firestore database `tbd-firestore`, Valkey, `trip-service`. The `trip-service` connection is visible through `TRIPPLANNING_TRIP_SERVICE_URL`. Persistent state is outside the service container, so replicas can be added or replaced without moving local application state.

### external-info-service

- Runtime: image `ghcr.io/tbd-htwg/backend/tripplanning-external-info-service:latest`, port `8082`, 1 replica.
- Scaling: HPA enabled, min 1, max 4.
- Security: JWT/internal/test bearer secrets from Secret Manager.
- External services: Valkey, Google Maps API key, optional Viator API key. No internal trip-service URL is configured for this service in the deployment values. Third-party integrations are configured as external backing services and secrets.

## 2.3 Datastores

- PostgreSQL: in-cluster `StatefulSet postgres`, database `tripplanning`, user `tripplanning_app`, password from `trip-service-secrets`, 1 Gi PVC using `standard-hdd-wffc`.
- OpenSearch: in-cluster `StatefulSet elasticsearch`, image `opensearchproject/opensearch:2.19.0`, single node, security plugin disabled, 1 Gi PVC using `standard-hdd-wffc`.
- Valkey: in-cluster cache deployment, no persistent volume.
- Firestore: native database `tbd-firestore` in `europe-west1`; used by `social-service`; composite index on `comments(tripId ASC, createdAt DESC, __name__ DESC)`.
- Cloud Storage:
  - `tbd-cloudappdev-images-bucket`: image storage, CORS for `https://k8s.tbd-htwg.de`.
  - `tbd-cloudappdev-frontend-bucket`: static frontend assets, website fallback to `index.html`, public read.
  - `tbd-cloudappdev-tfstate`: Terraform state.
  - `tbd-cloudappdev-project-logs`: GKE container/pod log sink.

These datastores are separated from the application containers, which supports the 12-Factor backing-services principle.

#TODO: Add the actual application data model/ER diagram or schemas. The deployment files show the storage systems, but not the full table/document/index schema.

## 2.4 Security: Roles and Role Mapping

- `frontend-deployer`: used by frontend GitHub Actions through Workload Identity Federation. Has object admin/read access on the frontend bucket and `roles/compute.loadBalancerAdmin` for CDN/load balancer cache invalidation.
- `secrets-deployer`: used by backend secret sync workflow through Workload Identity Federation. Has `roles/secretmanager.admin` and `roles/secretmanager.secretAccessor`.
- `workload`: used by in-cluster workloads through GKE Workload Identity. Has `roles/datastore.user`, `roles/secretmanager.secretAccessor`, `roles/artifactregistry.reader`, `roles/dns.admin`, and permission to impersonate `tripplanning-image-url-sig`.
- `tripplanning-image-url-sig`: has object viewer/creator on the images bucket and is used for signed image upload/access URLs.
- `external-secrets/external-secrets`, `cert-manager/cert-manager`, `tripplanning-free/trip-service`, and `tripplanning-free/default` Kubernetes service accounts can impersonate `workload`.
- Secrets are stored in GCP Secret Manager and projected to Kubernetes with External Secrets. This keeps credentials out of images and source-controlled manifests.

## 2.5 Infrastructure as Code

- Terraform environment: `infrastructure/ms2/terraform/envs/dev`.
- Terraform modules create project APIs, service accounts/IAM, VPC/subnet/NAT, GKE Autopilot, buckets, Firestore, Secret Manager secrets, DNS, frontend HTTPS load balancer, API gateway IP, and GitHub Workload Identity Federation.
- GitOps: Flux bootstraps `infrastructure/ms2/gitops/clusters/dev`, then reconciles platform config, gateway, and tenant manifests.
- Helm chart: `infrastructure/ms2/charts/tripplanning` deploys the backend services, router, backing services, routes, HPAs, config, and secrets references.
- Active tenant values come from `gitops/tenants/free/shared/values-configmap.yaml`.
- Present but not active in the deployment path: Cloud SQL module, KMS disabled, observability commented out, chart `seedJob` disabled.
- The split between Terraform, GitOps manifests, and Helm values supports repeatable environments and a clear build/release/run separation.

# 3 Development View

## 3.1 Software Components

- Repositories referenced by the deployment:
  - `tbd-htwg/frontend`: React/Vite SPA, built by GitHub Actions and uploaded to Cloud Storage.
  - `tbd-htwg/backend`: container images for `trip-service`, `social-service`, `external-info-service`, and `seed-job`, published to GHCR.
  - Infrastructure/GitOps under `infrastructure/ms2`.
- Components:
  - Frontend SPA.
  - `trip-service`: main trip API, PostgreSQL/OpenSearch/Valkey/GCS integration.
  - `social-service`: comments/likes/community features, Firestore/Valkey integration.
  - `external-info-service`: external travel/info API integration.
  - `api-router`: Nginx path router for API compatibility/routing.
- Languages/frameworks visible from deployment files:
  - Frontend: Node.js 20, npm, Vite/React.
  - Backend: Spring Boot services inferred from `SPRING_*` config and Actuator health endpoints.
  - Infrastructure: Terraform, Kubernetes YAML, Kustomize, Helm, Flux.

#TODO: Add exact backend languages, frameworks, and important libraries from the application source code. They are not fully visible from the allowed IaC/pipeline files.

## 3.2 Pipelines

- Frontend `deploy-gcp-gke.yml`:
  - Runs on `workflow_dispatch`; planned/added trigger: push to `main`.
  - Installs Node.js 20 dependencies with `npm ci`.
  - Builds with Vite env vars for same-origin API, Firebase, and Google Maps.
  - Authenticates to GCP via Workload Identity Federation.
  - Uploads `dist` to the frontend Cloud Storage bucket.
  - Sets `index.html` no-cache and invalidates the frontend URL map CDN cache.
  - Separates build output from deployment configuration, close to the 12-Factor build/release/run model.

- Backend `docker-publish-gke.yml`:
  - Runs on `workflow_dispatch`; planned/added trigger: push to `main`.
  - Builds and pushes GHCR images for `trip`, `social`, `external-info`, and `seed-job`.
  - Tags each image with both the Git SHA and `latest`.
  - The active Helm values deploy `latest` images, so Flux/GKE pull the newest published images when reconciled/restarted.
  - Produces immutable container artifacts per commit SHA; runtime config is injected later by Kubernetes.

- Backend `sync-gke-secrets.yml`:
  - Runs manually, every 2 hours, and on repository dispatch events.
  - Authenticates to GCP with Workload Identity Federation.
  - Creates/updates GCP Secret Manager secrets for DB password, JWT/internal secrets, Google Maps, Viator, test bearer token, and GHCR pull config.
  - External Secrets Operator reconciles these values into `tripplanning-free`.
  - Keeps secret/config management outside the container image lifecycle.
