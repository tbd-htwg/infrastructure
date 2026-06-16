# IaC and Tenant Setup Overview

This document gives a short overview of how a new Google Cloud project is set up and how tenants are created in the MS2 platform.

## What Terraform Creates

Terraform in `infrastructure/ms2/terraform/envs/dev` creates the cloud foundation:

- GCP APIs, service accounts, IAM, Secret Manager, DNS, logging.
- VPC and GKE Autopilot cluster.
- Cloud Storage buckets for frontend assets and shared images.
- Frontend HTTPS load balancer for the shared frontend.
- Static IPs and DNS records for tenant browser/API subdomains.
- Google Identity Platform tenants for Standard and Enterprise customers.
- Cloud SQL:
  - one small platform Cloud SQL instance for the platform-service tenant registry;
  - one shared Standard Cloud SQL instance with one database per Standard tenant;
  - one dedicated Cloud SQL instance per Enterprise tenant.
- Dedicated Enterprise image buckets.
- Optional Terraform-driven Flux bootstrap into the GKE cluster.

## What Flux and Helm Create

Flux reconciles Kubernetes resources from `infrastructure/ms2/gitops`.

Helm chart: `infrastructure/ms2/charts/tripplanning`

It deploys:

- platform-service in `tripplanning-system` for auth, tenant registry, and application-triggered provisioning
- `api-router`
- `trip-service`
- `social-service`
- `external-info-service`
- optional in-cluster backing services for Free/dev
- tenant LoadBalancer entrypoints
- ConfigMaps, ExternalSecrets, HPAs, resource requests/limits

## Setup Plan for a New GCP Project

1. Create a new GCP project and attach billing.
2. Configure `terraform/envs/dev/terraform.tfvars` from `terraform.tfvars.example`.
3. Set DNS zone/domain values.
4. Flux bootstrap is always enabled for this environment.
5. For private Git repositories, provide `flux_bootstrap_git_password` through a local uncommitted `secrets.auto.tfvars` file or `TF_VAR_flux_bootstrap_git_password`.
6. Install local bootstrap tools on the machine that runs Terraform:

```bash
sudo apt-get update
sudo apt-get install kubectl google-cloud-cli-gke-gcloud-auth-plugin
```

7. Populate or plan the required Secret Manager values:
   - `tripplanning-ghcr-pull-dockerconfigjson`
   - `tripplanning-jwt-secret`
   - `tripplanning-internal-secret`
   - `tripplanning-google-maps-api-key`
   - `tripplanning-viator-api-key`
   - `tripplanning-platform-github-dispatch-token` if tenants should be created from the application
8. Verify that `gitops/clusters/dev/flux-system/gotk-sync.yaml` points at the correct GitHub repository, branch, and path.
9. Run:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev init
terraform -chdir=infrastructure/ms2/terraform/envs/dev apply
```

10. Terraform creates the cluster and bootstraps Flux by applying `gitops/clusters/dev/flux-system`.
11. Flux then installs platform and tenant Kubernetes resources from Git.
12. Run smoke tests for frontend, tenant API routing, Identity Platform login, and service health.

`flux_bootstrap.manifest_dir` is relative to `terraform/envs/dev`; for this repository it should stay `../../../gitops/clusters/dev/flux-system`.

## Dev Cluster Capacity and Quotas

This environment is intentionally small, but GKE Autopilot still needs enough Compute Engine CPU quota to add nodes during rollouts. If pods stay `Pending` with `GCE quota exceeded`, check:

```bash
gcloud compute project-info describe --project tbd-cloudappdev \
  --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

The quota to watch is `CPUS_ALL_REGIONS`. This project currently has a low default limit, so running Free, Standard, and Enterprise at the same time can exceed quota or pod density during rollouts. For development, either run one shared tier at a time or request a quota increase in Google Cloud Console: **IAM & Admin -> Quotas -> CPUS_ALL_REGIONS**. A practical dev target is at least 32 CPUs; more is useful when adding Enterprise tenants with dedicated OpenSearch.

The Helm chart uses no-surge rolling updates for shared services so upgrades do not temporarily double pod count. Standard also uses reduced dev resources for OpenSearch and waits for Valkey/OpenSearch before starting trip-service.

## Terraform State

Tenant automation requires shared Terraform state. The dev environment uses this GCS backend:

```text
bucket: tbd-cloudappdev-tfstate
prefix: ms2/dev
```

If the project was already applied locally before the backend existed, migrate the local state once before running tenant workflows:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev init -migrate-state
```

After migration, rerun:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev plan
```

The plan should not try to recreate shared resources such as `tripplanning-standard-lb-ip`, `terraform-deployer`, `tbd-dns-zone`, the frontend/images/tfstate buckets, or existing Secret Manager secrets. If it does, stop and fix state before running tenant provisioning.

