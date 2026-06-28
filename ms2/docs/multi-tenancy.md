# Multi Tenancy

## Management Summary

TripPlanning supports three tenant tiers:

- Free: shared development/free runtime.
- Standard: shared paid runtime with tenant-aware routing and data separation.
- Enterprise: dedicated runtime and stronger infrastructure isolation.

The main difference is how much infrastructure a tenant gets exclusively. Free
and Standard share more infrastructure to keep cost low. Enterprise duplicates
more infrastructure per tenant to improve isolation, customization, and scaling.

## Tenant Tier Comparison

| Area | Free | Standard | Enterprise |
| --- | --- | --- | --- |
| Kubernetes namespace | `tripplanning-free` | `tripplanning-standard` | `tripplanning-ent-<tenant>` |
| Runtime services | Shared | Shared | Dedicated per tenant |
| API router | Shared | Shared with known-host enforcement | Dedicated per tenant |
| Identity Platform | Shared/default or tenant-aware config | Tenant-specific Identity Platform tenant | Tenant-specific Identity Platform tenant |
| PostgreSQL | Shared/default development setup | Shared Cloud SQL instance, tenant DB/user | Dedicated Cloud SQL instance |
| Firestore | Shared database | Shared database with tenant-specific collections/data | Shared Firestore database, tenant-scoped data |
| Images | Shared bucket prefix | Shared bucket prefix | Dedicated image bucket |
| Search | Shared/simple defaults | Tenant-specific index on shared OpenSearch | Tenant-specific OpenSearch release/index |
| Cache | Shared prefix | Tenant-specific prefix | Tenant-specific prefix and dedicated Valkey by default |
| Custom fields | Disabled | Disabled by default | Enabled |
| HPA | Disabled | Enabled | Enabled per tenant |

## Isolation and Security

Tenant isolation is layered:

- Host-based routing maps requests to tenant IDs.
- `api-router` injects `X-Tenant-ID` and
  `X-Identity-Platform-Tenant-ID` headers.
- Backend services read tenant context from headers and host information.
- Identity Platform tenants separate user authentication realms for paid tenants.
- Standard tenants use separate database names/users on a shared Cloud SQL
  instance.
- Enterprise tenants use dedicated Cloud SQL instances and Kubernetes
  namespaces.
- Enterprise namespaces include network policies that deny broad ingress and
  only allow expected traffic.
- Secret values are stored in Secret Manager and synced into Kubernetes with
  External Secrets.
- Kubernetes service accounts are annotated for GCP workload identity instead of
  storing cloud keys in pods.

Standard isolation is good for cost-efficient shared operation. Enterprise
isolation is stronger because runtime, namespace, database, and image storage
are dedicated.

## Tenant Creation

Tenant creation is driven by the platform service and infrastructure automation:

1. A platform admin creates a tenant through the application.
2. `platform-service` writes the tenant registry entry and creates or references
   the Identity Platform tenant.
3. `platform-service` sends a GitHub `repository_dispatch` event to the
   infrastructure repository.
4. The tenant infrastructure workflow writes a tenant YAML file.
5. `scripts/render-tenants.py` generates Terraform tenant variables and GitOps
   manifests.
6. Terraform creates cloud resources such as DNS, Identity Platform settings,
   Cloud SQL, buckets, and static addresses as needed.
7. Flux reconciles the generated Kubernetes resources.
8. The provisioning callback updates tenant status in the platform service.

Tenant YAML is intentionally compact. It contains business-relevant tenant
inputs such as slug, display name, tier, hostnames, branding, identity settings,
database naming, storage, search, and cache settings.

## Tenant Deletion

Tenant deletion is handled by the tenant deletion workflow referenced in
`tenants/README.md`.

At a high level:

1. The tenant is removed from tenant YAML.
2. Generated Terraform and GitOps output is updated.
3. Terraform destroys or detaches tenant-owned cloud resources.
4. Flux prunes generated Kubernetes resources.
5. Cleanup verifies that tenant resources no longer remain.

Standard tenant deletion needs extra care because the runtime is shared. Tenant
data such as database objects, search data, cache data, and storage prefixes
must be cleaned without disrupting other standard tenants.

## Current Tenant Inputs

Current tenant definitions are under:

- `tenants/standard`
- `tenants/enterprise`

Files named `example-*.yaml` are examples and are not applied by the renderer.

