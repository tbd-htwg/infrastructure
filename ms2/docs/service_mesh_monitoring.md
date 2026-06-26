# Managed Prometheus and Cloud Service Mesh

MS2 currently uses Google Cloud Managed Service for Prometheus on the GKE
Autopilot cluster.

Google-managed Cloud Service Mesh was tested but is intentionally disabled for
now. The managed control plane repeatedly stalled with
`MESH_IAM_PERMISSION_DENIED` even after the documented service-agent IAM role,
required APIs, and Autopilot quota were fixed. Keep the mesh disabled until the
Google-managed Fleet/Cloud Service Mesh issue is resolved.

No in-cluster Prometheus server is installed.

## Provisioning

Terraform:

- enables the Monitoring API and related application APIs;
- explicitly enables Managed Prometheus collection on the Autopilot cluster.

Flux:

- labels workloads with `app.kubernetes.io/part-of=tripplanning`, tier, and,
  for Enterprise, tenant ID;
- installs a `ClusterPodMonitoring` resource. It is harmless while mesh is
  disabled, but it will not produce Envoy sidecar metrics until sidecars exist.

Apply a new project with:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev init
terraform -chdir=infrastructure/ms2/terraform/envs/dev apply
```

Provide the dispatch token when Terraform should manage its Secret Manager
version:

```bash
export TF_VAR_platform_github_dispatch_token='...'
```

Review the plan before applying.

## Verification

Cloud Service Mesh should be disabled:

```bash
gcloud container fleet mesh describe --project "$PROJECT_ID"
```

The expected result while mesh is disabled is:

```text
Service Mesh Feature for project [...] is not enabled
```

Check Managed Prometheus:

```bash
kubectl get clusterpodmonitoring tripplanning-mesh-proxies
kubectl describe clusterpodmonitoring tripplanning-mesh-proxies
kubectl get pods -n gke-gmp-system
```

In Google Cloud Console, open **Monitoring -> Metrics explorer**, switch to
PromQL, and use Kubernetes or application metrics first. The old Envoy scrape
job will not be useful until Cloud Service Mesh is re-enabled successfully:

```promql
up{job="tripplanning-mesh-proxies"}
```

For normal workload logs, use Cloud Logging with `resource.type="k8s_container"`
and namespace filters such as `resource.labels.namespace_name="tripplanning-standard"`.

## Tenant-aware operations

| Tier | Monitoring boundary |
| --- | --- |
| Free | `tripplanning-free` namespace |
| Standard | Shared `tripplanning-standard` namespace and shared workloads |
| Enterprise | Dedicated namespace plus `tripplanning.htwg.dev/tenant-id` label |
| Platform | `tripplanning-system` namespace |

Enterprise tenants can be filtered and alerted independently by namespace.
Standard tenants share the same pods, so Kubernetes infrastructure metrics
cannot reliably attribute CPU or memory to one Standard tenant. Use namespace
metrics for the shared Standard pool, and add application-level metrics later
if per-Standard-tenant request counts or latency are required.

Application-level business metrics should use the same bounded tenant IDs if
you later add Micrometer/OpenTelemetry instrumentation.

## Traffic management

Cloud Service Mesh is disabled, so traffic management still uses the existing
global HTTPS load balancer, tenant DNS, Kubernetes Services, and `api-router`.
Do not add Istio traffic resources until the managed control plane issue is
resolved and the mesh is intentionally re-enabled.

## Cost and rollback

Managed Prometheus ingestion has a cost; keep scrape interval and metric volume
under review. The `cost-control.sh` script can still scale application
workloads down and stop Cloud SQL. It does not remove GKE-managed system pods
or the Managed Prometheus collectors.
