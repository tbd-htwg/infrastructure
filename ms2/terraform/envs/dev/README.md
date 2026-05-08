# Terraform Bootstrap (dev)

This environment bootstraps a new GCP project with core APIs, service accounts, IAM bindings, Artifact Registry, Secret Manager, Cloud DNS, and a log sink.

Usage:

1. Copy terraform.tfvars.example to terraform.tfvars and edit values.
2. terraform init
3. terraform apply
