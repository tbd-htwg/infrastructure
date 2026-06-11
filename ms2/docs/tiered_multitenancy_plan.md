# Tiered Multitenancy Implementation Plan

This document describes the target multitenancy model for the TripPlanning application. It is meant as an implementation handoff for developers or AI agents that will later define Terraform, Helm, GitOps templates, and tenant provisioning automation.

The plan is based on the multitenancy criteria from `01_Multitenancy.pdf`: isolation, availability, scalability, cost, customizability, regulatory needs, authentication/authorization, SLA, provisioning, maintainability, monitoring, and automation.

Billing is intentionally not the focus of this version. The goal is to define a clean infrastructure and deployment model first.

## Core Decisions

| Topic | Decision |
| --- | --- |
| Free tenants | Shared namespace, shared runtime, shared backing services, reduced resources, best effort. |
| Standard tenants | All Standard tenants share one Kubernetes namespace and one Standard runtime. Each Standard tenant gets its own database inside one shared Standard Cloud SQL instance. |
| Enterprise tenants | Each Enterprise tenant gets its own Kubernetes namespace, its own LoadBalancer, its own API router, its own Cloud SQL instance, and configurable service images/resources/scaling. |
| Routing | Do not use GKE Gateway API as the target model. Use Kubernetes LoadBalancer Services and in-namespace API routers. |
| Domains | Free uses the shared app domain, Standard uses `<tenant>.k8s.tbd-htwg.de`, and Enterprise uses `<tenant>.enterprise.k8s.tbd-htwg.de`. |
| Frontend | Standard and Enterprise tenants get a frontend subfolder in the shared frontend bucket and can customize brand name, color scheme, and brand icon. |
| Tenant identity | Use the tenant subdomain to select the tenant at routing/frontend time. Use Google Identity Platform tenant ID as the authoritative authenticated tenant identity. Backend services must verify both match. |
| User management | Standard and Enterprise tenants get Google Identity Platform tenant configurations. Free can use a shared Identity Platform tenant or project-level auth. |
| Automation | Tenant creation/deletion is driven by one tenant YAML file. A provisioning script converts tenant YAML into Terraform `.tfvars` and GitOps/Helm manifests. |
| Application style | Follow 12-factor app principles where possible: config through environment, stateless services, logs to stdout, disposability, parity, and independent service processes. |

## Target Architecture by Tier

### Free Tier

Free tenants are not isolated from each other at infrastructure level. This tier exists to keep cost low and operational complexity small.

- Namespace: one shared namespace, currently `tripplanning-free`.
- Runtime: one shared HelmRelease for all Free users.
- LoadBalancer/routing: shared endpoint or existing shared route.
- Postgres: shared in-cluster Postgres can remain for Free if cost is the priority.
- Firestore: shared database/collections.
- OpenSearch: shared in-cluster OpenSearch.
- Valkey: shared in-cluster Valkey.
- Images: shared Cloud Storage bucket prefix, for example `free/`.
- Frontend: shared frontend, no tenant branding.
- Identity Platform: shared Free auth context. This can be one shared Identity Platform tenant or project-level auth, depending on what is easiest for the existing frontend/backend.
- Scaling: fixed small replica counts or very low HPA max.
- SLA: best effort only.
- Customization: none.
- Deletion: deleting a Free account only deletes or disables application/user data; no tenant infrastructure is deleted.

### Standard Tier

Standard is the main pooled multitenancy model. It should provide tenant-specific domains, tenant-specific data isolation, frontend customization, and controlled scalability without duplicating the whole application for every tenant.

