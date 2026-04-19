# Tripplanning GCP infrastructure (Terraform)

Terraform is the **single source of truth** for this stack. Do **not** run `gcloud run deploy`
or the [`../paas/deploy-*-cloudrun.sh`](../paas/) scripts against the Cloud Run service Terraform
manages — use the two-stage flow below and push a new backend tag through stage 1 when you
release a new image.

The stack is split into **two idempotent root modules** under this directory:

- [`stage1/`](stage1/) — **assets**: Artifact Registry (Docker) + GCS frontend bucket (+ docker
  push + SPA build + upload from the wrapper script).
- [`stage2/`](stage2/) — **app runtime**: APIs, Cloud SQL with PITR, Secret Manager, Cloud Run,
  HTTPS load balancer + Cloud CDN + managed SSL + **HTTP→HTTPS redirect**, Cloud DNS A records,
  and an optional **Cloud Armor** WAF.

Every resource converges to declared state on reapply; every shell action in the wrapper is
reentrant (content-addressed rsync, digest-idempotent docker pushes, best-effort CDN
invalidation). Running each stage twice with the same inputs is a no-op plan.

## Prerequisites

- GCP project with billing enabled.
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 (or `hashicorp/terraform`
  Docker; on Fedora use `-v "$PWD:/tf:z"` for SELinux).
- Credentials for the Google provider
  (`gcloud auth application-default login` on the host, or `GOOGLE_APPLICATION_CREDENTIALS` in
  Docker — see below).
- For stage 1 of [`terraform-stage.sh`](terraform-stage.sh): Docker, `npm`, and `gcloud` on your
  PATH.
