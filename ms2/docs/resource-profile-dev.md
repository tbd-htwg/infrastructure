# Dev resource profile (Minikube + GKE ms2)

Pod **CPU requests** drive GKE Autopilot node sizing; **limits** cap burst. Target for the
tripplanning app stack (excluding GKE system / Managed Prometheus):

| Target | Value |
|--------|--------|
| CPU requests (sum) | ~2.5–3.5 vCPU |
| CPU limits (sum, all pegged) | ~5.5–6 vCPU (within 8–16 dev aim) |
| Memory limits (sum) | ~5.5 GiB workloads + ~0.4 GiB frontend/proxy |

Project quota ceiling: **24 vCPU** — this profile leaves headroom for Autopilot overhead and
`gke-gmp-system`.

## Workloads

| Component | CPU request | CPU limit | Memory request | Memory limit | Notes |
|-----------|-------------|-----------|----------------|--------------|--------|
| **trip-service** | 1000m | 2000m | 768Mi | 1536Mi | JVM + Hibernate Search + H2/Postgres |
| **social-service** | 300m | 750m | 384Mi | 768Mi | Firestore client |
| **external-info-service** | 300m | 750m | 384Mi | 768Mi | Redis cache + outbound HTTP |
| **elasticsearch** | 500m | 1000m | 768Mi | 1536Mi | `ES_JAVA_OPTS=-Xms512m -Xmx512m` |
| **redis** | 100m | 250m | 128Mi | 256Mi | |
| **firestore-emulator** (local only) | 100m | 250m | 256Mi | 512Mi | |
| **cloud-sql-proxy** (GKE only) | 50m | 100m | 64Mi | 128Mi | trip-service sidecar |
| **frontend** (GKE only) | 100m | 250m | 128Mi | 256Mi | nginx + init |

**Minikube:** set `MINIKUBE_MEMORY=24576` (24 GiB) or at least `12288` (12 GiB) so ES + JVMs fit.

Manifests: `ms2/k8s/dependencies/`, `ms2/gitops/tenants/tripplanning/`, `backend/k8s/local/`.
