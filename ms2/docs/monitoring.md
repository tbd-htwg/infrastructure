# Monitoring

## Management Summary

Monitoring is built on normal GKE observability plus Google Cloud Managed
Service for Prometheus. Logs, Kubernetes events, workload health, resource
usage, and Prometheus metrics can be viewed in Google Cloud without running a
separate Prometheus server.

The most important operational signals are:

- Pod health and rollout status.
- CPU and memory usage.
- HTTP health endpoints.
- Application metrics from `/actuator/prometheus`.
- Mesh request metrics and access logs.
- Kubernetes service and load balancer health.
- Cloud SQL, Firestore, and Cloud Storage health in Google Cloud.

Alerting rules are not the main focus of the current manifests. The current
state provides metric collection and logging foundations that can be used to
create alert policies in Cloud Monitoring.

## Managed Prometheus

Managed Prometheus is configured through
`gitops/platform/workloads/observability/managed-prometheus.yaml`.

It defines `ClusterPodMonitoring` resources for:

- `trip-service` on port `8080`, path `/actuator/prometheus`.
- `social-service` on port `8081`, path `/actuator/prometheus`.
- `external-info-service` on port `8082`, path `/actuator/prometheus`.
- mesh sidecars on port `http-envoy-prom`, path `/stats/prometheus`.

The collection interval is `30s`.

The backend services include Spring Boot Actuator and Micrometer Prometheus
dependencies where metrics are exposed. Kubernetes probes use separate
liveness/readiness endpoints so restart behavior and metric scraping are not
mixed.

## GKE and Kubernetes Observability

Useful views in Google Cloud:

- GKE Workloads: pod health, restarts, resource usage, rollout status.
- GKE Services and Ingress: service endpoints and load balancer status.
- Logs Explorer: container logs and platform logs.
- Cloud Monitoring Metrics Explorer: CPU, memory, request, and custom metrics.
- Cloud SQL monitoring: database CPU, storage, connections, slow behavior.

Useful kubectl checks:

```bash
kubectl get pods -A
kubectl get deploy -A
kubectl get hpa -A
kubectl get svc -A
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> deploy/<deployment>
```

## Logs

Terraform configures a project log sink for Kubernetes container and pod logs.
Application logs are written to standard output and standard error, which is the
expected pattern for containerized workloads.

In Logs Explorer, useful filters are:

```text
resource.type="k8s_container"
resource.labels.namespace_name="tripplanning-standard"
```

```text
resource.type="k8s_container"
labels."k8s-pod/app_kubernetes_io_component"="trip-service"
```

## Service Mesh Telemetry

`mesh-telemetry.yaml` enables mesh metrics, tracing, and access logging. The
mesh metric configuration adds a `tenant_id` tag from the `x-tenant-id` request
header where available.

This helps answer questions such as:

- Which tenant is generating traffic?
- Which service path is failing?
- Is the failure at the router, service, or backing dependency?

## Health and Rollouts

Services define readiness and liveness probes:

- Readiness controls whether the pod receives traffic.
- Liveness controls whether Kubernetes restarts a stuck process.
- The deployment pipeline waits for rollout status after image updates.

This is especially important for standard and enterprise tenants where multiple
replicas and HPA are enabled.

## Recommended Alert Policies

The current monitoring foundation supports alerts such as:

- Deployment has unavailable replicas for more than a few minutes.
- Pod restart count increases repeatedly.
- HPA is at max replicas for a sustained period.
- API router health check fails.
- Cloud SQL CPU, connections, or storage approach limits.
- HTTP 5xx rate increases for a tenant or namespace.