- Namespace: one shared namespace, for example `tripplanning-standard`.
- Runtime: one shared Standard HelmRelease for all Standard tenants.
- LoadBalancer/routing: one Standard LoadBalancer.
- API routing: one in-namespace Standard API router receives all Standard tenant domains and routes to the shared Standard services.
- Domains: each Standard tenant gets a DNS record such as `acme.k8s.tbd-htwg.de` pointing to the Standard LoadBalancer IP.
- Postgres: one shared Standard Cloud SQL instance. Each Standard tenant gets its own database inside this instance, for example `tripplanning_std_acme`.
- Firestore: shared Firestore database, but all documents/paths must be tenant-scoped.
- OpenSearch: shared OpenSearch, but use one index per tenant or tenant-filtered aliases.
- Valkey: shared Valkey with tenant-prefixed keys.
- Images: shared images bucket with a tenant prefix, for example `standard/acme/`.
- Frontend: shared frontend bucket with one subfolder per tenant, for example `standard/acme/`.
- Frontend customization: tenant config contains brand name, color scheme, and brand icon path.
- Identity Platform: one Identity Platform tenant per Standard tenant. The frontend maps the hostname to the Identity Platform tenant ID before sign-in.
- Scaling: shared HPA for the Standard service pool. Use application-level quotas/rate limits so one tenant cannot consume the whole pool.
- SLA: moderate SLA, dependent on the shared Standard runtime.
- Customization: limited to approved settings, branding, quotas, and feature flags. No custom service images in Standard.
- Deletion: remove DNS entry, frontend subfolder, tenant database, tenant search index, storage prefixes, secrets, and tenant registry entry.

### Enterprise Tier

Enterprise is isolated and customizable. It is the tier for high isolation, tenant-specific service versions, stronger SLA, and custom resources.

- Namespace: one namespace per tenant, for example `tripplanning-ent-acme`.
- Runtime: one HelmRelease per Enterprise tenant.
- LoadBalancer/routing: one LoadBalancer per Enterprise tenant.
- API routing: one in-namespace API router per Enterprise namespace.
- Domains: each Enterprise tenant gets a DNS record such as `acme.enterprise.k8s.tbd-htwg.de` pointing to that tenant's LoadBalancer IP.
- Postgres: one Cloud SQL instance per Enterprise tenant. Do not use in-cluster Postgres for Enterprise.
- Firestore: tenant-scoped collections/paths; use separate database/project only if a future compliance requirement needs it.
- OpenSearch: dedicated OpenSearch deployment or managed OpenSearch resource from the beginning.
- Valkey: dedicated Valkey deployment in the tenant namespace, unless a managed/dedicated external cache is introduced later.
- Images: dedicated Cloud Storage image bucket per tenant.
- Frontend: shared frontend bucket with one subfolder per Enterprise tenant, for example `enterprise/acme/`.
- Frontend customization: tenant config contains brand name, color scheme, and brand icon path.
- Identity Platform: one Identity Platform tenant per Enterprise tenant. Tenant-specific IdP settings, email/password settings, MFA, and SAML/OIDC providers can be configured here.
- Scaling: configured per tenant during tenant creation. The tenant definition must allow replicas, HPA min/max, CPU/memory requests, and CPU/memory limits per microservice.
- Service images: configured per tenant during tenant creation. The tenant definition must allow image repository/tag/pull policy for `trip-service`, `social-service`, `external-info-service`, and `api-router`.
- SLA: strongest SLA in this model because runtime, database, and routing are isolated.
- Customization: tenant-specific code, service images, resources, integrations, branding, feature flags, and domains.
- Deletion: remove DNS, LoadBalancer, namespace, HelmRelease, tenant Cloud SQL instance, tenant secrets, frontend subfolder, dedicated image bucket, OpenSearch resources, and cache resources. Tenant destruction does not retain data.

## Resource Plan

### DNS and LoadBalancers

| Tier | Target |
| --- | --- |
| Free | Shared DNS and shared entrypoint. No per-tenant DNS records. |
| Standard | One Standard LoadBalancer Service. Every Standard tenant subdomain points to the same LoadBalancer IP. The in-namespace Standard API router uses the `Host` header to identify the tenant and route API traffic. |
| Enterprise | One LoadBalancer Service per Enterprise tenant. Each Enterprise DNS record points to that tenant's LoadBalancer IP. The API router lives in the tenant namespace. |

Implementation notes:

- Terraform should manage DNS records.
- Kubernetes should create LoadBalancer Services through Helm/GitOps.
- Store tenant hostname in the tenant definition.
- The API router must preserve `Host`, `X-Forwarded-Host`, and request identity headers for backend tenant validation.
- Avoid GKE Gateway API in the target implementation unless it is kept temporarily during migration.

