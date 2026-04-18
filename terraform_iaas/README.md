# Terraform IaaS (tiered GCE + Docker Compose)

This module provisions **one GCE VM per tier** (e.g. small / medium / large), **Cloud DNS** A records like `small-iaas.example.de`, a private **GCS** bucket with your **Docker Compose** stack files, and **Secret Manager** secrets for `.env`, the **GCP service account JSON** (Caddy DNS-01), **per-tier Elasticsearch passwords**, and optionally a **GitHub PAT** for **ghcr.io**.

Each VM runs the same stack as [`../docker-compose.yml`](../docker-compose.yml) (Caddy, frontend, backend, Postgres, Elasticsearch). **Elasticsearch** is **not** exposed on the public hostname; the app uses **`http://elasticsearch:9200`** on the VM with user **`elastic`** and a per-tier password from Secret Manager.

## Prerequisites

- GCP project with billing; **Cloud DNS** managed zone already exists (Terraform only creates A records).
- Local files you will reference from `terraform.tfvars`:
  - **`.env`** – Postgres and app vars (see [`../.env.example`](../.env.example)). Host-specific keys (`CADDY_DOMAIN`, `GCP_PROJECT`, etc.) are **overwritten on the VM** by bootstrap.
  - **GCP SA JSON** – service account that can manage **DNS** for your zone (Caddy ACME DNS-01), e.g. `roles/dns.admin` on the project or zone.
- Optional: **GitHub PAT** file with `read:packages` for private **ghcr.io** images.
- **Terraform** ≥ 1.5 on the host, **or** use [`run-terraform-docker.sh`](run-terraform-docker.sh) with Docker.
- **Application Default Credentials** for Terraform:  
  `gcloud auth application-default login`  
  (or `GOOGLE_APPLICATION_CREDENTIALS` pointing at a key).

## Configure

```bash
cd infrastructure/terraform_iaas
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: project_id, zone, iaas_domain_suffix, dns_managed_zone_name,
# tripplanning_env_file, gcp_sa_json_file, tiers, and optionally ghcr_* / artifact_registry_repository_ids.
```

Paths like `../.env` are resolved relative to this directory; **Docker Terraform** mounts `../` (the `infrastructure/` folder) so those paths work inside the container.

**VM shape (`tiers` → `machine_type`):** the examples use **`e2-standard-1`**, **`e2-standard-2`**, and **`e2-standard-4`** for **1, 2, and 4 vCPUs** (about **4 / 8 / 16 GiB** RAM each). Adjust `es_java_opts` so Elasticsearch fits alongside Postgres and the JVM backend on small tiers.

## Apply (Terraform)

**Local Terraform:**

```bash
terraform init
terraform plan
terraform apply
```

**Docker (no local Terraform binary):**

```bash
chmod +x run-terraform-docker.sh
./run-terraform-docker.sh init
./run-terraform-docker.sh plan
./run-terraform-docker.sh apply
```

Useful outputs:

```bash
terraform output assets_bucket
terraform output tier_hostnames
terraform output compose_bootstrap_hint
```

## Bootstrap on the VM (compose + secrets)

On **first boot**, the GCE **startup script** installs the Google Cloud CLI, downloads **`bootstrap-compose.sh`** from your assets bucket, and runs it. That script installs **Docker** if needed, syncs compose/Caddy from GCS, loads **Secret Manager** secrets into `/opt/tripplanning/.env` and `gcp-sa.json`, optionally **`docker login ghcr.io`**, then runs **`docker compose up -d`**.

If the stack is missing or you changed secrets/assets, **re-run bootstrap** on each VM (SSH or serial console), as **root** or with **sudo**:

```bash
sudo gsutil cp "gs://$(curl -fsS -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/iaas_assets_bucket)/bootstrap-compose.sh" /tmp/
sudo bash /tmp/bootstrap-compose.sh
```

The bucket name is read from instance metadata (`iaas_assets_bucket`), so you do not need to copy it by hand. Alternatively, after `terraform apply`:

```bash
sudo gsutil cp gs://$(terraform output -raw assets_bucket)/bootstrap-compose.sh /tmp/
sudo bash /tmp/bootstrap-compose.sh
```

…run the second line **on the VM**; use `terraform output -raw assets_bucket` **on your laptop** if you paste the bucket name manually.

**Other ways to re-run the full startup path:**

```bash
gcloud compute instances reset INSTANCE_NAME --zone=YOUR_ZONE --project=YOUR_PROJECT_ID
```

Logs on the VM: **`/var/log/iaas-bootstrap.log`**.

## Files and data on the VM after bootstrap

Bootstrap uses **`/opt/tripplanning`** as the Compose project directory (override with `INSTALL_DIR` only if you change the script).