For a brand-new project, create the state bucket before enabling the backend or do one local bootstrap apply, then immediately migrate the state to GCS before any GitHub Actions workflow runs Terraform.

## Routing Overview

The target routing model does not use GKE Gateway API.

```text
User
  -> frontend or tenant domain
  -> global HTTPS frontend load balancer
  -> frontend Cloud Storage bucket

Browser API call
  -> same domain /api/*
  -> global HTTPS frontend load balancer
  -> Standard or Enterprise api-router backend
  -> platform-service for /api/v2/auth, /api/v2/admin, /api/v2/tenants
  -> tenant services for trip/social/external-info paths
```

Domain pattern:

- Free: shared app/API entrypoint.
- Standard: `<tenant>.k8s.tbd-htwg.de`
- Enterprise: `<tenant>.enterprise.k8s.tbd-htwg.de`

Only `tbd-dns-zone` (`tbd-htwg.de.`) should be used for public records. Do not create a separate public managed zone for `k8s.tbd-htwg.de.` unless the parent zone delegates NS records to it. Without delegation, the child zone is orphaned and public DNS ignores it.

Tenant A records point to the global frontend load balancer IP. The frontend load balancer serves the shared frontend bucket for normal browser routes and forwards `/api/*` to the correct Kubernetes `api-router`:

- Standard tenants share one Standard `api-router` LoadBalancer in `tripplanning-standard`.
- Enterprise tenants each keep a dedicated `api-router` LoadBalancer in their own namespace. The frontend load balancer has a host-specific `/api/*` backend for each Enterprise tenant.

New tenant hostnames are added to the frontend HTTPS certificate. Google-managed certificates can take time to provision after Terraform apply, so a tenant may be reachable over DNS before HTTPS is marked `ACTIVE`.

The frontend load balancer uses `EXTERNAL_MANAGED` forwarding rules for tenant host routing. In existing projects that still have older classic forwarding rules or the old `api-backend-service`, Terraform replaces them with managed resources instead of migrating them in place. This avoids Google Cloud migration-state errors around backend buckets and Internet NEGs.

The `api-router` receives the original `Host` header, resolves the tenant from the hostname, and forwards API traffic to the correct backend service. Backend services must verify that the Google Identity Platform tenant ID in the user token matches the hostname tenant.

The platform-service is intentionally outside tenant namespaces in `tripplanning-system`. It is control-plane infrastructure and should keep running even if a tenant namespace is recreated.

## Multitenancy by Tier

| Tier | Isolation model | Main resources |
| --- | --- | --- |
| Free | Shared runtime, shared namespace, shared backing services, best effort. | `tripplanning-free`, in-cluster Postgres/OpenSearch/Valkey, shared image bucket prefix. |
| Standard | Shared runtime, tenant-isolated data. | One `tripplanning-standard` namespace, one Standard API router behind one Standard LoadBalancer, shared Standard Cloud SQL instance with database per tenant, shared frontend bucket, shared image bucket prefixes. |
| Enterprise | Dedicated runtime and stronger isolation. | Namespace per tenant, API router behind a tenant LoadBalancer, Cloud SQL instance per tenant, shared frontend bucket with tenant prefix, dedicated image bucket, dedicated OpenSearch, dedicated Valkey. |

## How Tenants Are Created Right Now

Tenants can be created in two ways:

- manually, by adding tenant YAML and running the render/apply flow below;
- from the application, through platform-service, once the platform-service image is deployed and `tripplanning-platform-github-dispatch-token` is populated in Secret Manager.

Tenant intent is written as YAML under `infrastructure/ms2/tenants`.

Examples:

- `tenants/standard/example-acme.yaml`
- `tenants/enterprise/example-globex.yaml`

Current flow:

1. Copy an example tenant YAML and remove the `example-` prefix.
2. Adjust tenant ID, hostnames, branding, Identity Platform settings, database names, and storage/search settings.
3. Generate Terraform inputs only:

```bash
cd infrastructure/ms2
python3 scripts/render-tenants.py --terraform-only
```

4. Apply Terraform so cloud resources are created:

```bash
terraform -chdir=terraform/envs/dev apply
```

5. Render Kubernetes GitOps with Terraform-computed values:

```bash
terraform -chdir=terraform/envs/dev output -json > /tmp/ms2-terraform-output.json
python3 scripts/render-tenants.py --terraform-output-json /tmp/ms2-terraform-output.json
```

6. Commit and push the tenant YAML, generated Terraform input file, and generated GitOps files.
7. Flux reconciles the cluster.
8. Run tenant smoke tests.