### API Router

| Tier | Target |
| --- | --- |
| Free | One shared router with minimal resources. |
| Standard | One shared Standard router. It must map hostnames to tenant IDs, reject unknown hosts, route API paths to the shared services, and inject a trusted internal tenant header. |
| Enterprise | One router per tenant namespace. It can be configured with that tenant's hostnames, custom CORS origins, custom routes, and tenant-specific images. |

Important requirements:

- The tenant identity must not be taken from an arbitrary client-provided header.
- If the router injects `X-Tenant-ID`, backend services must only trust it from internal traffic.
- The backend must verify the Identity Platform ID token and ensure the token tenant ID matches the resolved hostname/router tenant.
- Router config should be generated from Helm values or a ConfigMap created from the tenant definition.

### Kubernetes Namespaces

| Tier | Target |
| --- | --- |
| Free | `tripplanning-free` namespace. |
| Standard | `tripplanning-standard` namespace for all Standard tenants. |
| Enterprise | One namespace per tenant, for example `tripplanning-ent-acme`. |

Implementation notes:

- Add `ResourceQuota` and `LimitRange` for every namespace.
- Add NetworkPolicies to limit traffic between services and backing resources.
- Enterprise namespaces should have tenant labels: `tier=enterprise`, `tenant_id=<id>`.
- Standard resources should have `tier=standard`; where possible add tenant labels to config, logs, metrics, and generated data resources.

### Microservices

The current services are:

- `api-router`
- `trip-service`
- `social-service`
- `external-info-service`

| Tier | Target |
| --- | --- |
| Free | Shared service deployments with reduced resources. |
| Standard | Shared service deployments in `tripplanning-standard`. Service code must be tenant-aware and use tenant-specific data resources. |
| Enterprise | Dedicated service deployments per tenant namespace. Images, replicas, HPA, and resources are configured per tenant. |

Enterprise Helm values must support per-service overrides like:

```yaml
services:
  trip:
    image:
      repository: ghcr.io/tbd-htwg/backend/custom-acme-trip-service
      tag: 2026-06-tenant-acme
      pullPolicy: IfNotPresent
    resources:
      requests:
        cpu: "500m"
        memory: "768Mi"
      limits:
        cpu: "2000m"
        memory: "2Gi"
  social:
    image:
      repository: ghcr.io/tbd-htwg/backend/tripplanning-social-service
      tag: stable
```

### Cloud SQL and Postgres

| Tier | Target |
| --- | --- |
| Free | Shared in-cluster Postgres is acceptable for low cost. Later, it can move to a shared Free Cloud SQL database if reliability becomes more important. |
| Standard | One shared Standard Cloud SQL instance. Each Standard tenant gets its own database in that instance. |
| Enterprise | One Cloud SQL instance per Enterprise tenant. No in-cluster Postgres for Enterprise. |

Implementation notes:

- Terraform should create the shared Standard Cloud SQL instance.
- Terraform or a tenant provisioning job should create one database per Standard tenant.
- Terraform should create one Cloud SQL instance per Enterprise tenant from the tenant definition.
- Store generated DB passwords in Secret Manager.
- Use External Secrets to sync only the required credentials into Kubernetes.
- Prefer private IP connectivity where possible.
- Backups should be enabled for Standard and Enterprise Cloud SQL. Enterprise can use stronger backup/PITR settings.

### Firestore

| Tier | Target |
| --- | --- |
| Free | Shared Firestore database/collections. |
| Standard | Shared Firestore database with tenant-scoped paths or mandatory `tenantId` fields. |
| Enterprise | Tenant-scoped paths/collections. Separate Firestore database/project is optional future work for compliance. |

Requirements:

- Every Firestore document that belongs to a tenant must be reachable only through tenant-scoped backend logic.
- Queries must include tenant scope.
- Index definitions must include tenant-scoped access patterns.

### OpenSearch