| Location | Purpose |
|----------|---------|
| `/opt/tripplanning/docker-compose.yml` | Stack from GCS |
| `/opt/tripplanning/docker-compose.iaas.yml` | Caddy SA JSON mount |
| `/opt/tripplanning/docker-compose.es.yml` | Generated Elasticsearch heap (`ES_JAVA_OPTS`) |
| `/opt/tripplanning/Caddyfile` | Active Caddy config |
| `/opt/tripplanning/.env` | Compose env (Secret Manager + per-VM lines from bootstrap) |
| `/opt/tripplanning/gcp-sa.json` | DNS-01 service account |
| `/opt/tripplanning/logs/` | **Caddy logs** (host path; mounted as `/var/log/caddy` in the container) |
| `/opt/tripplanning/data/`, `config/`, `static/` | Other Caddy bind mounts |

Bootstrap/install log (not under `/opt/tripplanning`): **`/var/log/iaas-bootstrap.log`**.

**Postgres and Elasticsearch** use **Docker named volumes** (data under **`/var/lib/docker/volumes/`**). The volume name is usually **`tripplanning_postgres_data`** and **`tripplanning_elasticsearch_data`** when the project runs from a directory named `tripplanning`; confirm with:

```bash
docker volume ls
docker compose -f docker-compose.yml -f docker-compose.iaas.yml -f docker-compose.es.yml config --volumes
```

After editing files under `/opt/tripplanning`, apply with:

```bash
cd /opt/tripplanning
sudo docker compose -f docker-compose.yml -f docker-compose.iaas.yml -f docker-compose.es.yml up -d
```

Re-running **`bootstrap-compose.sh`** overwrites the **compose files and Caddyfile** from GCS and rebuilds **`.env`** from Secret Manager; keep durable edits in the repo + `terraform apply`, or only patch on the VM for short-lived experiments.

## Reset Postgres for an empty database (testing)

Use this when you want a **fresh PostgreSQL** data directory on one VM; Flyway will migrate from scratch on the next backend start.

```bash
cd /opt/tripplanning
DC="docker compose -f docker-compose.yml -f docker-compose.iaas.yml -f docker-compose.es.yml"

sudo $DC stop backend postgres
sudo $DC rm -f postgres backend
# Replace VOLUME with the name from: docker volume ls | grep postgres
sudo docker volume rm tripplanning_postgres_data

sudo $DC up -d
```

If your Compose **project name** is not `tripplanning`, the volume may be **`${project}_postgres_data`** (see `docker volume ls`). You can also discover it with:

```bash
docker volume ls -q | grep postgres
```

**Elasticsearch** is unchanged by the steps above; search indexes may still contain old documents. To wipe ES data as well, stop the stack, remove **`tripplanning_elasticsearch_data`** (or the matching `*_elasticsearch_data` volume), then `up -d` again—or use **`docker compose ... down -v`** to drop **all** project volumes (Postgres + Elasticsearch + any unused named volumes in that compose project). That is more destructive; use only when you intend to clear everything.

## Private images (ghcr.io)

In `terraform.tfvars`:

```hcl
ghcr_username     = "your-github-username"
ghcr_token_file   = "../github-pat-ghcr.txt"   # single line PAT, read:packages; do not commit
```

After apply, metadata on each VM includes the Secret Manager id for the token; bootstrap runs **`docker login ghcr.io`** before **`docker compose pull`**.

## Elasticsearch and Caddy

- **IaaS**: only the web app and API are on **`https://<tier>-iaas.<domain>`**; Elasticsearch stays on the Docker network.
- **PaaS / Cloud Run** remote search: use **[`../terraform_es`](../terraform_es)** (dedicated VM with **`/es`** behind Caddy) and stage2 **`remote_elasticsearch`**.

## Troubleshooting

- **`dpkg` / apt lock**: bootstrap waits on real dpkg locks (`fuser`); do not rely on `unattended-upgrade-shutdown` as a signal of “apt busy”.
- **Pull failures**: confirm **ghcr** login or **Artifact Registry** IAM (`artifact_registry_repository_ids`).
- **TLS / DNS**: confirm the SA in Secret Manager can edit **Cloud DNS** for the zone; **`GCP_PROJECT`** on the VM must be the project that holds the zone.
- **Metadata missing** (manual VM): run **`terraform apply`** so instances get **`iaas_*`** metadata keys, then reset or run bootstrap again.

## PaaS (optional)

For Hibernate Search from **Cloud Run**, apply **`../terraform_es`** and wire **`remote_elasticsearch`** in the main PaaS stack to that host and password secret (not the IaaS tier secrets). See [`../terraform/terraform.tfvars.example`](../terraform/terraform.tfvars.example).

## State

This module uses its **own** Terraform state (not stage1/stage2). Optionally configure a **GCS backend** in `versions.tf` (see [`../terraform/backend.tf.example`](../terraform/backend.tf.example)).
