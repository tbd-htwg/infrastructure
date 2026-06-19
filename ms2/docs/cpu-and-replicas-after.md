# CPU requests, limits, and replicas — recommended state (after)

Audited recommendations for Free, Standard, and Enterprise tenant stacks on GKE Autopilot dev, tuned for a **~16 vCPU** project quota and sensible Spring Boot JVM sizing.

**Current state:** [cpu-and-replicas-before.md](cpu-and-replicas-before.md)

This document describes **target values**, implemented in GitOps and chart defaults as of 2026-06-19.

---

## Design principles

| Principle | Rationale |
|-----------|-----------|
| **Free = single instance** | One replica of each workload; no HPA on steady-state dev |
| **Standard = shared runtime, max 2** | HPA or static scale up to **2** replicas per app service when needed |
| **Enterprise = isolated, capped HPA on dev** | Keep min 2 for HA shape; cap HPA max below chart defaults |
| **Spring Boot CPU limit ≈ 2–3× request** | JVM burst for GC/startup; avoid 2000m limits on dev without load tests |
| **Memory limit ≈ 1.25–1.5× request** | Align with `-XX:MaxRAMPercentage=75.0` already set in env |
| **Optimize requests first** | Autopilot provisions from requests; limits matter for quota accounting |
| **Locust / perf is exceptional** | Load tests need a temporary HPA profile — not the steady-state Free stack |

### Istio sidecar assumption

Injected app pods: **~100m CPU request** each (not in Helm). See [service_mesh_monitoring.md](service_mesh_monitoring.md).

---

## Tier summary

| Tier | Namespace | HPA (recommended) | NS quota ceiling | Min effective req¹ | Max effective req¹ |
|------|-----------|-------------------|------------------|--------------------|--------------------|
| Free | `tripplanning-free` | **off** | none | ~**1.0 core** | ~**1.0 core** |
| Standard | `tripplanning-standard` | **min 1 max 2 @ 70%** | 12 CPU req / 32 CPU limit | ~**0.9 core** | ~**1.8 cores** |
| Enterprise | `tripplanning-ent-{slug}` | **min 2 max 4** (trip/social), ext **max 2** | 16 CPU req / 48 CPU limit | ~**2.5 cores** | ~**5.5 cores** |

¹ Declared pod requests + estimated Envoy sidecars.

---

## Free — `tripplanning-free`

**Goal:** exactly one replica of each component; no autoscale on dev.

### Recommended changes

| Component | Replicas before → after | HPA before → after | CPU req before → after | CPU limit before → after |
|-----------|-------------------------|--------------------|------------------------|---------------------------|
| api-router | 2 → **1** | — | 50m | 200m (unchanged) |
| trip-service | 1 → **1** | 1–2 → **off** | 250m → **150m** | 1000m → **400m** |
| social-service | 1 → **1** | 1–4 → **off** | 250m → **150m** | 750m → **400m** |
| external-info | 1 → **1** | 1–4 → **off** | 250m → **100m** | 750m → **300m** |
| postgres | 1 | — | 100m | 500m → **250m** |
| valkey | 1 | — | 50m | 250m → **100m** |
| opensearch | 1 | — | 250m → **200m** | 1000m → **500m** |

Set `autoscaling.enabled: false`. Align with [values-free.yaml](../charts/tripplanning/values-free.yaml).

### Memory (recommended, unchanged pattern)

| Component | Mem req → limit |
|-----------|-----------------|
| trip-service | 256Mi → 512Mi |
| social-service | 256Mi → 512Mi |
| external-info | 128Mi → 256Mi |

### Quota impact

| Scenario | Before (effective req) | After (effective req) |
|----------|------------------------|------------------------|
| Steady | ~1.75 cores | ~**1.0 core** |
| HPA max | ~4.2 cores | **N/A** (HPA off) |

---

## Standard — `tripplanning-standard`

**Goal:** shared runtime with **up to 2** app replicas; Spring Boot limits appropriate for dev (not `values-standard.yaml` 500m/2000m trip sizing).

### Recommended changes

| Component | Replicas before → after | HPA before → after | CPU req | CPU limit before → after |
|-----------|-------------------------|--------------------|---------|---------------------------|
| api-router | 1 → **1** | off → off | 50m | 200m |
| trip-service | 1 → **1–2** | off → **min 1 max 2 @ 70%** | 250m | 750m (keep) |
| social-service | 1 → **1–2** | off → **min 1 max 2 @ 70%** | 150m | 500m (keep) |
| external-info | 1 → **1–2** | off → **min 1 max 2 @ 70%** | 100m | 500m (keep) |
| valkey | 1 | — | 25m | 100m |
| opensearch | 1 | — | 100m | 500m → **400m** |
| cloud-sql-proxy | per trip pod | — | 50m | 250m → **150m** |

Enable `autoscaling.enabled: true` with **maxReplicas: 2** on trip, social, and externalInfo. Do **not** use chart file min 2 / max 8.

When no Standard tenants are registered, keep **trip.replicas: 0** (existing scale-to-zero behavior).

### Quota impact

| Scenario | Before (effective req) | After (effective req) |
|----------|------------------------|------------------------|
| Min (trip = 1) | ~1.1 cores | ~**0.9 cores** |
| Max (2+2+2 app pods) | ~1.1 cores (HPA off today) | ~**1.8 cores** |
| Current (trip = 0) | ~0.7 cores | ~**0.6 cores** |

---

## Enterprise — per tenant (example: globex)

**Goal:** production-shaped floor (min 2) without consuming the full 16 CPU namespace quota at HPA max.

### Recommended changes