| Tier | Target |
| --- | --- |
| Free | Shared in-cluster OpenSearch. |
| Standard | Shared search service with one index per tenant, for example `tripentity-acme`. |
| Enterprise | Dedicated OpenSearch deployment or managed OpenSearch resource per tenant immediately. |

Requirements:

- Index names must be generated from tenant config.
- Services must never accept raw index names from client input.
- Deleting a tenant must delete its index or dedicated OpenSearch resource.

### Valkey Cache

| Tier | Target |
| --- | --- |
| Free | Shared Valkey. |
| Standard | Shared Valkey with tenant-prefixed keys. |
| Enterprise | Dedicated Valkey in the tenant namespace by default. |

Requirements:

- Standard keys must include a tenant prefix, for example `std:acme:<key>`.
- Cache data must be disposable and rebuildable.
- Enterprise cache settings can be configured per tenant.

### Cloud Storage: Images and Frontend

| Area | Standard | Enterprise |
| --- | --- | --- |
| Images | Shared images bucket prefix: `standard/<tenant-id>/`. | Dedicated image bucket per tenant, for example `tripplanning-ent-acme-images`. |
| Frontend | Shared frontend bucket subfolder: `standard/<tenant-id>/`. | Shared frontend bucket subfolder: `enterprise/<tenant-id>/`. |
| Branding | Config file in tenant frontend folder defines brand name, color scheme, icon path. | Same, plus custom frontend build can be uploaded per tenant if needed. |

Implementation notes:

- Terraform should create the shared frontend bucket, the shared Standard images bucket, and dedicated Enterprise image buckets.
- Tenant provisioning should create or upload the initial tenant frontend folder contents.
- Tenant deletion should delete the tenant frontend subfolder and image prefix/bucket.
- Backend signed URLs must only allow access to objects under the resolved tenant prefix.

Example tenant frontend config:

```json
{
  "tenantId": "acme",
  "brandName": "Acme Travel",
  "colorScheme": "blue",
  "brandIcon": "/enterprise/acme/assets/brand-icon.png"
}
```

### Secrets

| Tier | Target |
| --- | --- |
| Free | Shared secrets. |
| Standard | Tenant-specific DB credentials and optional tenant-specific integration secrets; shared platform secrets for common dependencies. |
| Enterprise | Tenant-specific secrets for DB, integrations, API keys, and custom service images where needed. |

Naming convention:

- `tripplanning-standard-<tenant-id>-db-password`
- `tripplanning-enterprise-<tenant-id>-db-password`
- `tripplanning-enterprise-<tenant-id>-internal-secret`
- `tripplanning-enterprise-<tenant-id>-external-api-key`

### Google Identity Platform

Identity Platform is the user-management source of truth for Standard and Enterprise tenants.

| Tier | Target |
| --- | --- |
| Free | Shared auth context. Use either project-level auth or one shared Free Identity Platform tenant. |
| Standard | One Identity Platform tenant per Standard tenant. Runtime remains shared, but users are isolated by Identity Platform tenant ID. |
| Enterprise | One Identity Platform tenant per Enterprise tenant, with tenant-specific provider settings where needed. |

Requirements:

- Tenant YAML must include an `identityPlatform` section.
- Provisioning must create/update/delete the Identity Platform tenant together with the infrastructure tenant.
- The frontend must set the Identity Platform `tenantId` before sign-in based on the current hostname.
- Backend services must verify ID tokens and read the Identity Platform tenant ID from the verified token/user context.
- The hostname-derived tenant and Identity Platform tenant ID must match the tenant registry entry.
- Do not use application database membership alone as the authentication source of truth.
- For Enterprise, tenant-specific SAML/OIDC providers can be configured in the Identity Platform tenant.
- Deleting a tenant must delete its Identity Platform tenant/users as part of destructive cleanup.

## Tenant Identity Source

Recommended tenant identity flow:

1. **Routing and frontend selection: hostname/subdomain.**
   - `acme.k8s.tbd-htwg.de` maps to tenant ID `acme`.
   - For Standard, many hostnames point to one Standard LoadBalancer.
   - For Enterprise, one hostname points to the tenant LoadBalancer.
   - The frontend uses this mapping to load tenant branding and configure the Identity Platform tenant before sign-in.

