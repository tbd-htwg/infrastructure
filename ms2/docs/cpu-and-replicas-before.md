# CPU requests, limits, and replicas — current state (before)

Snapshot of **deployed GitOps values** for the Free, Standard, and Enterprise tenant stacks on GKE Autopilot dev (`tripplanning-gke`). Verified against repository sources on 2026-06-19.

## How to read this document

- **GKE Autopilot schedules nodes from CPU requests**, not limits.
- **Limits** cap burst usage and count toward namespace `limits.cpu` quotas.
- **Istio sidecars** (Cloud Service Mesh, enabled on tenant namespaces) add ~100m CPU request per injected pod. That overhead is **not** in Helm values. Backing services (Postgres, OpenSearch, Valkey) opt out.
- **Cloud SQL proxy** adds 50m request / 250m limit per trip-service pod when `global.cloudSql.enabled` (Standard and Enterprise).

### Sources

| Tier | Primary source |
|------|----------------|
| Free | [gitops/tenants/free/shared/values-configmap.yaml](../gitops/tenants/free/shared/values-configmap.yaml) |
| Standard | [gitops/tenants/standard/shared/values-configmap.yaml](../gitops/tenants/standard/shared/values-configmap.yaml) + [generated-tenants-configmap.yaml](../gitops/tenants/standard/shared/generated-tenants-configmap.yaml) |
| Enterprise | [tenants/enterprise/example-globex.yaml](../tenants/enterprise/example-globex.yaml) + chart defaults [values.yaml](../charts/tripplanning/values.yaml) / [values-enterprise.yaml](../charts/tripplanning/values-enterprise.yaml) |
| Chart references (not deployed directly) | [values-free.yaml](../charts/tripplanning/values-free.yaml), [values-standard.yaml](../charts/tripplanning/values-standard.yaml) |

---

## Known inconsistencies

| Topic | GitOps (deployed) | Chart tier file | Other docs |
|-------|-------------------|-----------------|------------|
| Free api-router replicas | **2** | 1 (base chart) | — |
| Free autoscaling | **enabled** (social/external max **4**) | **disabled** in `values-free.yaml` | [gke-dev-hpa-and-test-bearer-checklist.md](gke-dev-hpa-and-test-bearer-checklist.md) expects HPA 1–8 |
| Free Spring Boot CPU | 250m req / 750–1000m limit | 150m / 400m in `values-free.yaml` | — |
| Standard replicas | **1** each, HPA **off** | **2** each, HPA min 2 max **8** in `values-standard.yaml` | — |
| Standard trip (cluster) | **replicas: 0** in generated tenants | replicas: 1 in values ConfigMap | Scale-to-zero when no tenants |
| Enterprise trip CPU limit | **2000m** (globex) | 1000m (base chart default) | — |

---

## Free — `tripplanning-free`

Namespace: `tripplanning-free`. Istio injection: **enabled**. Namespace ResourceQuota: **none**. HPA: **enabled**.

### Workloads

| Component | Type | Static replicas | HPA min | HPA max | CPU request | CPU limit | Mem request | Mem limit | Istio sidecar |
|-----------|------|-----------------|---------|---------|-------------|-----------|-------------|-----------|---------------|
| api-router | app | 2 | — | — | 50m¹ | 200m¹ | 64Mi¹ | 128Mi¹ | yes |
| trip-service | app | 1 | 1 | 2 | 250m | 1000m | 512Mi | 1024Mi | yes |
| social-service | app | 1 | 1 | 4 | 250m | 750m | 384Mi | 768Mi | yes |
| external-info | app | 1 | 1 | 4 | 250m | 750m | 384Mi | 768Mi | yes |
| postgres | backing | 1 | — | — | 100m | 500m | 256Mi | 512Mi | no |
| valkey | backing | 1 | — | — | 50m | 250m | 256Mi | 512Mi | no |
| opensearch | backing | 1 | — | — | 250m | 1000m | 768Mi | 1280Mi | no |

¹ From base chart [values.yaml](../charts/tripplanning/values.yaml); not overridden in Free GitOps ConfigMap.

### HPA settings

| Setting | Value |
|---------|-------|
| Global target CPU | 80% |
| Global target memory | 75% |
| trip target CPU | 70% |
| trip target memory | 0 (disabled) |
| social / externalInfo | inherit global CPU 80% and memory 75% |

### CPU totals (declared requests only)

| Scenario | App + backing requests | Injected pods | Envoy (~100m each) | **Approx. effective requests** |
|----------|------------------------|---------------|--------------------|--------------------------------|
| Steady (min replicas) | 1250m (1.25 cores) | 5 | 500m | **~1.75 cores** |
| HPA maximum | 3000m (3.0 cores) | 12 | 1200m | **~4.2 cores** |

Calculation (min): 2×50 + 250 + 250 + 250 + 100 + 50 + 250 = 1250m.

Calculation (HPA max): 2×50 + 2×250 + 4×250 + 4×250 + 400 backing = 3000m.

---