| Component | Replicas before → after | HPA min–max before → after | CPU req | CPU limit before → after |
|-----------|-------------------------|----------------------------|---------|---------------------------|
| api-router | 2 → **2** | — | 50m | 200m |
| trip-service | 2 → **2** | 2–8 → **2–4 @ 70%** | 500m | 2000m → **1000m** |
| cloud-sql-proxy | per trip pod | — | 50m | 250m → **150m** |
| social-service | 2 → **2** | 2–8 → **2–4 @ 70%** | 200m | 750m → **500m** |
| external-info | 1 → **1** | 2–8 → **1–2 @ 70%** | 150m | 500m (keep) |
| opensearch | 1 | — | 500m | 1000m → **750m** |
| valkey | 1 | — | 50m | 150m (keep) |

### Quota impact

| Scenario | Before (effective req) | After (effective req) |
|----------|------------------------|------------------------|
| Steady (min) | ~3.0 cores | ~**2.5 cores** |
| HPA max | ~10.5 cores | ~**5.5 cores** |

---

## Flux — `flux-system`

Limits are unrealistically high for dev controllers; requests are fine.

| Controller | CPU request | CPU limit before → after |
|------------|-------------|---------------------------|
| source-controller | 50m | 1000m → **500m** |
| kustomize-controller | 100m | 1000m → **500m** |
| helm-controller | 100m | 1000m → **500m** |
| notification-controller | 100m | 1000m → **500m** |
| **Total** | **350m** | **4000m → 2000m** |

**Aggressive dev option:** 250m limit per controller (**1000m** total).

**Implementation:** prefer a Kustomize patch in [gitops/clusters/dev/flux-system/](../gitops/clusters/dev/flux-system/) over editing `gotk-components.yaml` directly (Flux bootstrap may regenerate the latter).

---

## Cross-tier comparison (recommended CPU req / limit)

| Component | Free | Standard | Enterprise |
|-----------|------|----------|------------|
| api-router | 50m / 200m × **1** | 50m / 200m × 1 | 50m / 200m × 2 |
| trip-service | **150m / 400m** × 1 | 250m / 750m × 1–2 | 500m / **1000m** × 2–4 |
| social-service | **150m / 400m** × 1 | 150m / 500m × 1–2 | 200m / **500m** × 2–4 |
| external-info | **100m / 300m** × 1 | 100m / 500m × 1–2 | 150m / 500m × 1–2 |
| opensearch | **200m / 500m** | 100m / **400m** | 500m / **750m** |
| HPA | **off** | max **2** | max **4** (ext **2**) |

---

## Combined dev cluster budget

Approximate effective CPU **requests** (with Envoy) if Free + Standard (min) + platform (~0.8 core) run together:

| Profile | Approx. total |
|---------|---------------|
| **Before** (Free min + Standard trip=0 + platform) | ~**3.2 cores** |
| **After** (recommended steady state) | ~**2.5 cores** |
| Before — Free at HPA max alone | ~4.2 cores |
| After — Free steady (no HPA) | ~1.0 core |

Frees headroom on **16 vCPU** `CPUS_ALL_REGIONS` quota for rollouts, mesh system pods, and optional Enterprise tenant.

Also watch regional **`SSD_TOTAL_GB`** — Autopilot scale-up can fail on SSD quota even when CPU looks available ([iac_tenant_setup_overview.md](iac_tenant_setup_overview.md)).

---

## Files to change (implementation checklist)

| Change | File(s) |
|--------|---------|
| Free replicas, HPA, CPU | [gitops/tenants/free/shared/values-configmap.yaml](../gitops/tenants/free/shared/values-configmap.yaml) |
| Standard HPA max 2 | [gitops/tenants/standard/shared/values-configmap.yaml](../gitops/tenants/standard/shared/values-configmap.yaml) |
| Enterprise defaults in renderer | [scripts/render-tenants.py](../scripts/render-tenants.py), [tenants/enterprise/example-globex.yaml](../tenants/enterprise/example-globex.yaml) |
| Reduce chart drift | [charts/tripplanning/values-free.yaml](../charts/tripplanning/values-free.yaml), [values-standard.yaml](../charts/tripplanning/values-standard.yaml) |
| Flux CPU limits | Kustomize patch under [gitops/clusters/dev/flux-system/](../gitops/clusters/dev/flux-system/) |
| HPA checklist (conflicts with Free HPA off) | [gke-dev-hpa-and-test-bearer-checklist.md](gke-dev-hpa-and-test-bearer-checklist.md) |

---

## Open questions

### Locust load tests on Free

Steady-state Free with HPA off cannot scale under Locust. Options:

1. **Temporary perf profile** — enable HPA and raise limits only for the test window, then revert.
2. **Dedicated perf namespace** — separate Helm values with higher caps.
3. **Run Locust against Standard** — use Standard HPA max 2 instead of Free max 12 pods.

The [gke-dev-hpa-and-test-bearer-checklist.md](gke-dev-hpa-and-test-bearer-checklist.md) assumes Free HPA 1–8; update that doc if adopting this steady-state profile.

### When to use higher Enterprise limits

Trip **2000m** CPU limit and HPA max **8** are reasonable for production perf validation, not for shared 16-vCPU dev. Use tenant YAML overrides or a non-dev project for load testing.

---

## Related documentation

- Current values: [cpu-and-replicas-before.md](cpu-and-replicas-before.md)
- Mesh overhead: [service_mesh_monitoring.md](service_mesh_monitoring.md)
- Quota troubleshooting: [gke-dev-hpa-and-test-bearer-checklist.md](gke-dev-hpa-and-test-bearer-checklist.md)