2. **Authenticated tenant source: Google Identity Platform tenant ID.**
   - Identity Platform user tokens include the tenant context for users signed in to a tenant.
   - Backend services verify the token and use the authenticated Identity Platform tenant ID as the authoritative user tenant.
   - Backend services reject requests where hostname tenant and Identity Platform tenant ID do not match.

3. **Internal propagation: trusted tenant context.**
   - API router can inject an internal tenant header after resolving the hostname.
   - Backend services trust this header only from internal router traffic.
   - Backend services still validate the verified Identity Platform tenant ID before accessing tenant data.

Do not use a client-supplied query parameter, arbitrary request header, or request body field as the source of truth for tenant identity.

## Tenant Definition File

Tenant creation should start from one declarative tenant definition. This can be YAML committed to Git and used by Terraform/Helm generation.

Use this provisioning pattern:

1. A developer creates or updates one YAML file under `infrastructure/ms2/tenants/<tier>/<tenant-id>.yaml`.
2. A small provisioning script validates the YAML schema.
3. The script generates Terraform `.tfvars` for cloud resources.
4. The script generates GitOps files and Helm values for Kubernetes resources.
5. Terraform applies cloud resources.
6. Flux/GitOps applies Kubernetes resources.

This keeps tenant intent human-readable while avoiding complex Terraform YAML parsing and avoiding hand-written repeated Kubernetes manifests.

Example Standard tenant:

```yaml
tenantId: acme
tier: standard
hostnames:
  - acme.k8s.tbd-htwg.de
frontend:
  bucketPrefix: standard/acme
  brandName: Acme Travel
  colorScheme: blue
  brandIcon: assets/brand-icon.png
identityPlatform:
  displayName: acme-standard
  tenantId: acme-standard
  emailPasswordEnabled: true
  mfaEnabled: false
database:
  cloudSqlInstance: tripplanning-standard
  databaseName: tripplanning_std_acme
storage:
  imagesPrefix: standard/acme
search:
  indexName: tripentity-acme
cache:
  keyPrefix: std:acme
features:
  customCode: false
```

Example Enterprise tenant:

```yaml
tenantId: acme
tier: enterprise
namespace: tripplanning-ent-acme
hostnames:
  - acme.enterprise.k8s.tbd-htwg.de
frontend:
  bucketPrefix: enterprise/acme
  brandName: Acme Travel Enterprise
  colorScheme: blue
  brandIcon: assets/brand-icon.png
identityPlatform:
  displayName: acme-enterprise
  tenantId: acme-enterprise
  emailPasswordEnabled: true
  mfaEnabled: true
  oidcProviders: []
  samlProviders: []
database:
  cloudSqlInstance: tripplanning-ent-acme
  databaseName: tripplanning
storage:
  imageBucketName: tripplanning-ent-acme-images
search:
  dedicated: true
  releaseName: opensearch-acme
cache:
  dedicated: true
services:
  trip:
    image:
      repository: ghcr.io/tbd-htwg/backend/acme-trip-service
      tag: 1.0.0
      pullPolicy: IfNotPresent
    replicas: 2
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 8
    resources:
      requests:
        cpu: "500m"
        memory: "768Mi"
      limits:
        cpu: "2000m"
        memory: "2Gi"
  social:
    image:
      repository: ghcr.io/tbd-htwg/backend/tripplanning-social-service
      tag: stable
    replicas: 2
  externalInfo:
    image:
      repository: ghcr.io/tbd-htwg/backend/tripplanning-external-info-service
      tag: stable
    replicas: 1
```

## Tenant Creation Process

### Standard Tenant Creation

1. Create a tenant definition file under a path such as `infrastructure/ms2/tenants/standard/acme.yaml`.
2. Terraform reads or is generated from the tenant definition and creates:
   - DNS record pointing `acme.k8s.tbd-htwg.de` to the Standard LoadBalancer IP.
   - Identity Platform tenant for `acme`.
   - Database `tripplanning_std_acme` in the shared Standard Cloud SQL instance.
   - Secret Manager entries for database credentials.
   - Optional search index/bootstrap job configuration.
   - Optional storage/frontend prefixes or metadata.
