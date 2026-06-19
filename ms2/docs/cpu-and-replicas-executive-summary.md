# CPU and replicas — executive summary

One-page comparison of **before** (pre-tuning GitOps, Jun 2026) vs **after** (implemented limits and replica policy for 16-vCPU Autopilot dev).

Autopilot schedules on **CPU requests**. **Effective** columns add ~100m Envoy sidecar request per injected app pod (mesh). Details: [cpu-and-replicas-before.md](cpu-and-replicas-before.md), [cpu-and-replicas-after.md](cpu-and-replicas-after.md).

---

## Before

| Tier | Component | Replicas (static) | HPA min | HPA max | HPA target | CPU request | CPU limit | Mem req | Mem limit | Sidecar | Notes |
|------|-----------|-------------------|---------|---------|------------|-------------|-----------|---------|-----------|---------|-------|
| **Free** | api-router | 2 | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | chart default |
| **Free** | trip-service | 1 | 1 | 2 | CPU 70% | 250m | 1000m | 512Mi | 1024Mi | yes | |
| **Free** | social-service | 1 | 1 | 4 | CPU 80%, mem 75% | 250m | 750m | 384Mi | 768Mi | yes | |
| **Free** | external-info | 1 | 1 | 4 | CPU 80%, mem 75% | 250m | 750m | 384Mi | 768Mi | yes | |
| **Free** | postgres | 1 | — | — | — | 100m | 500m | 256Mi | 512Mi | no | |
| **Free** | valkey | 1 | — | — | — | 50m | 250m | 256Mi | 512Mi | no | |
| **Free** | opensearch | 1 | — | — | — | 250m | 1000m | 768Mi | 1280Mi | no | |
| **Standard** | api-router | 1 | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | chart default |
| **Standard** | trip-service | 1 (0 in cluster) | — | — | HPA off | 250m | 750m | 384Mi | 768Mi | yes | + proxy 50m / 250m |
| **Standard** | social-service | 1 | — | — | HPA off | 150m | 500m | 256Mi | 512Mi | yes | |
| **Standard** | external-info | 1 | — | — | HPA off | 100m | 500m | 192Mi | 384Mi | yes | |
| **Standard** | valkey | 1 | — | — | — | 25m | 100m | 64Mi | 128Mi | no | |
| **Standard** | opensearch | 1 | — | — | — | 100m | 500m | 384Mi | 768Mi | no | |
| **Enterprise** | api-router | 2 | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | per tenant |
| **Enterprise** | trip-service | 2 | 2 | 8 | CPU 70% | 500m | 2000m | 768Mi | 2Gi | yes | globex example |
| **Enterprise** | cloud-sql-proxy | per trip pod | — | — | — | 50m | 250m | 64Mi | 256Mi | no | |
| **Enterprise** | social-service | 2 | 2 | 8 | CPU 70% | 200m | 750m | 384Mi | 768Mi | yes | chart default |
| **Enterprise** | external-info | 1 | 2 | 8 | CPU 70% | 150m | 500m | 256Mi | 512Mi | yes | |
| **Enterprise** | opensearch | 1 | — | — | — | 500m | 1000m | 1Gi | 2Gi | no | |
| **Enterprise** | valkey | 1 | — | — | — | 50m | 150m | 128Mi | 256Mi | no | |
| **Flux** | source-controller | 1 | — | — | — | 50m | 1000m | 64Mi | 1Gi | no | |
| **Flux** | kustomize-controller | 1 | — | — | — | 100m | 1000m | — | 1Gi | no | |
| **Flux** | helm-controller | 1 | — | — | — | 100m | 1000m | — | 1Gi | no | |
| **Flux** | notification-controller | 1 | — | — | — | 100m | 1000m | — | 1Gi | no | |

### Before — quota footprint (approx.)

| Scope | Scenario | Declared CPU requests | Effective (+ Envoy) |
|-------|----------|----------------------|---------------------|
| Free | Steady (min) | 1.25 cores | **~1.75 cores** |
| Free | HPA max | 3.0 cores | **~4.2 cores** |
| Standard | trip = 1 (+ proxy) | 0.73 cores | **~1.1 cores** |
| Standard | trip = 0 (cluster) | 0.43 cores | **~0.7 cores** |
| Enterprise (globex) | Steady (min) | 2.3 cores | **~3.0 cores** |
| Enterprise (globex) | HPA max | 7.85 cores | **~10.5 cores** |
| Flux | always on | 0.35 cores | 0.35 cores (no sidecars) |
| **Dev cluster** | Free min + Standard trip=0 + Flux | ~2.0 cores | **~2.8 cores** |

Namespace quotas: Standard **12** CPU req / **32** limit; Enterprise **16** / **48** per tenant.

---

## After