- An **existing** Cloud DNS managed zone named by [`dns_managed_zone_name`](terraform.tfvars.example).
  The zone itself is never created or destroyed by Terraform.

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: project_id, region, hostnames, CORS, etc.
```

## The two stages

```text
 stage1 (assets)                              stage2 (app runtime)
 ├─ Artifact Registry (Docker)                ├─ enable run/sqladmin/secretmanager/compute/dns
 ├─ GCS frontend bucket (SPA website config,  ├─ Cloud SQL Postgres 15 (backups, PITR, insights)
 │  versioning, allUsers objectViewer for     ├─ Cloud Run runtime SA + IAM (roles/cloudsql.client,
 │  the CDN-backed LB)                        │  secretmanager.secretAccessor)
 ├─ enable artifactregistry/storage/iam APIs  ├─ Secret Manager secret + version for the DB password
 │                                            ├─ Cloud Run v2 backend (gen2, cpu_idle,
 │                                            │  startup_cpu_boost, startup probe, CloudSQL socket)
 │                                            ├─ HTTPS LB: global IP + managed SSL + modern SSL
 │                                            │  policy (TLS_1_2+) + quic_override
 │                                            ├─ URL map: default → GCS backend bucket (SPA, CDN,
 │                                            │  compression, negative caching, security headers),
 │                                            │  api host → serverless NEG → Cloud Run backend
 │                                            │  service (logging, HSTS, optional Cloud Armor)
 │                                            ├─ HTTP(:80) forwarding rule → permanent redirect to
 │                                            │  HTTPS on the same global IP
 │                                            └─ Cloud DNS A records: frontend + api → LB IP
 │
 └─ Shell (post-apply, wrapped by `terraform-stage.sh 1`):
    ├─ docker build + push backend (tag = git short SHA, written to .terraform-stage-tag)
    ├─ npm ci + npm run build (VITE_API_BASE_URL defaults to https://<api_host>/api/v2)
    └─ gcloud storage rsync --checksums-only --delete-unmatched-destination-objects dist → bucket
       + best-effort CDN invalidate (skipped silently if the URL map does not exist yet)
```

Stage 2 reads stage 1's AR repo and GCS bucket via **live GCP data sources** (no remote-state
dependency), so each root can have its own local or remote state.

## Create everything

```bash
./terraform-stage.sh 1        # or ./terraform-stage.sh --docker 1
./terraform-stage.sh 2        # or ./terraform-stage.sh --docker 2
```

That is the entire lifecycle. Both stages are safe to rerun at any time:

- Rerunning **stage 1** with no code changes is a plan no-op; the docker push to the same git SHA
  tag is a server-side no-op; `gcloud storage rsync --checksums-only --delete-unmatched-destination-objects`
  only touches changed objects.
- Rerunning **stage 2** with the same `backend_image_tag` is a plan no-op; changing `cors_allowed_origins`,
  `cloud_run_min_instances`, `sql_high_availability`, etc. performs an in-place update.

### Promoting a new backend build

```bash
# from a clean checkout of the new commit
./terraform-stage.sh 1        # builds + pushes a new image under the git SHA, updates the bucket
./terraform-stage.sh 2        # rolls the Cloud Run service to the new image
```

### Skipping the SPA upload

`SKIP_FRONTEND_STATIC=1 ./terraform-stage.sh 1` runs the docker push only (handy when you only
changed backend code).

## DNS

Both `frontend_hostname` and `cloud_run_api_hostname` are **A records** that Terraform creates in
the existing managed zone, both pointing at the same `frontend_lb_ip`. The HTTPS LB does
host-based routing inside the URL map:

- `frontend_hostname` → GCS backend bucket (CDN, Brotli/gzip compression, SPA 404-fallback to
  `index.html`).
- `cloud_run_api_hostname` → serverless NEG → Cloud Run backend service.

Set `manage_cloud_dns_records = false` to manage DNS outside Terraform (the A records are the
only DNS resources this stack owns).

Hostnames must sit under the zone's DNS name. The managed SSL certificate lists both hostnames
and only becomes `ACTIVE` once DNS has propagated; the first apply may need a few minutes.

## HTTP → HTTPS redirect

A second forwarding rule on port 80 uses a dedicated URL map with
`default_url_redirect { https_redirect = true, redirect_response_code = "MOVED_PERMANENTLY_DEFAULT" }`,
so any plaintext request to either hostname is 301'd to HTTPS on the same global IP.

## TLS / security

- [`google_compute_ssl_policy`](stage2/frontend_static.tf) — `MODERN` profile, `TLS_1_2` minimum,
  bound to the HTTPS target proxy.
- HTTPS target proxy has `quic_override = "ENABLE"`.
- SPA (backend bucket) and API (backend service) both emit `Strict-Transport-Security` (two-year
  max-age, `includeSubDomains`, `preload`), `X-Content-Type-Options: nosniff`, and the SPA adds
  `X-Frame-Options: DENY` + `Referrer-Policy: strict-origin-when-cross-origin`.
- API backend service has `log_config { enable = true, sample_rate = 1.0 }` so 100% of LB-level
  requests land in Cloud Logging.

### Optional Cloud Armor (WAF + rate limit)

Set `enable_cloud_armor = true` in `terraform.tfvars` and reapply stage 2. This attaches a
`google_compute_security_policy` to the API backend service with:

- `deny(403)` on the preconfigured OWASP SQLi (`sqli-v33-stable`) and XSS (`xss-v33-stable`)
  expressions.
- `rate_based_ban` (per source IP) at `cloud_armor_rate_limit_rps` requests/minute with a 10
  minute ban; throttled requests get `429`.
- Default `allow` rule.

## Cloud SQL

Production-profile defaults:

- `POSTGRES_15`, `PD_SSD`, `disk_autoresize = true`.
- `backup_configuration { enabled = true, point_in_time_recovery_enabled = true, transaction_log_retention_days = 7, backup_retention_settings { retained_backups = 14 } }`.
- `maintenance_window { day = 7, hour = 4, update_track = "stable" }` (Sunday 04:00 UTC).
- `insights_config { query_insights_enabled = true }`.
- `deletion_protection = true` by default.

Set `sql_high_availability = true` to provision the instance as `REGIONAL` (synchronous
standby in another zone; ~2× cost).

## Cloud Run

- `EXECUTION_ENVIRONMENT_GEN2`, `startup_cpu_boost`, `cpu_idle`, `max_instance_request_concurrency` from `cloud_run_concurrency` (default **80**, same as `terraform-paas-develop.yml` / `CLOUD_RUN_CONCURRENCY`).
- Defaults align with that workflow: **`cloud_run_cpu` = "2"**, **`cloud_run_memory` = "2Gi"**.
- Startup probe: TCP on `:8080`; `cloud_run_startup_probe_*` defaults match the workflow (30s initial delay, 5s period/timeout, 60 failure threshold ≈ long JVM warmup window).
- CloudSQL proxy volume mount at `/cloudsql` (the Spring datasource URL uses the socket factory).
- Image URI is derived — the wrapper passes `-var backend_image_tag=<git SHA>` and Terraform
  builds `${region}-docker.pkg.dev/${project}/${artifact_repo}/${service_name}:${tag}` from the
  stage 1 Artifact Registry data source.

Tune with `cloud_run_min_instances` (1+ to keep a warm instance and eliminate cold starts),
`cloud_run_max_instances`, `cloud_run_cpu`, `cloud_run_memory`, `cloud_run_concurrency`,
`cloud_run_startup_probe_*`, `cloud_run_request_timeout_seconds`.

## Destroy everything

```bash
./terraform-stage.sh --destroy
```

The wrapper destroys **stage 2 first** (it references stage 1's AR repo and bucket), then stage 1.
If the destroy is blocked by:

- **Cloud SQL deletion protection**: set `sql_deletion_protection = false` in
  `terraform.tfvars`, run `./terraform-stage.sh 2` once to apply the change into state, then
  retry `--destroy`.
- **Non-empty frontend bucket**: set `frontend_bucket_force_destroy = true` in
  `terraform.tfvars`, run `./terraform-stage.sh 1` once to apply the change into state, then
  retry `--destroy`.

Terraform removes managed record sets from the Cloud DNS zone; the zone itself is not touched.

## Wrapper environment knobs

All optional, documented at the top of [`terraform-stage.sh`](terraform-stage.sh):

| env                      | stage | effect                                                               |
| ------------------------ | ----- | -------------------------------------------------------------------- |
| `AUTO_APPROVE=1`         | 1,2,destroy | passes `-auto-approve` to terraform apply/destroy              |
| `DOCKER_TERRAFORM_IMAGE` | 1,2,destroy | override image for `--docker` (default `hashicorp/terraform:1.9`) |
| `TAG`                    | 1,2   | backend image tag (default: `git rev-parse --short HEAD`)            |
| `VITE_API_BASE_URL`      | 1     | override Vite base URL (default: `https://<api_host>/api/v2`)        |
| `CORS_ALLOWED_ORIGINS`   | 2     | overrides `cors_allowed_origins` passed to stage 2                   |
| `SKIP_FRONTEND_STATIC=1` | 1     | skip npm build + GCS upload + CDN invalidate (backend image only)    |
| `BACKEND_CONTEXT_DIR`    | 1     | backend Dockerfile dir (default auto-detect)                         |
| `FRONTEND_CONTEXT_DIR`   | 1     | frontend package dir (default auto-detect)                           |

## Docker + Terraform on the same machine

The Terraform container cannot see host ADC unless you mount credentials. The wrapper does this
automatically under `--docker`; if you want to run Terraform manually:

```bash
cd infrastructure/terraform/stage1   # or stage2
docker run --rm -it \
  -v "$PWD/..:/tf:z" -w /tf/stage1 \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/root/adc.json:ro,z" \
  -e GOOGLE_APPLICATION_CREDENTIALS=/root/adc.json \
  hashicorp/terraform:1.9 apply -var-file=../terraform.tfvars
```

## Remote state

For teams, use a GCS backend **per stage**: copy [`backend.tf.example`](backend.tf.example) into
`stage1/` and `stage2/`, pick distinct prefixes (e.g. `terraform/state/stage1`,
`terraform/state/stage2`), create the bucket (versioning + uniform access), and run
`terraform -chdir=stageN init -migrate-state` in each.

## Outputs (for apps and CI)

- Stage 1: `artifact_registry_url`, `artifact_repo`, `frontend_bucket_name`, `project_id`,
  `region`.
- Stage 2: `cloudsql_connection_name`, `run_service_account_email`, `db_name`, `db_user`,
  `db_password_secret_id`, `frontend_bucket_name`, `frontend_lb_ip`, `frontend_url_map_name`,
  `frontend_https_url`, `cloud_run_api_url`, `cloud_run_backend_service_uri`,
  `cloud_run_backend_service_name`, `vite_api_base_url`, `dns_managed_zone_name`,
  `dns_traffic_routing`, `cloud_armor_policy_name`.

## Secrets and rotation

- The DB password lives in **Terraform state** (`random_password`) and in Secret Manager.
  Restrict state access; prefer encrypted remote state.
- To rotate: `terraform -chdir=stage2 taint random_password.db_password && ./terraform-stage.sh 2`
  (expect brief connection failures until Cloud Run rolls to the new secret version).

## Provider lock file

Each stage has its own [`.terraform.lock.hcl`](stage1/) after the first `terraform init`. Commit
both so the project pins provider versions consistently.