3. GitOps/Helm updates the Standard namespace:
   - API router ConfigMap gets the new hostname-to-tenant mapping.
   - Tenant config ConfigMap/Secret is updated.
   - ExternalSecret syncs tenant DB credentials if needed.
4. Frontend deployment uploads or copies tenant frontend files to `frontend-bucket/standard/acme/`.
5. Smoke tests verify:
   - DNS resolves to the Standard LoadBalancer.
   - Frontend sets the correct Identity Platform tenant ID before sign-in.
   - API router resolves tenant ID from hostname.
   - Backend rejects tokens from other Identity Platform tenants.
   - Tenant database/search/storage prefixes are used.

### Enterprise Tenant Creation

1. Create a tenant definition file under a path such as `infrastructure/ms2/tenants/enterprise/acme.yaml`.
2. Terraform reads or is generated from the tenant definition and creates:
   - Cloud SQL instance `tripplanning-ent-acme`.
   - Database and DB user.
   - Secret Manager entries.
   - DNS record for the tenant subdomain.
   - Identity Platform tenant for `acme`, including Enterprise-specific provider settings.
   - Dedicated image bucket.
3. GitOps creates tenant Kubernetes resources:
   - Namespace `tripplanning-ent-acme`.
   - ResourceQuota and LimitRange.
   - NetworkPolicies.
   - ServiceAccount with Workload Identity annotation.
   - ExternalSecrets.
   - HelmRelease with tenant-specific image tags, resources, replicas, HPA, hostnames, and frontend/storage/search/cache settings.
   - LoadBalancer Service for the tenant API router.
   - Dedicated OpenSearch resources.
4. Frontend deployment uploads or copies tenant frontend files to `frontend-bucket/enterprise/acme/`.
5. Smoke tests verify:
   - Tenant LoadBalancer is reachable.
   - DNS points to the tenant LoadBalancer.
   - Tenant services use the configured custom images.
   - Tenant services connect to the tenant Cloud SQL instance.
   - Frontend and backend use the correct Identity Platform tenant.
   - Resource limits and HPA are applied.

## Tenant Deletion Process

Deletion must be automated and destructive. Tenant data is not retained after tenant destruction. If data export is ever needed, it must be done manually before starting the deletion workflow.

### Standard Tenant Deletion

1. Mark tenant as `deleting` or `disabled` in the tenant registry.
2. API router stops accepting traffic for the tenant hostname or returns a controlled disabled response.
3. Remove DNS record.
4. Delete tenant frontend subfolder.
5. Delete image prefix.
6. Delete tenant database from the shared Standard Cloud SQL instance.
7. Delete tenant search index.
8. Delete Identity Platform tenant and users.
9. Delete tenant-specific secrets.
10. Remove tenant mapping/config from the Standard namespace.
11. Remove tenant definition file.

### Enterprise Tenant Deletion

1. Mark tenant as `deleting` or `disabled`.
2. Remove DNS record or route it to a controlled disabled response.
3. Delete HelmRelease and tenant namespace.
4. Delete tenant LoadBalancer Service and wait for cloud load balancer cleanup.
5. Delete frontend subfolder and dedicated image bucket.
6. Delete tenant Cloud SQL instance, including all tenant database data.
7. Delete Identity Platform tenant and users.
8. Delete tenant secrets and dedicated search/cache resources.
9. Remove tenant definition file.

## Terraform Requirements

Terraform should own cloud resources and should not encode tenant behavior directly in application code.

Required Terraform work:

- Create or extend a Standard Cloud SQL module:
  - one shared Standard Cloud SQL instance;
  - `for_each` databases for Standard tenants;
  - generated DB passwords in Secret Manager.
- Create an Enterprise tenant module:
  - Cloud SQL instance per tenant;
  - database/user/password;
  - Secret Manager secrets;
  - DNS record;
  - Identity Platform tenant if managed through Terraform or generated provisioning code;
  - dedicated image bucket;
  - dedicated OpenSearch resource metadata if managed through Terraform;
  - labels: `app=tripplanning`, `tier`, `tenant_id`, `managed_by=terraform`.
