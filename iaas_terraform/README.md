# IaaS Terraform (Compute Engine VM)

This folder provisions the IaaS VM and bootstraps the infrastructure repo to run the Docker Compose stack on the VM.

## What it does

- Creates a VM in the default VPC (zone: europe-west3-c, type: e2-medium).
- Optionally reserves a static external IP and applies tags `http-server` and `https-server`.
- Installs Docker + Compose, clones the repo, writes `.env`, then runs `docker compose pull` and `docker compose up -d`.
- Always deploys the `main` branch by default.
- Creates a Cloud DNS A record for `iaas-tf.tbd-htwg.de.` pointing to the VM IP.
- Reads secrets from Secret Manager using the VM service account.
- Attaches a persistent data disk and mounts it as `/var/lib/docker`.

## Quick start

```bash
cd infrastructure/iaas_terraform
terraform init
terraform apply
```

## Recommended variables to set

- `instance_name`, `zone`, `machine_type` to override the old VM defaults
- `create_static_ip=true` to keep DNS stable
- `manage_dns=false` if you do not want Terraform to manage Cloud DNS

## Notes

- If you already have default firewall rules, keep `create_firewall_rules=false`.
- The startup script pulls `tripplanning-db-password` and `tbd-es-gateway-elastic-password` from Secret Manager.
- The VM service account must have `roles/secretmanager.secretAccessor` and `roles/dns.admin` for DNS-01 certificates.
- OS Login is enabled by default and `metadata_ssh_keys` is empty, so SSH access is not inherited from the old VM.
