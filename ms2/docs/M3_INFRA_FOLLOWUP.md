 M3 multitenancy — status & follow-up

Short map from [tiered_multitenancy_plan.md](./tiered_multitenancy_plan.md) to what exists today, what is still open, and where we deliberately differ.

**Today in prod (ms2):** single `tripplanning-free` namespace and GCS frontend. Gateway API is no longer the target routing model. See [ms2_report.md](./ms2_report.md).

**Target:** three tiers (Free / Standard / Enterprise), subdomain routing, Terraform DNS, no GKE Gateway API, `repository_dispatch` from platform-service into this repo.

---

## Already in the application (backend + frontend)

Enough to develop and demo multitenancy locally; not enough to run Standard/Enterprise in GKE without infra.

| Area | What exists |
|------|-------------|
| **platform-service** (:8083) | Tenant registry, admin CRUD, async provisioning, Identity Platform client (stub + real) |
| **Auth** | `POST /api/v2/auth/firebase`, `dev-login`, `GET /auth/me` on platform only; trip/social/external validate JWT |
| **Tenant resolution** | `Host` / `X-Forwarded-Host` → slug + tier; `GET /api/v2/tenants/{slug}/public-config` |
| **Provisioning** | Unified pipeline (Standard + Enterprise); `repository_dispatch` to infra repo; stub mode completes locally with warnings |
| **Isolation** | Firestore writes tenant-scoped; GCS bucket/prefix from platform runtime; Valkey keys tenant-prefixed |
| **User APIs** | Platform admin/public user lists; trip internal `/internal/users` (list + by-ids + delete) |
| **Admin UI** | Tenant list/detail/create, branding, provisioning timeline, stub banner, login gated by `enabledAuthProviders` |
| **Local dev** | `dev.sh` — four JVM services :8080–:8083; Minikube chart routes `/api/v2/auth\|admin\|tenants` → platform (nginx ingress only) |
| **CI / packaging** | platform image in Dockerfile + `docker-publish-gke`; local Helm deployment/service/configmap |

---

## Still needed — application

| Item | Why |
|------|-----|
| **GKE platform-service deploy** | Image exists; no Flux/Helm release or Cloud SQL `tripplanning_platform` in prod yet |
| **`use-stubs=false` completion** | Infra workflow now waits for Flux/Helm readiness and calls `POST /internal/tenants/{slug}/provisioning-callback` |
| **Prod secrets** | `TRIPPLANNING_PLATFORM_GITHUB_DISPATCH_*`, bootstrap admin, shared JWT/internal secret on all four services |
| **Per-tenant search writes** | Index naming stubbed; Hibernate Search write coordination not done |
| **Hygiene** | Disable test bearer in prod; extend backend secret-sync for platform |

---

## Still needed — infrastructure (this repo)

| Area | Work |
|------|------|
| **Entry traffic** | Gateway API manifests are removed from the target path. Tenant API traffic uses Kubernetes `LoadBalancer` Services and in-namespace `api-router` deployments. Frontend traffic stays on the GCS HTTPS load balancer. |
| **Tier pools** | GitOps: Free shared namespace, Standard shared namespace, generated `enterprise/{slug}/`; shared Standard namespace + per-Enterprise namespace |
| **DNS** | `terraform/modules/tenant-dns/` exists and is wired into `terraform/envs/dev`; tenant A records are created from tenant definitions. |
| **Dispatch workflow** | Root `.github/workflows/tenant-provision.yml` writes tenant YAML and Terraform inputs from `tenant-created-standard` / `tenant-created-enterprise`. Optional CI Terraform apply can also create cloud resources and rerender GitOps with computed outputs. |
| **Platform DB** | Cloud SQL `tripplanning_platform`; JDBC + Flyway for platform-service on GKE |
| **LB layout** | Free: shared apex; Standard: one LB, `{slug}.k8s…` → same IP; Enterprise: one LB per tenant, `{slug}.enterprise.k8s…` |
| **Runtime caveat** | Standard now boots for the current smoke path through the shared Standard Cloud SQL instance. Multiple Standard tenants still need a clear backend credential strategy if tenant DB users differ. |

**Workflow:** root `.github/workflows/tenant-provision.yml` creates tenant YAML and generated Terraform inputs. Optional CI Terraform apply is gated by `TENANT_PROVISION_APPLY_TERRAFORM=true`; otherwise apply Terraform manually, then rerender GitOps with Terraform outputs. **GitOps today:** Free and Standard base tiers exist; Enterprise tenant directories are generated from tenant YAML. The old `ms2/.github/workflows` path is not used for tenant provisioning because GitHub Actions only runs workflows from the repository root.

**Secrets:** root `.github/workflows/dispatch-backend-secret-sync.yml` dispatches `tenant-created` to the backend repository after tenant GitOps changes. The backend workflow `.github/workflows/sync-gke-secrets.yml` owns the runtime Secret Manager values.

---

## Where application and plan diverge

| Topic | tiered_multitenancy_plan.md | Application today |
|-------|----------------------------|-------------------|
| **Provisioning trigger** | One tenant YAML → script → Terraform + GitOps | Admin UI → platform-service → `repository_dispatch` → infra workflow |
| **DNS** | Terraform owns all A records | Java never calls Cloud DNS; dispatch carries slug/tier/host to infra workflow |
| **API router** | Per-tier in-namespace router; host → tenant | Local: nginx ingress path split; prod router not deployed yet |
| **Frontend** | GCS subfolder per tenant (`standard/{slug}/`) | Single SPA build; subdomain selects tenant; `frontendPath` is metadata only |
| **Local dev** | Not specified | Full provisioning pipeline with `TRIPPLANNING_PLATFORM_USE_STUBS=true` (default); `VITE_DEMO_MODE` = frontend-only mocks |
| **platform-service** | Not in original ms2 model | Fourth microservice; auth/admin/registry removed from trip-service |
| **Standard automation** | Same Terraform/GitOps as Enterprise (shared pool) | Same dispatch events; local stub skips real Terraform |
| **Prod tenant state** | Infra completes → tenant active | Stub: auto-ACTIVE; prod workflow callback marks tenants ACTIVE after Terraform/Flux completes |

**Aligned:** tier names (`FREE` / `STANDARD` / `ENTERPRISE`), host patterns (`{slug}.k8s…`, `{slug}.enterprise.k8s…`), Identity Platform tenant per paid tenant, Postgres-per-tenant (Standard DB in shared instance; Enterprise dedicated instance), no GKE Gateway as target.

---

## Related

- [tiered_multitenancy_plan.md](./tiered_multitenancy_plan.md) — full target architecture
- [ms2_report.md](./ms2_report.md) — current GKE baseline
- `backend/scripts/README.md` — JVM local dev
- `frontend/DEMO.md` — admin UI without backend
