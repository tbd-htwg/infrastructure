# Terraform Bootstrap (dev)

Creates VPC, GKE Autopilot, Cloud SQL, GCS buckets, DNS zone, IAM, Firestore (optional), and related secrets for **milestone2-tbd-cad** (see `terraform.tfvars`).

**Minimal dev defaults:** single shared DB (`tenant_databases = []`), `db-g1-small`, log sink disabled, `manage_firestore_database = false`, buckets `force_destroy = true` for easier teardown.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # if needed
terraform init
terraform apply
```

## Idempotent apply (resources already exist)

If `terraform apply` fails with **409 already exists**, state is out of sync with GCP. **Do not** delete live resources manually.

```bash
# From this repository root (folder that contains ms2/)
cd ms2
./scripts/terraform-import-existing-dev.sh
cd terraform/envs/dev
terraform plan
terraform apply
```

Full stack lifecycle and **`dev-lifecycle.sh`:** **[docs/gettingstarted/README.md](../../../docs/gettingstarted/README.md)**.

### Optional variables (`terraform.tfvars`)

```hcl
manage_firestore_database = false   # DB exists or Firestore 403
artifact_registry_enabled = false   # repo exists; import via script
```

### Permission errors

| Error | Fix |
|-------|-----|
| Firestore 403 | `roles/datastore.owner` or `manage_firestore_database = false` |