| Tier | Component | Replicas (static) | HPA min | HPA max | HPA target | CPU request | CPU limit | Mem req | Mem limit | Sidecar | Notes |
|------|-----------|-------------------|---------|---------|------------|-------------|-----------|---------|-----------|---------|-------|
| **Free** | api-router | **1** | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | |
| **Free** | trip-service | 1 | — | — | **HPA off** | **150m** | **400m** | **256Mi** | **512Mi** | yes | |
| **Free** | social-service | 1 | — | — | **HPA off** | **150m** | **400m** | **256Mi** | **512Mi** | yes | |
| **Free** | external-info | 1 | — | — | **HPA off** | **100m** | **300m** | **128Mi** | **256Mi** | yes | |
| **Free** | postgres | 1 | — | — | — | 100m | **250m** | 256Mi | 512Mi | no | |
| **Free** | valkey | 1 | — | — | — | 50m | **100m** | 256Mi | 512Mi | no | |
| **Free** | opensearch | 1 | — | — | — | **200m** | **500m** | 768Mi | 1280Mi | no | |
| **Standard** | api-router | 1 | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | |
| **Standard** | trip-service | 1 | **1** | **2** | CPU **70%** | 250m | 750m | 384Mi | 768Mi | yes | + proxy 50m / **150m** |
| **Standard** | social-service | 1 | **1** | **2** | CPU **70%** | 150m | 500m | 256Mi | 512Mi | yes | |
| **Standard** | external-info | 1 | **1** | **2** | CPU **70%** | 100m | 500m | 192Mi | 384Mi | yes | |
| **Standard** | valkey | 1 | — | — | — | 25m | 100m | 64Mi | 128Mi | no | |
| **Standard** | opensearch | 1 | — | — | — | 100m | **400m** | 384Mi | 768Mi | no | |
| **Enterprise** | api-router | 2 | — | — | — | 50m | 200m | 64Mi | 128Mi | yes | |
| **Enterprise** | trip-service | 2 | 2 | **4** | CPU 70% | 500m | **1000m** | 768Mi | 2Gi | yes | |
| **Enterprise** | cloud-sql-proxy | per trip pod | — | — | — | 50m | **150m** | 64Mi | 256Mi | no | |
| **Enterprise** | social-service | 2 | 2 | **4** | CPU 70% | 200m | **500m** | 384Mi | 768Mi | yes | |
| **Enterprise** | external-info | 1 | **1** | **2** | CPU 70% | 150m | 500m | 256Mi | 512Mi | yes | |
| **Enterprise** | opensearch | 1 | — | — | — | 500m | **750m** | 1Gi | 2Gi | no | |
| **Enterprise** | valkey | 1 | — | — | — | 50m | 150m | 128Mi | 256Mi | no | |
| **Flux** | source-controller | 1 | — | — | — | 50m | **500m** | 64Mi | 1Gi | no | Kustomize patch |
| **Flux** | kustomize-controller | 1 | — | — | — | 100m | **500m** | — | 1Gi | no | |
| **Flux** | helm-controller | 1 | — | — | — | 100m | **500m** | — | 1Gi | no | |
| **Flux** | notification-controller | 1 | — | — | — | 100m | **500m** | — | 1Gi | no | |

### After — quota footprint (approx.)

| Scope | Scenario | Declared CPU requests | Effective (+ Envoy) |
|-------|----------|----------------------|---------------------|
| Free | Steady (only profile) | **0.80 cores** | **~1.2 cores** |
| Free | HPA max | — | **N/A** (HPA disabled) |
| Standard | min (trip = 1) | 0.73 cores | **~1.1 cores** |
| Standard | HPA max (2+2+2) | 1.28 cores | **~1.9 cores** |
| Standard | trip = 0 (no tenants) | 0.43 cores | **~0.7 cores** |
| Enterprise (globex) | Steady (min) | 2.3 cores | **~3.0 cores** |
| Enterprise (globex) | HPA max | **~3.95 cores** | **~5.2 cores** |
| Flux | always on | 0.35 cores | 0.35 cores |
| **Dev cluster** | Free + Standard trip=0 + Flux | **~1.6 cores** | **~2.3 cores** |

---

## Headline deltas

| Area | Before | After | Why |
|------|--------|-------|-----|
| Free api-router | 2 replicas | **1** | No HA needed on dev |
| Free HPA | on (up to 12 app pods) | **off** | Fixed single-instance dev stack |
| Free steady CPU (effective) | ~1.75 cores | **~1.2 cores** | Lower requests + no scale-out |
| Free under load | up to ~4.2 cores | **~1.2 cores** | Locust needs temporary perf profile |
| Standard HPA | off | **on, max 2** | Modest scale without 8-replica burst |
| Standard HPA max (effective) | ~1.1 cores (fixed) | **~1.9 cores** | Can double app pods when needed |
| Enterprise HPA max (effective) | ~10.5 cores | **~5.2 cores** | max 4/4/2 instead of 8/8/8 |
| Enterprise trip CPU limit | 2000m | **1000m** | Spring Boot–sensible dev cap |
| Flux CPU limits (total) | 4000m | **2000m** | Controllers don't need 1 core each |
| Combined dev cluster (steady) | ~2.8 cores effective | **~2.3 cores effective** | More headroom on 16-vCPU quota |

---

## Files changed

| Area | Path |
|------|------|
| Free GitOps | `gitops/tenants/free/shared/values-configmap.yaml` |
| Standard GitOps | `gitops/tenants/standard/shared/values-configmap.yaml` |
| Enterprise example | `tenants/enterprise/example-globex.yaml` |
| Chart tiers | `charts/tripplanning/values-free.yaml`, `values-standard.yaml`, `values-enterprise.yaml`, `values.yaml` |
| Cloud SQL proxy limit | `charts/tripplanning/templates/deployments/trip-deployment.yaml` |
| Enterprise renderer | `scripts/render-tenants.py` |
| Flux limits | `gitops/clusters/dev/flux-system/flux-controller-cpu-limits.yaml` |

Apply on cluster: `flux reconcile kustomization tenants -n flux-system` and reconcile Free/Standard HelmReleases.
