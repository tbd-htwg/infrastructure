# M3 multitenancy — status & follow-up

Short map from [tiered_multitenancy_plan.md](./tiered_multitenancy_plan.md) to what exists today, what is still open, and where we deliberately differ.

**Today in prod (ms2):** single `tripplanning-free` namespace, GCS frontend, and the free-tier `api-router` NEG on the frontend HTTPS LB. Gateway API is removed from GitOps. See [ms2_report.md](./ms2_report.md).

**Target:** three tiers (Free / Standard / Enterprise), subdomain routing, Terraform DNS, no GKE Gateway API, `repository_dispatch` from platform-service into this repo.

**After M3 application + infra implementation:** application code and GitOps/Terraform definitions for multitenancy are largely complete. Remaining work is **deploying new images**, **Flux/Terraform rollout**, **GitHub environment configuration**, and **end-to-end smoke**.

---

## Already in the application (backend + frontend)

Implemented in backend and frontend repos; requires image publish + cluster reconcile to take effect in prod.

| Area | What exists |
|------|-------------|
| **platform-service** (:8083) | Tenant registry, admin CRUD, async provisioning, Identity Platform client (stub + real) |
| **Auth** | `POST /api/v2/auth/firebase`, `dev-login`, `GET /auth/me` on platform only; trip/social/external validate JWT |
| **Tenant resolution** | `Host` / `X-Forwarded-Host` → slug + tier; `GET /api/v2/tenants/{slug}/public-config` |
| **Provisioning dispatch** | Unified pipeline; `repository_dispatch` to infra repo; stub mode completes locally |
| **Provisioning callback** | `POST /internal/tenants/{slug}/provisioning-callback` — advances steps, creates search index (Standard), reconciles Enterprise resources, sets `ACTIVE` |
| **Per-tenant DB credentials** | `SecretManagerTenantDbCredentialProvider` reads `tripplanning-standard-{slug}-db-password` / enterprise equivalents; exposed on `GET /internal/tenants/{slug}` as `dbUser` + `dbPassword` |
| **Standard DB routing** | `TenantRoutingDataSource` + per-tenant creds; `TenantSchemaMigrator` runs Flyway on first tenant pool; gated by `TRIPPLANNING_TENANT_DATASOURCE_ROUTING` |
| **Per-tenant search** | `TenantIndexLayoutStrategy` + tenant-scoped `SearchIndexCoordinationService`; lazy bootstrap via `TenantSearchIndexBootstrapFilter` when routing enabled |
| **Isolation** | Firestore tenant-scoped; GCS bucket/prefix from platform; Valkey keys tenant-prefixed |
| **User APIs** | Platform admin/public user lists; trip internal `/internal/users` |
| **Admin UI** | Tenant list/detail/create, branding, provisioning timeline, stub banner; list polling while provisioning; Enterprise host preview; `TenantNotReadyGate` on tenant subdomains |
| **Local dev** | `dev.sh` — four JVM services :8080–:8083; Minikube chart routes `/api/v2/auth\|admin\|tenants` → platform |
| **CI / packaging** | platform image in Dockerfile + `docker-publish-gke` |
| **Hygiene** | `TestBearerMisconfigurationWarning` when test bearer is set under `k8s` profile; test bearer kept in ExternalSecrets for gke-dev/Locust |

---

## Already in infrastructure (this repo)

Defined in Git on `main`; not necessarily reconciled in the live cluster yet.

| Area | What exists |
|------|-------------|
| **Entry traffic** | Gateway API removed. Chart `api-router` routes by hostname and proxies `/api/v2/auth\|admin\|tenants` → `platform-service` when `apiRouter.platform.enabled` (default `true`). |
| **Tier pools** | GitOps: `tenants/free/shared`, `tenants/standard/shared`, `tenants/enterprise/{slug}/` (generated). Helm values: `values-free.yaml`, `values-standard.yaml`, `values-enterprise.yaml`. |
| **DNS** | `terraform/modules/tenant-dns/`; Standard apex + per-tenant A records from `generated-tenants.auto.tfvars.json`. |
| **Cloud SQL** | Terraform: `platform_cloudsql`, `standard_cloudsql`, per-Enterprise `tenant-cloudsql`. |
| **Dispatch workflows** | Root `.github/workflows/tenant-provision.yml` and `tenant-delete.yml`. |
| **Provisioning callback hook** | `tenant-provision.yml` posts to `POST /internal/tenants/{slug}/provisioning-callback` when `PLATFORM_CALLBACK_BASE_URL` + `PLATFORM_INTERNAL_SECRET` are set. |
| **Renderer** | `ms2/scripts/render-tenants.py` — tenant YAML → Terraform tfvars, Standard generated configmap, Enterprise per-slug GitOps (incl. test bearer on all services). |
| **platform-service GitOps** | `gitops/platform/platform-service/` — Deployment, Cloud SQL JDBC, `USE_STUBS=false`, dispatch URL, `TRIPPLANNING_PLATFORM_GCP_PROJECT_ID`. |
| **Standard GitOps wiring** | `values-configmap.yaml`: `TRIPPLANNING_TENANT_DATASOURCE_ROUTING=true`, `TRIPPLANNING_PLATFORM_BASE_URL`, `global.cloudSql.*`. ExternalSecrets incl. test bearer on all three services. |
| **Platform GSM IAM** | Terraform `platform_secret_accessor` for `platform-admin@` to read tenant DB password secrets. |
| **Secret sync hook** | Root `.github/workflows/dispatch-backend-secret-sync.yml` fires `tenant-created` on backend when tenant GitOps changes. |
| **Sample Standard tenant** | `tenants/standard/test03.yaml` + rendered DNS/LB IP in generated config. |