## Standard — `tripplanning-standard`

Namespace: `tripplanning-standard`. Istio injection: **enabled**. HPA: **disabled** (maxReplicas 2 configured but inactive).

**Namespace ResourceQuota:** requests.cpu **12** / limits.cpu **32**.

**Current cluster override:** [generated-tenants-configmap.yaml](../gitops/tenants/standard/shared/generated-tenants-configmap.yaml) sets `trip.replicas: 0`.

### Workloads (from values ConfigMap)

| Component | Type | Static replicas | HPA | CPU request | CPU limit | Mem request | Mem limit | Istio sidecar | Notes |
|-----------|------|-----------------|-----|-------------|-----------|-------------|-----------|---------------|-------|
| api-router | app | 1 | off | 50m¹ | 200m¹ | 64Mi¹ | 128Mi¹ | yes | |
| trip-service | app | 1 (0 now) | off | 250m | 750m | 384Mi | 768Mi | yes | + Cloud SQL proxy 50m / 250m when running |
| social-service | app | 1 | off | 150m | 500m | 256Mi | 512Mi | yes | |
| external-info | app | 1 | off | 100m | 500m | 192Mi | 384Mi | yes | |
| valkey | backing | 1 | — | 25m | 100m | 64Mi | 128Mi | no | |
| opensearch | backing | 1 | — | 100m | 500m | 384Mi | 768Mi | no | |

¹ Chart default.

### CPU totals (declared requests)

| Scenario | Declared requests | Injected pods | Envoy (~100m) | **Approx. effective** |
|----------|-------------------|---------------|---------------|------------------------|
| Configured (trip = 1, + proxy) | 725m | 4 | 400m | **~1.1 cores** |
| **Current GitOps (trip = 0)** | 425m | 3 | 300m | **~0.7 cores** |

---

## Enterprise — per tenant (example: globex)

Namespace: `tripplanning-ent-globex`. Istio injection: **enabled** (when deployed). Example: [example-globex.yaml](../tenants/enterprise/example-globex.yaml).

**Namespace ResourceQuota** (from [render-tenants.py](../scripts/render-tenants.py)): requests.cpu **16** / limits.cpu **48**.

Services not listed in tenant YAML inherit chart defaults from [values.yaml](../charts/tripplanning/values.yaml) and [values-enterprise.yaml](../charts/tripplanning/values-enterprise.yaml).

### Workloads

| Component | Type | Static replicas | HPA min | HPA max | CPU request | CPU limit | Mem request | Mem limit | Istio | Source |
|-----------|------|-----------------|---------|---------|-------------|-----------|-------------|-----------|-------|--------|
| api-router | app | 2 | — | — | 50m | 200m | 64Mi | 128Mi | yes | chart |
| trip-service | app | 2 | 2 | 8 | 500m | 2000m | 768Mi | 2Gi | yes | globex YAML |
| cloud-sql-proxy | sidecar | per trip pod | — | — | 50m | 250m | 64Mi | 256Mi | no | chart |
| social-service | app | 2 | 2² | 8² | 200m | 750m | 384Mi | 768Mi | yes | chart |
| external-info | app | 1 | 2² | 8² | 150m | 500m | 256Mi | 512Mi | yes | chart + globex replicas |
| opensearch | backing | 1 | — | — | 500m | 1000m | 1Gi | 2Gi | no | chart |
| valkey | backing | 1 | — | — | 50m | 150m | 128Mi | 256Mi | no | chart |

² Global Enterprise autoscaling: minReplicas **2**, maxReplicas **8**, target CPU **70%** (`values-enterprise.yaml`). Per-service HPA uses these unless overridden.

### CPU totals (declared requests)

| Scenario | Declared requests | Injected pods | Envoy (~100m) | **Approx. effective** |
|----------|-------------------|---------------|---------------|------------------------|
| Steady (min replicas) | 2300m (2.3 cores) | 7 | 700m | **~3.0 cores** |
| HPA max (8+8+8 app + 2 api) | 7850m (7.85 cores) | 26 | 2600m | **~10.5 cores** |

---

## Flux controllers — `flux-system`

From [gotk-components.yaml](../gitops/clusters/dev/flux-system/gotk-components.yaml). Not a tenant tier; included because aggregate limits are high.

| Controller | CPU request | CPU limit |
|------------|-------------|-----------|
| source-controller | 50m | 1000m |
| kustomize-controller | 100m | 1000m |
| helm-controller | 100m | 1000m |
| notification-controller | 100m | 1000m |
| **Total** | **350m** | **4000m** |

Limits do not drive Autopilot scheduling; requests total **350m**.

---

## Related documentation

- Recommended tuning: [cpu-and-replicas-after.md](cpu-and-replicas-after.md)
- Mesh sidecar cost: [service_mesh_monitoring.md](service_mesh_monitoring.md)
- HPA / Locust checklist: [gke-dev-hpa-and-test-bearer-checklist.md](gke-dev-hpa-and-test-bearer-checklist.md)
