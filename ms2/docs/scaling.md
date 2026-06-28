# Scaling

## Management Summary

Scaling is controlled per tenant tier. Free is intentionally small. Standard is
a shared paid runtime with multiple replicas and HPA. Enterprise tenants get
their own namespace and can be scaled independently.

Most application scaling changes are easy: edit Helm values or tenant YAML,
render the tenant manifests, and let Flux apply the change. Database scaling is
different: Cloud SQL machine type, storage, and availability are Terraform
settings and should be changed deliberately.

## Tier Scaling Overview

| Tier | Runtime model | Default scaling | Change effort |
| --- | --- | --- | --- |
| Free | Shared free namespace | 1 replica per service, HPA disabled | Low, Helm values |
| Standard | Shared paid namespace | 2 replicas, HPA enabled up to 8 by default | Low for services, medium for shared database |
| Enterprise | Dedicated namespace per tenant | 1 replica, HPA enabled, per-service max values | Low per tenant for services, medium for tenant database |

## Kubernetes Scaling

Scaling is mainly configured in Helm values:

- `services.<service>.replicas`
- `services.<service>.resources.requests`
- `services.<service>.resources.limits`
- `autoscaling.enabled`
- `autoscaling.minReplicas`
- `autoscaling.maxReplicas`
- per-service autoscaling overrides

The chart contains HPA resources for:

- `trip-service`
- `social-service`
- `external-info-service`
- `customfield-service` when enabled

HPA uses CPU utilization by default. Memory scaling is supported for
`trip-service` when a memory target is configured.

## Free Tier

Free is optimized for low cost:

- 1 replica for backend services.
- HPA disabled.
- Reduced CPU and memory requests.
- No external `api-router` LoadBalancer from the tier values.

This tier is simple and inexpensive, but it is not designed for strong
availability guarantees.

## Standard Tier

Standard is a shared production-like runtime:

- `api-router` has 2 replicas.
- `trip-service`, `social-service`, and `external-info-service` have 2 replicas.
- HPA is enabled.
- Default HPA range is 2 to 8 replicas.
- OpenSearch and Valkey run as shared backing services.
- Cloud SQL is shared at the instance level, with tenant-specific databases and
  users.

Changing standard service scale is straightforward in
`values-standard.yaml`. Because standard tenants share the runtime, scaling up
helps all standard tenants but also means noisy tenants can affect shared
capacity.

## Enterprise Tier

Enterprise tenants have dedicated namespaces and generated Helm releases:

- Independent `api-router`, services, OpenSearch, Valkey, and Cloud SQL
  connection settings.
- HPA enabled by default.
- `trip-service` can scale from 1 to 4 replicas by default.
- `social-service`, `external-info-service`, and `customfield-service` can scale
  from 1 to 3 replicas by default.
- Namespace ResourceQuota limits total tenant resource consumption.

Enterprise scale changes can be made per tenant through tenant YAML overrides or
the generated values. This is the easiest tier to scale independently because a
change does not affect other enterprise tenants.

## Database and Storage Scaling

Cloud SQL is managed by Terraform:

- Standard has a shared Cloud SQL instance.
- Platform service has its own small Cloud SQL instance.
- Enterprise tenants have tenant-specific Cloud SQL instances.

Cloud SQL storage can auto-grow when configured, but CPU and memory class require
a Terraform change. Database changes should be treated as operational changes,
not simple app rollouts.

Cloud Storage scales automatically. Tenant isolation is by prefix for shared
tiers and by dedicated bucket for enterprise image storage.

Firestore scales as a managed service, but indexes and data model choices still
matter. Terraform manages required Firestore indexes for comments and likes.

