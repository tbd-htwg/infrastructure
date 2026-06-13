# IaC and Tenant Setup Overview

This document gives a short overview of how a new Google Cloud project is set up and how tenants are created in the MS2 platform.

## What Terraform Creates

Terraform in `infrastructure/ms2/terraform/envs/dev` creates the cloud foundation:

- GCP APIs, service accounts, IAM, Secret Manager, DNS, logging.
- VPC and GKE Autopilot cluster.
- Cloud Storage buckets for frontend assets and shared images.
- Frontend HTTPS load balancer for the shared frontend.
- Static IPs and DNS records for tenant API subdomains.
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

## Routing Overview

The target routing model does not use GKE Gateway API.

```text
User
  -> frontend domain
  -> global HTTPS frontend load balancer
  -> frontend Cloud Storage bucket

Browser API call
  -> frontend domain /api/*
  -> global HTTPS frontend load balancer
  -> free api-router NEG
  -> platform-service for /api/v2/auth, /api/v2/admin, /api/v2/tenants
  -> tenant services for trip/social/external-info paths

User
  -> tenant API subdomain
  -> Kubernetes LoadBalancer Service
  -> in-namespace api-router
  -> trip/social/external-info services
```

Domain pattern:

- Free: shared app/API entrypoint.
- Standard: `<tenant>.k8s.tbd-htwg.de`
- Enterprise: `<tenant>.enterprise.k8s.tbd-htwg.de`

The `api-router` resolves the tenant from the hostname and forwards API traffic to the correct backend service. Backend services must verify that the Google Identity Platform tenant ID in the user token matches the hostname tenant.

The platform-service is intentionally outside tenant namespaces in `tripplanning-system`. It is control-plane infrastructure and should keep running even if a tenant namespace is recreated.

## Multitenancy by Tier

| Tier | Isolation model | Main resources |
| --- | --- | --- |
| Free | Shared runtime, shared namespace, shared backing services, best effort. | `tripplanning-free`, in-cluster Postgres/OpenSearch/Valkey, shared image bucket prefix. |
| Standard | Shared runtime, tenant-isolated data. | One `tripplanning-standard` namespace, one Standard LoadBalancer, one Standard API router, shared Standard Cloud SQL instance with database per tenant, shared image bucket prefixes. |
| Enterprise | Dedicated runtime and stronger isolation. | Namespace per tenant, LoadBalancer per tenant, API router per tenant, Cloud SQL instance per tenant, dedicated image bucket, dedicated OpenSearch, dedicated Valkey. |

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
```

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

- Standard runtime exists but its HelmRelease is suspended until backend support for tenant-aware database routing is implemented.
- Enterprise is the cleaner immediate tenant path because each tenant has its own runtime and Cloud SQL instance.

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