For Standard tenants, the render step also creates `gitops/tenants/standard/shared/generated-db-external-secret.yaml`. This keeps the tenant DB password in a separate Kubernetes Secret (`trip-service-db-secrets`) and avoids multiple ExternalSecrets trying to own the same target Secret.

The repository workflow `.github/workflows/tenant-provision.yml` can perform the same first step from a `repository_dispatch` or manual run. By default it commits tenant YAML plus Terraform inputs only. If `TENANT_PROVISION_APPLY_TERRAFORM=true`, it also applies Terraform, rerenders GitOps with real outputs, and commits the Kubernetes manifests.

Application-driven creation path:

```text
Admin UI
  -> platform-service in tripplanning-system
  -> Google Identity Platform tenant creation
  -> GitHub repository_dispatch to infrastructure repo
  -> .github/workflows/tenant-provision.yml
  -> tenant YAML / Terraform inputs / GitOps render
  -> Flux reconciles Kubernetes resources
  -> workflow calls platform-service /internal/tenants/{slug}/provisioning-callback
```

For application-driven creation, platform-service creates the Identity Platform tenant first and sends `identityPlatformTenantId` in the GitHub dispatch payload. The provisioning workflow writes that ID into the tenant YAML, and Terraform then skips creating a second Identity Platform tenant for that tenant. For manual `workflow_dispatch` runs, no pre-created Identity Platform tenant ID is provided, so Terraform creates the Identity Platform tenant.

When `TENANT_PROVISION_APPLY_TERRAFORM=true`, the provisioning workflow waits for the generated tenant HelmRelease to become ready and then marks the tenant `ACTIVE` through the internal platform-service callback. The callback is protected by `X-Internal-Secret` using `tripplanning-internal-secret`.

If `tripplanning-platform-github-dispatch-token` is missing, platform-service can still start, but real tenant provisioning cannot dispatch to GitHub.

Required GitHub configuration for workflow-based provisioning:

- Environment: `gke-dev` if environment protection is enabled.
- Secrets in the infrastructure repo: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_TERRAFORM_SERVICE_ACCOUNT`, `FLUX_BOOTSTRAP_GIT_PASSWORD`, and `BACKEND_REPOSITORY_DISPATCH_TOKEN`.
- Variables in the infrastructure repo: `GCP_PROJECT_ID`, `BACKEND_REPOSITORY`, and optional `TENANT_PROVISION_APPLY_TERRAFORM=true`.
- Repository permissions: GitHub Actions must allow `contents: write` and `id-token: write`.

Terraform creates the infrastructure repository identity for optional CI Terraform applies. After applying Terraform, copy these outputs into the infrastructure repository environment `gke-dev`:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev output infra_wif_provider
terraform -chdir=infrastructure/ms2/terraform/envs/dev output infra_terraform_service_account
```

Use them as:

- `GCP_WORKLOAD_IDENTITY_PROVIDER` = `infra_wif_provider`
- `GCP_TERRAFORM_SERVICE_ACCOUNT` = `infra_terraform_service_account`

Use CI Terraform apply only after the Terraform backend is shared/remote. Otherwise, apply locally and commit the rerendered outputs.

The infrastructure Terraform service account needs enough read/write permissions to refresh and modify all Terraform-managed resources. Terraform manages these roles after the first successful apply, but if CI fails with `artifactregistry.repositories.get denied`, grant the missing role once with an owner/admin account:

```bash
gcloud projects add-iam-policy-binding tbd-cloudappdev \
  --member="serviceAccount:terraform-deployer@tbd-cloudappdev.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding tbd-cloudappdev \
  --member="serviceAccount:terraform-deployer@tbd-cloudappdev.iam.gserviceaccount.com" \
  --role="roles/servicenetworking.networksAdmin"
```

Then rerun `terraform plan` or the tenant provisioning workflow. Terraform will keep the role in code afterwards.

## Deleting Tenants and Failed Runs

Tenant infrastructure is declarative. A tenant exists because its YAML file exists under `ms2/tenants`.

Preferred deletion path:

1. Run `.github/workflows/tenant-delete.yml`.
2. Choose the tier and slug.
3. Repeat the slug in `confirm_slug`.
4. The workflow removes the tenant YAML, rerenders Terraform input, applies Terraform, rerenders GitOps, and commits the deletion.
5. Flux removes the tenant Kubernetes resources from the cluster.

This deletes tenant-owned data resources. The current design intentionally does not retain tenant data after tenant destruction.

Manual cleanup path:

```bash
rm infrastructure/ms2/tenants/standard/<slug>.yaml
# or:
rm infrastructure/ms2/tenants/enterprise/<slug>.yaml

cd infrastructure/ms2
python3 scripts/render-tenants.py --terraform-only
terraform -chdir=terraform/envs/dev apply
terraform -chdir=terraform/envs/dev output -json > /tmp/ms2-terraform-output.json
python3 scripts/render-tenants.py --terraform-output-json /tmp/ms2-terraform-output.json
```