- Extend LoadBalancer/DNS handling:
  - one Standard LoadBalancer IP/DNS target;
  - one Enterprise LoadBalancer/DNS target per tenant.
- Keep platform resources reusable:
  - GKE cluster;
  - Artifact Registry access;
  - Secret Manager;
  - frontend bucket;
  - images bucket;
  - Identity Platform project configuration;
  - monitoring/logging.

Terraform code quality requirements:

- Use modules for repeated Standard/Enterprise tenant resources.
- Use `for_each` over tenant maps instead of copy-pasted resources.
- Use clear variable schemas for tenants.
- Add outputs needed by GitOps/Helm, such as DB connection names, LoadBalancer IPs, bucket names, and secret IDs.
- Add Identity Platform tenant IDs to generated tenant config consumed by frontend/backend.
- Add labels consistently to all cloud resources that support labels.
- Avoid hardcoded tenant names outside example files.

## Helm and GitOps Requirements

Helm should own Kubernetes resources and make tenant-specific configuration declarative.

Required Helm/GitOps work:

- Keep one reusable `tripplanning` chart.
- Add values for:
  - `tier`;
  - `tenantId`;
  - `hostnames`;
  - frontend bucket and prefix;
  - image bucket and prefix;
  - Cloud SQL connection/database settings;
  - service images per microservice;
  - replicas and autoscaling per microservice;
  - resource requests/limits per microservice;
  - search index name for Standard and dedicated OpenSearch settings for Enterprise;
  - Valkey key prefix or dedicated Valkey toggle;
  - API router mode: `free`, `standard`, or `enterprise`;
  - LoadBalancer enablement.
- Add values/config for Identity Platform tenant IDs and frontend auth initialization.
- Add `values-standard.yaml` for the shared Standard runtime.
- Add an Enterprise values template generated from the tenant definition.
- Disable in-chart Postgres for Standard and Enterprise.
- Keep in-chart Postgres available only for Free/dev.
- Generate API router config from values instead of manually editing Nginx config.
- Add ExternalSecret templates that can reference tenant-specific Secret Manager keys.

GitOps structure suggestion:

```text
infrastructure/ms2/gitops/tenants/
  free/shared/
  standard/shared/
    namespace.yaml
    helmrelease.yaml
    values-configmap.yaml
    tenant-router-config.yaml
  enterprise/acme/
    namespace.yaml
    resourcequota.yaml
    networkpolicy.yaml
    external-secrets.yaml
    helmrelease.yaml
    values-configmap.yaml
```

## 12-Factor Application Requirements

The application and deployment model should follow 12-factor principles where possible.

| Principle | Requirement for this project |
| --- | --- |
| Codebase | Keep service code in version control. Enterprise custom code should still be built as versioned images, not manually patched in clusters. |
| Dependencies | Services declare dependencies in their build files/images. Do not rely on manually installed packages in pods. |
| Config | Tenant-specific config comes from environment variables, ConfigMaps, Secrets, and Helm values. Do not hardcode tenant IDs, DB names, bucket prefixes, or hostnames. |
| Backing services | Treat Cloud SQL, Firestore, OpenSearch, Valkey, Storage, and external APIs as attached resources configured by environment. |
| Build/release/run | Build images once, release with Helm values, run in Kubernetes. Enterprise custom images must be immutable tags, not `latest`. |
| Processes | Services should be stateless. Tenant state belongs in Cloud SQL, Firestore, Storage, OpenSearch, or cache. |
| Port binding | Services expose ports through Kubernetes Services. |
| Concurrency | Scale through replicas/HPA, not in-process tenant-specific workers unless justified. |
| Disposability | Services must handle restarts, rolling updates, and SIGTERM cleanly. |
| Dev/prod parity | Keep Free/Standard/Enterprise differences in config and infrastructure, not in entirely different deployment logic. |
| Logs | Write logs to stdout/stderr with tenant ID where available. Central logging collects them. |
| Admin processes | Tenant bootstrap/migration/seed jobs should run as one-off Kubernetes Jobs or CI tasks using the same release config. |