See [iac_tenant_setup_overview.md](./iac_tenant_setup_overview.md) for the full setup and apply flow.

---

## Still needed — application

| Item | Why |
|------|-----|
| **Publish & deploy images** | New platform-service and trip-service code (callback, routing, search) must be built and rolled out via `docker-publish-gke` + Flux image pull. |
| **Callback failure path in workflow** | `tenant-provision.yml` only posts `SUCCESS`; add failure callback (or manual ops runbook) when Terraform/Flux steps fail. |
| **Platform OpenSearch bootstrap (optional)** | Standard callback calls `createSearchIndex()`; needs `TRIPPLANNING_PLATFORM_OPENSEARCH_*` on platform-service if index `PUT` should run from platform pod (otherwise trip-service mass-index creates it). |
| **Enterprise callback resource fields** | Infra workflow should pass `gcsBucket`, `dbName`, `dbUser` overrides in callback payload when they differ from platform pre-compute (especially `{project_id}-{slug}-images-bucket`). |
| **Integration / E2E tests** | Callback and multi-tenant routing covered by unit tests; no automated smoke against live GKE yet. |

---

## Still needed — infrastructure (rollout & ops)

| Area | Work |
|------|------|
| **GitHub environment vars** | Set `PLATFORM_CALLBACK_BASE_URL` (platform-service URL reachable from Actions) and `PLATFORM_INTERNAL_SECRET` on infra repo `gke-dev` environment. Optionally `TENANT_PROVISION_APPLY_TERRAFORM=true`. |
| **Flux reconcile** | Apply GitOps so `tripplanning-system`, `tripplanning-standard`, and generated Enterprise dirs exist in the cluster. Free tier is live today. |
| **Terraform apply for tenants** | `tenant-provision.yml` commits YAML + `generated-tenants.auto.tfvars.json`. Cloud resources need `TENANT_PROVISION_APPLY_TERRAFORM=true` or manual `terraform apply` + `render-tenants.py --terraform-output-json`. |
| **Standard LB IP** | `values-configmap.yaml` has empty `apiRouter.loadBalancer.ip`; populate from Terraform output after apply (test03 generated config has `34.52.217.31`). |
| **Enterprise runtime** | No enterprise tenant YAML checked in yet; renderer generates per-slug tree on first Enterprise provision. |
| **api-router → platform routing in Standard pool** | Confirm Standard `api-router` can reach `platform-service.tripplanning-system.svc.cluster.local` for auth/admin paths (network policy / cluster DNS). |
| **End-to-end smoke** | Admin UI → dispatch → Terraform → Flux → callback → ACTIVE → login on `{slug}.k8s.tbd-htwg.de` / `{slug}.enterprise.k8s.tbd-htwg.de`. |
| **Docs drift** | [ms2_report.md](./ms2_report.md) still describes Free tier only; update after Standard/Enterprise go live. |

**Workflow recap:** Admin UI → platform-service → `repository_dispatch` → `tenant-provision.yml` → commit tenant YAML + generated inputs → (optional) Terraform apply → Flux → **callback** (when env vars set) → tenant `ACTIVE`.

**Secrets:** Platform secrets from Terraform Secret Manager + platform ExternalSecrets. Tenant workload secrets via backend `sync-gke-secrets.yml` → Secret Manager → tenant ExternalSecrets (incl. test bearer for gke-dev).

---

## Where application and plan diverge

| Topic | tiered_multitenancy_plan.md | Application / infra today |
|-------|----------------------------|---------------------------|
| **Provisioning trigger** | One tenant YAML → script → Terraform + GitOps | Admin UI → platform-service → `repository_dispatch` → infra workflow (aligned on outcome; different entrypoint) |
| **Provisioning completion** | Infra finishes → tenant active | Infra workflow → `POST /internal/tenants/{slug}/provisioning-callback` → platform sets `ACTIVE` |
| **DNS** | Terraform owns all A records | Java never calls Cloud DNS; Terraform + `render-tenants.py` own records |
| **API router** | Per-tier in-namespace router; host → tenant | Implemented in chart + generated tenant host maps; free tier live; Standard/Enterprise pending cluster rollout |
| **Frontend** | GCS subfolder per tenant (`standard/{slug}/`) | Single SPA build; subdomain selects tenant; `frontendPath` / `bucketPrefix` is metadata for assets |
| **Local dev** | Not specified | Full provisioning pipeline with `TRIPPLANNING_PLATFORM_USE_STUBS=true` (default); `VITE_DEMO_MODE` = frontend-only mocks |
| **platform-service** | Not in original ms2 model | Fourth microservice; auth/admin/registry removed from trip-service; GitOps manifest added |
| **DB credentials** | Per-tenant Cloud SQL users in Terraform | Platform reads GSM secrets; trip-service fetches creds via internal API (not per-tenant K8s secrets) |
| **Search** | Per-tenant index | `TenantIndexLayoutStrategy` maps logical `tripentity` → `tripentity-{slug}` when routing enabled |

**Aligned:** tier names (`FREE` / `STANDARD` / `ENTERPRISE`), host patterns (`{slug}.k8s…`, `{slug}.enterprise.k8s…`), Identity Platform tenant per paid tenant, Postgres-per-tenant, no GKE Gateway as target.

---

## Related

- [tiered_multitenancy_plan.md](./tiered_multitenancy_plan.md) — full target architecture
- [iac_tenant_setup_overview.md](./iac_tenant_setup_overview.md) — Terraform, Flux, tenant create/delete flow
- [ms2_report.md](./ms2_report.md) — current GKE baseline (Free tier; update when Standard/Enterprise go live)
- `backend/scripts/README.md` — JVM local dev
- `frontend/DEMO.md` — admin UI without backend
