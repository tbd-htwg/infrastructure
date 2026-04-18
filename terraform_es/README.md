# Terraform: Elasticsearch gateway (PaaS)

One **GCE VM** running **Elasticsearch** and **Caddy** only. Caddy terminates TLS (ACME **DNS-01** via Google Cloud DNS) and proxies **`https://<elasticsearch_fqdn>/es/*`** to Elasticsearch on the Docker network. The **`elastic`** user password is generated and stored in **Secret Manager**; use that secret for **stage2** `remote_elasticsearch.password_secret_id` in the main PaaS stack.

IaaS tier VMs do **not** expose Elasticsearch publicly; they keep a local ES container for the Compose stack only.

## Prerequisites

- Use the **same GCP region** as [`../terraform`](../terraform) (PaaS) and the **same region + zone** as [`../terraform_iaas`](../terraform_iaas) GCE VMs (e.g. `europe-west1` / `europe-west1-b`).
- GCP project, billing, **Cloud DNS** managed zone (if `manage_cloud_dns_records = true`).
- **GCP service account JSON** with DNS permissions for the zone (same pattern as `terraform_iaas` Caddy).
- **Terraform** ≥ 1.5 or [`run-terraform-docker.sh`](run-terraform-docker.sh) with ADC:  
  `gcloud auth application-default login`

## Configure and apply

```bash
cd infrastructure/terraform_es
cp terraform.tfvars.example terraform.tfvars
# Edit: project_id, zone, elasticsearch_fqdn, dns_managed_zone_name, gcp_sa_json_file,
# secret_accessor_members (Cloud Run runtime SA), optional ghcr_* / machine_type / es_java_opts.

chmod +x run-terraform-docker.sh
./run-terraform-docker.sh init
./run-terraform-docker.sh plan
./run-terraform-docker.sh apply
```

After the first boot, check **`/var/log/es-bootstrap.log`** on the VM if services are slow to start (Elasticsearch healthcheck can take ~1–2 minutes).

## Wire PaaS (Cloud Run)

Outputs **`elastic_password_secret_id`** and **`remote_elasticsearch_hint`** match **`stage2`** variable **`remote_elasticsearch`**. Grant **`roles/secretmanager.secretAccessor`** on the password secret to the **Cloud Run runtime** service account (use **`secret_accessor_members`** in `terraform.tfvars`).

Example (see also [`../terraform/terraform.tfvars.example`](../terraform/terraform.tfvars.example)):

```hcl
remote_elasticsearch = {
  hosts              = "es.tbd-htwg.de:443"
  password_secret_id = "<output elastic_password_secret_id>"
  protocol           = "https"
  path_prefix        = "/es"
  username           = "elastic"
}
```

## Re-bootstrap

Terraform stores **`es_*`** metadata on the VM. To refresh compose after changing assets:

```bash
sudo gsutil cp gs://<assets_bucket>/bootstrap-compose.sh /tmp/ && sudo bash /tmp/bootstrap-compose.sh
```

Default install directory: **`/opt/es-gateway`**.

## State

Uses a **separate** Terraform state from `terraform_iaas` and `terraform/stage*`. Optionally add a GCS backend in `versions.tf`.