## Code Quality and Safety Requirements

- Tenant isolation must be explicit in code paths that access data.
- Backend services must never trust a tenant ID supplied directly by the client.
- Backend services must verify Identity Platform ID tokens and compare token tenant ID with the hostname/router tenant.
- All data access helpers/repositories should require tenant context for tenant-owned data.
- Prefer typed tenant config models over string maps.
- Add tests for tenant isolation:
  - cross-tenant API access is rejected;
  - token tenant ID mismatch with hostname is rejected;
  - tenant A cannot read tenant B trips/comments/images/search results;
  - Standard tenant DB routing uses the right DB;
  - Enterprise tenant values select the configured images/resources.
- Keep Terraform, Helm, and app config generated from one tenant definition where possible.
- Avoid copy-pasting tenant manifests. Use templates/modules.
- Use immutable image tags for Enterprise custom service images.
- Add runbooks for tenant create, update, disable, delete, backup restore, and custom image rollout.

## Implementation Phases

1. **Define tenant identity and config model.** Use hostname for routing/frontend tenant selection and Identity Platform tenant ID for authenticated user identity.
2. **Update API router design.** Support host-to-tenant mapping for Standard and single-tenant config for Enterprise.
3. **Make backend services tenant-aware.** Verify Identity Platform tokens, compare authenticated tenant ID with hostname/router tenant, and propagate trusted tenant context.
4. **Make data access tenant-safe.** Standard uses database-per-tenant in shared Cloud SQL; Firestore, Storage, OpenSearch, and Valkey use tenant scopes/prefixes.
5. **Refactor Helm values.** Add tier, tenant, hostnames, LoadBalancer, Cloud SQL, frontend, storage, image, resource, and autoscaling values.
6. **Add Terraform/provisioning tenant modules.** Standard tenant DB/DNS/secrets/Identity Platform resources and Enterprise Cloud SQL/DNS/secrets/Identity Platform resources.
7. **Add GitOps templates.** Standard shared deployment and Enterprise namespace-per-tenant deployment.
8. **Automate tenant creation.** Generate Terraform `.tfvars` and GitOps files from the tenant definition.
9. **Automate tenant deletion.** Implement disabled state, DNS removal, resource cleanup, and final deletion without data retention.
10. **Pilot tenants.** Create one Standard and one Enterprise tenant and verify routing, isolation, scaling, frontend subfolder, and custom images.

## Finalized Conventions

- Standard domain pattern: `<tenant>.k8s.tbd-htwg.de`.
- Enterprise domain pattern: `<tenant>.enterprise.k8s.tbd-htwg.de`.
- Tenant source format: one YAML file per tenant.
- Provisioning approach: a small script validates tenant YAML and generates Terraform `.tfvars` plus GitOps/Helm files.
- User management: one Google Identity Platform tenant per Standard or Enterprise tenant.
- Standard image storage: shared images bucket with tenant prefixes.
- Enterprise image storage: dedicated image bucket per tenant from the beginning.
- Standard OpenSearch: shared OpenSearch with one tenant index.
- Enterprise OpenSearch: dedicated OpenSearch resource per tenant from the beginning.
- Tenant destruction: destructive cleanup with no retained tenant data.

## Recommended First Implementation Target

Start with this target because it gives good isolation and is still realistic to implement:

- Keep Free mostly as it is, with reduced resources and no per-tenant customization.
- Create one Standard namespace, one Standard LoadBalancer, one Standard API router, one Standard Cloud SQL instance, and database-per-Standard-tenant.
- Create Enterprise tenant automation that creates namespace, LoadBalancer, HelmRelease, custom service image settings, resource/scaling settings, Cloud SQL instance-per-tenant, image bucket-per-tenant, and OpenSearch-per-tenant.
- Use hostname for tenant routing/frontend selection, then validate it against the Google Identity Platform tenant ID in every backend service.
- Put Standard and Enterprise frontend builds/configs into per-tenant subfolders in the existing frontend bucket.