If tenant creation fails before the workflow commits tenant files, usually nothing needs to be deleted from Git. If creation fails after Terraform creates tenant resources, rerun the same tenant workflow after fixing the error, or use the deletion workflow once the tenant YAML has been committed.

`409 already exists` errors for shared resources are not a tenant cleanup problem. They mean Terraform is running without the state that owns those resources. Migrate or repair Terraform state before creating or deleting tenants.

## Secret Manager Values

Terraform creates the Secret Manager secret resources and IAM permissions. Most runtime values are synced by backend CI. The platform GitHub dispatch token can be written automatically by Terraform when `platform_github_dispatch_token` is provided.

The values are synced by the backend repository workflow `.github/workflows/sync-gke-secrets.yml`. Configure these GitHub secrets in the backend repository environment `gke-dev`:

- `TRIPPLANNING_AUTH_JWT_SECRET` -> `tripplanning-jwt-secret`
- `TRIPPLANNING_INTERNAL_SECRET` -> `tripplanning-internal-secret`
- `GOOGLE_MAPS_API_KEY` -> `tripplanning-google-maps-api-key`
- `VIATOR_API_KEY` -> `tripplanning-viator-api-key`
- `GHCR_PULL_USERNAME` and `GHCR_PULL_TOKEN` -> `tripplanning-ghcr-pull-dockerconfigjson`

For application-driven tenant creation, provide a GitHub token with permission to dispatch workflows in the infrastructure repository.

Local Terraform apply:

```bash
export TF_VAR_platform_github_dispatch_token="github_pat_or_token"
export TF_VAR_flux_bootstrap_git_password="github_pat_or_token"
terraform -chdir=infrastructure/ms2/terraform/envs/dev apply
```

CI Terraform apply:

- Add infrastructure repo environment secret `PLATFORM_GITHUB_DISPATCH_TOKEN`.
- `tenant-provision.yml` passes it to Terraform as `TF_VAR_platform_github_dispatch_token`.

Terraform stores this value in Terraform state because Secret Manager versions are stateful Terraform resources. Use the remote state bucket with restricted access and rotate the token if it is ever exposed.

The backend workflow also needs backend repo variables `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, and `GCP_SECRETS_DEPLOYER_SA_EMAIL` or `GCP_BACKEND_DEPLOYER_SA_EMAIL`. Terraform outputs the required values as `backend_wif_provider` and `secrets_deployer_sa_email`.

Run the backend workflow manually once after the first Terraform apply. After tenant GitOps changes, the infrastructure repo root workflow `.github/workflows/dispatch-backend-secret-sync.yml` dispatches `tenant-created` to the backend repo so the same sync can run again.

For Flux bootstrap locally, use one of these options:

```bash
export TF_VAR_flux_bootstrap_git_password="github_pat_or_token"
terraform -chdir=infrastructure/ms2/terraform/envs/dev apply
```

or create the ignored local file `infrastructure/ms2/terraform/envs/dev/secrets.auto.tfvars`:

```hcl
flux_bootstrap_git_password = "github_pat_or_token"
```

When reusing an old project, some Secret Manager secrets may already exist outside the current Terraform state. Import them instead of deleting them. Example:

```bash
terraform -chdir=infrastructure/ms2/terraform/envs/dev import \
  'module.project_bootstrap.google_secret_manager_secret.secrets["tripplanning-auth-test-bearer-token"]' \
  projects/tbd-cloudappdev/secrets/tripplanning-auth-test-bearer-token
```

Important current limitation:

- Standard runtime supports the current single-tenant smoke path through the shared Standard Cloud SQL instance and generated tenant DB Secret. Multiple Standard tenants may need additional backend work or a shared Standard DB user strategy if each tenant must use different DB credentials at runtime.
- Enterprise remains the cleaner high-isolation path because each tenant has its own runtime, Cloud SQL instance, image bucket, and OpenSearch.

## Tenant Deletion

Tenant deletion is destructive by design.

For Standard:

- Remove DNS record.
- Delete tenant database from the shared Standard Cloud SQL instance.
- Delete tenant Identity Platform tenant/users.
- Delete frontend subfolder, image prefix, search index, and tenant secrets.
- Remove tenant YAML and generated config.

For Enterprise:

- Remove DNS record.
- Delete tenant namespace, LoadBalancer, Cloud SQL instance, Identity Platform tenant/users, image bucket, OpenSearch, Valkey, frontend subfolder, and secrets.
- Remove tenant YAML and generated config.

No tenant data is retained after destruction.
