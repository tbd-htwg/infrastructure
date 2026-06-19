# CPU and replicas — executive summary

Before (pre-tuning GitOps) vs after (implemented for 16-vCPU Autopilot dev). Autopilot schedules on **CPU requests**; effective totals add ~100m Envoy sidecar request per injected app pod. Detail: [cpu-and-replicas-before.md](cpu-and-replicas-before.md), [cpu-and-replicas-after.md](cpu-and-replicas-after.md).

---

## Before

| Tier | Component | Replicas | HPA min | HPA max | CPU request | CPU limit |
|------|-----------|----------|---------|---------|-------------|-----------|
| **Free** | api-router | 2 | — | — | 50m | 200m |
| **Free** | trip-service | 1 | 1 | 2 | 250m | 1000m |
| **Free** | social-service | 1 | 1 | 4 | 250m | 750m |
| **Free** | external-info | 1 | 1 | 4 | 250m | 750m |
| **Free** | postgres | 1 | — | — | 100m | 500m |
| **Free** | valkey | 1 | — | — | 50m | 250m |
| **Free** | opensearch | 1 | — | — | 250m | 1000m |
| **Standard** | api-router | 1 | — | — | 50m | 200m |
| **Standard** | trip-service | 1 (0 in cluster) | — | — | 250m | 750m |
| **Standard** | cloud-sql-proxy | per trip pod | — | — | 50m | 250m |
| **Standard** | social-service | 1 | — | — | 150m | 500m |
| **Standard** | external-info | 1 | — | — | 100m | 500m |
| **Standard** | valkey | 1 | — | — | 25m | 100m |
| **Standard** | opensearch | 1 | — | — | 100m | 500m |
| **Enterprise** | api-router | 2 | — | — | 50m | 200m |
| **Enterprise** | trip-service | 2 | 2 | 8 | 500m | 2000m |
| **Enterprise** | cloud-sql-proxy | per trip pod | — | — | 50m | 250m |
| **Enterprise** | social-service | 2 | 2 | 8 | 200m | 750m |
| **Enterprise** | external-info | 1 | 2 | 8 | 150m | 500m |
| **Enterprise** | opensearch | 1 | — | — | 500m | 1000m |
| **Enterprise** | valkey | 1 | — | — | 50m | 150m |
| **Flux** | source-controller | 1 | — | — | 50m | 1000m |
| **Flux** | kustomize-controller | 1 | — | — | 100m | 1000m |
| **Flux** | helm-controller | 1 | — | — | 100m | 1000m |
| **Flux** | notification-controller | 1 | — | — | 100m | 1000m |

### Before — CPU totals (approx.)

| Scope | Scenario | Declared CPU requests | Effective (+ Envoy) |
|-------|----------|----------------------|---------------------|
| Free | Steady (min) | 1.25 cores | **~1.75 cores** |
| Free | HPA max | 3.0 cores | **~4.2 cores** |
| Standard | trip = 1 (+ proxy) | 0.73 cores | **~1.1 cores** |
| Standard | trip = 0 (cluster) | 0.43 cores | **~0.7 cores** |
| Enterprise (globex) | Steady (min) | 2.3 cores | **~3.0 cores** |
| Enterprise (globex) | HPA max | 7.85 cores | **~10.5 cores** |
| Flux | always on | 0.35 cores | 0.35 cores |
| **Dev cluster** | Free min + Standard trip=0 + Flux | ~2.0 cores | **~2.8 cores** |

---

## After

| Tier | Component | Replicas | HPA min | HPA max | CPU request | CPU limit |
|------|-----------|----------|---------|---------|-------------|-----------|
| **Free** | api-router | **1** | — | — | 50m | 200m |
| **Free** | trip-service | 1 | — | — | **150m** | **400m** |
| **Free** | social-service | 1 | — | — | **150m** | **400m** |
| **Free** | external-info | 1 | — | — | **100m** | **300m** |
| **Free** | postgres | 1 | — | — | 100m | **250m** |
| **Free** | valkey | 1 | — | — | 50m | **100m** |
| **Free** | opensearch | 1 | — | — | **200m** | **500m** |
| **Standard** | api-router | 1 | — | — | 50m | 200m |
| **Standard** | trip-service | 1 | **1** | **2** | 250m | 750m |
| **Standard** | cloud-sql-proxy | per trip pod | — | — | 50m | **150m** |
| **Standard** | social-service | 1 | **1** | **2** | 150m | 500m |
| **Standard** | external-info | 1 | **1** | **2** | 100m | 500m |
| **Standard** | valkey | 1 | — | — | 25m | 100m |
| **Standard** | opensearch | 1 | — | — | 100m | **400m** |
| **Enterprise** | api-router | 2 | — | — | 50m | 200m |
| **Enterprise** | trip-service | 2 | 2 | **4** | 500m | **1000m** |
| **Enterprise** | cloud-sql-proxy | per trip pod | — | — | 50m | **150m** |
| **Enterprise** | social-service | 2 | 2 | **4** | 200m | **500m** |
| **Enterprise** | external-info | 1 | **1** | **2** | 150m | 500m |
| **Enterprise** | opensearch | 1 | — | — | 500m | **750m** |
| **Enterprise** | valkey | 1 | — | — | 50m | 150m |
| **Flux** | source-controller | 1 | — | — | 50m | **500m** |
| **Flux** | kustomize-controller | 1 | — | — | 100m | **500m** |
| **Flux** | helm-controller | 1 | — | — | 100m | **500m** |
| **Flux** | notification-controller | 1 | — | — | 100m | **500m** |

### After — CPU totals (approx.)

| Scope | Scenario | Declared CPU requests | Effective (+ Envoy) |
|-------|----------|----------------------|---------------------|
| Free | Steady (only profile) | **0.80 cores** | **~1.2 cores** |
| Free | HPA max | — | **N/A** (HPA off) |
| Standard | min (trip = 1) | 0.73 cores | **~1.1 cores** |
| Standard | HPA max (2+2+2) | 1.28 cores | **~1.9 cores** |
| Standard | trip = 0 (no tenants) | 0.43 cores | **~0.7 cores** |
| Enterprise (globex) | Steady (min) | 2.3 cores | **~3.0 cores** |
| Enterprise (globex) | HPA max | **~3.95 cores** | **~5.2 cores** |
| Flux | always on | 0.35 cores | 0.35 cores |
| **Dev cluster** | Free + Standard trip=0 + Flux | **~1.6 cores** | **~2.3 cores** |

---

## Headline deltas (CPU and replicas)

| Area | Before | After |
|------|--------|-------|
| Free api-router replicas | 2 | **1** |
| Free HPA | on (up to 12 app pods) | **off** |
| Free steady CPU (effective) | ~1.75 cores | **~1.2 cores** |
| Free under load (effective) | up to ~4.2 cores | **~1.2 cores** |
| Standard HPA | off | **on, max 2 per service** |
| Standard HPA max (effective) | ~1.1 cores | **~1.9 cores** |
| Enterprise HPA max (trip/social/ext) | 8 / 8 / 8 | **4 / 4 / 2** |
| Enterprise trip CPU limit | 2000m | **1000m** |
| Flux CPU limits (total) | 4000m | **2000m** |
| Dev cluster steady (effective) | ~2.8 cores | **~2.3 cores** |
