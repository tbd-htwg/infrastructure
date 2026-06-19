# Cloud Service Mesh and Managed Prometheus

MS2 uses Google-managed Cloud Service Mesh on the GKE Autopilot cluster and
Google Cloud Managed Service for Prometheus. No in-cluster Istio control plane
or Prometheus server is installed.

## Provisioning

Terraform:

- enables the GKE Hub, Mesh, Mesh CA, Mesh Configuration, Traffic Director,
  Monitoring, and related APIs;
- registers `tripplanning-gke` as a fleet membership;
- enables the fleet `servicemesh` feature with automatic management;
- explicitly enables Managed Prometheus collection on the Autopilot cluster.

Flux:

- labels application namespaces with `istio-injection=enabled`;
- labels workloads with `app.kubernetes.io/part-of=tripplanning`, tier, and,
  for Enterprise, tenant ID;
- installs a `ClusterPodMonitoring` resource that scrapes Envoy sidecar
  Prometheus metrics from `/stats/prometheus` on `http-envoy-prom`.
- configures the single supported cluster-wide Istio `Telemetry` resource for
  tenant-aware Prometheus labels, 1% Cloud Trace sampling, and Envoy request
  access logs.

Postgres, OpenSearch, Valkey, and the seed Job explicitly opt out of injection.
They are backing processes rather than HTTP microservices, and excluding them
avoids unnecessary Autopilot sidecar cost and Job shutdown issues.

Injected application pods exclude `169.254.169.254/32` from Envoy interception.
This preserves direct access to the GKE metadata server for Workload Identity,
Cloud SQL connectors, Firestore, and other Google client libraries.

Ports `5432`, `6379`, and `9200` are also excluded. They belong to the
non-meshed Postgres/Cloud SQL proxy, Valkey, and OpenSearch processes. The
exclusion also lets startup init containers reach those dependencies before
the Envoy sidecar has started.

Apply a new project with:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev init
terraform -chdir=infrastructure/ms2/terraform/envs/dev apply
```

Always provide both sensitive variables used by this environment. Omitting a
previously managed value can produce a destructive plan:

```bash
export TF_VAR_flux_bootstrap_git_password='...'
export TF_VAR_platform_github_dispatch_token='...'
```

Review the plan before applying. On an existing cluster, workloads must be
restarted once after the managed control plane becomes ready so new pods
receive Envoy sidecars:

```bash
kubectl rollout restart deployment -n tripplanning-system
kubectl rollout restart deployment -n tripplanning-free
kubectl rollout restart deployment -n tripplanning-standard
```

Repeat the restart for an Enterprise namespace if it already existed when the
mesh was enabled. New tenant namespaces are labeled by the tenant renderer and
are injected automatically.

## Verification

Check fleet and mesh state:

```bash
gcloud container fleet memberships list --project "$PROJECT_ID"
gcloud container fleet mesh describe --project "$PROJECT_ID"
```

The membership should be `READY` and the mesh membership should eventually
report a healthy managed control plane.

Check namespace labels and sidecars:

```bash
kubectl get namespace -L istio-injection
kubectl get pods -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CONTAINERS:.spec.containers[*].name'
```

Application pods in meshed namespaces should contain `istio-proxy`.

Check Managed Prometheus:

```bash
kubectl get clusterpodmonitoring tripplanning-mesh-proxies
kubectl describe clusterpodmonitoring tripplanning-mesh-proxies
kubectl get pods -n gke-gmp-system
```

In Google Cloud Console, open **Monitoring -> Metrics explorer**, switch to
PromQL, and start with:

```promql
up{job="tripplanning-mesh-proxies"}
```

Useful Envoy metrics include:

```promql
sum by (namespace) (
  rate(envoy_cluster_upstream_rq_total{namespace=~"tripplanning-.*"}[5m])
)
```

```promql
sum by (namespace) (
  rate(envoy_cluster_upstream_rq_xx{namespace=~"tripplanning-.*"}[5m])
)
```

Metric availability and exact labels can differ by managed Envoy version. Use
Metrics Explorer autocomplete to inspect the ingested `envoy_*` series first.

Cloud Service Mesh also writes service request metrics to Cloud Monitoring.
Open **Kubernetes Engine -> Service Mesh** for topology, service health, and
request telemetry, or query the `istio.io/service/*` metric types in Metrics
Explorer.

Cloud Trace is enabled at a 1% sampling rate. Open **Trace -> Trace explorer**
or select a service in **Kubernetes Engine -> Service Mesh** and follow its
request-trace link. Applications must propagate one of the supported trace
headers (`traceparent`, B3, or `x-cloud-trace-context`) on downstream HTTP
requests for multiple proxy spans to be joined into one end-to-end trace.

Envoy request access logs are enabled by the same cluster-wide Telemetry
resource and collected by Cloud Logging. Example Logs Explorer filter:

```text
resource.type="k8s_container"
resource.labels.container_name="istio-proxy"
resource.labels.namespace_name=~"tripplanning-.*"
```

## Tenant-aware operations

| Tier | Monitoring boundary |
| --- | --- |
| Free | `tripplanning-free` namespace |
| Standard | Shared `tripplanning-standard` namespace and shared workloads |
| Enterprise | Dedicated namespace plus `tripplanning.htwg.dev/tenant-id` label |
| Platform | `tripplanning-system` namespace |

Enterprise tenants can be filtered and alerted independently by namespace.
Standard tenants share the same pods, so Kubernetes and Envoy infrastructure
metrics cannot reliably attribute CPU or memory to one tenant. Request
metrics do include a `tenant_id` dimension taken from the trusted
`X-Tenant-ID` header injected by `api-router`, so Standard request rate,
errors, and latency can be queried independently. Never accept or preserve
this metric label directly from an untrusted client header.

Example Standard tenant query:

```promql
sum(
  rate(istio_requests_total{
    destination_workload_namespace="tripplanning-standard",
    tenant_id="acme"
  }[5m])
)
```

Application-level business metrics should use the same bounded tenant IDs if
you later add Micrometer/OpenTelemetry instrumentation.

## Traffic management

The mesh does not replace the existing global HTTPS load balancer or
`api-router`. It adds mTLS-capable sidecars, service telemetry, and Istio APIs
for east-west traffic. Start with observability only. Add `AuthorizationPolicy`,
`PeerAuthentication`, `DestinationRule`, or traffic-splitting resources
gradually and test them per namespace; a restrictive mesh policy can block
Cloud SQL, Google APIs, OpenSearch, Valkey, or other required egress.

## Cost and rollback

Envoy adds CPU and memory to each injected pod, which increases Autopilot
cost. Managed Prometheus ingestion also has a cost; keep the scrape interval
and metric volume under review. Cloud Trace sampling and Envoy request logs
also create observability ingestion costs.

Cloud Service Mesh also adds managed system pods to every node. Keep enough
pod, memory, CPU, and regional `SSD_TOTAL_GB` quota for Autopilot to create
another node during rollout. A generic `GCE quota exceeded` autoscaler event
can refer to SSD quota even when CPU quota is available.

To stop injection for a namespace:

```bash
kubectl label namespace NAMESPACE istio-injection-
kubectl rollout restart deployment -n NAMESPACE
```

Make the equivalent GitOps change first, otherwise Flux restores the label.
Disabling the fleet feature or deleting membership is a separate Terraform
change and should only happen after all injected workloads have been removed.
