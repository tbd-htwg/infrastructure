# Terraform Bootstrap (dev)

This environment bootstraps a new GCP project with core APIs, service accounts, IAM bindings, Artifact Registry, Secret Manager, Cloud DNS, a log sink, networking, a GKE Autopilot cluster, Google-managed Cloud Service Mesh, Managed Prometheus, and storage buckets.

Usage:

1. Copy terraform.tfvars.example to terraform.tfvars and edit values.
2. terraform init
3. terraform apply

The cluster is registered in a GKE fleet and the `servicemesh` feature uses
automatic management. Managed Prometheus collection is explicit in the GKE
module; Flux owns the `ClusterPodMonitoring` scrape configuration.

Before a full plan/apply, provide `TF_VAR_platform_github_dispatch_token` if
Terraform should create that Secret Manager version. The public infrastructure
repository does not require `TF_VAR_flux_bootstrap_git_password`.

## Frontend TLS migration

The frontend load balancer uses Certificate Manager DNS authorization and one certificate for `k8s.tbd-htwg.de`, `*.k8s.tbd-htwg.de`, and `*.enterprise.k8s.tbd-htwg.de`. Tenant creation therefore does not modify the certificate.

The canonical HTTPS proxy is `frontend-https-proxy-cm`. This name is retained from the initial Certificate Manager migration so Terraform state and the live `frontend-https-managed-rule` forwarding rule remain aligned. Do not rename it back to the legacy `frontend-https-proxy`; that proxy used the old Compute managed certificate.

The infrastructure Terraform deployer requires `roles/certificatemanager.admin` to create, update, and renew the Certificate Manager resources. This role is managed by `local.infra_terraform_project_roles` and should not be removed while Terraform owns the certificate, DNS authorizations, certificate map, and map entries.

On a first apply, Certificate Manager may report the certificate as
`PROVISIONING` while DNS authorization propagates. The certificate map can be
created immediately; HTTPS becomes ready when the managed certificate reaches
`ACTIVE`.

3. Wait until `frontend-wildcard-cert` is `ACTIVE`. Initial issuance can take time while the DNS authorization CNAMEs propagate.
4. Run a normal full `terraform apply`. The certificate-map entries deliberately reject the switch while the wildcard certificate is not active, preserving the legacy certificate on the HTTPS proxy.
5. Test HTTPS for the base, Standard, and Enterprise host patterns.
6. Delete legacy certificates such as `frontend-cert` or the orphaned `frontend-cert-v3` only after confirming that the HTTPS proxy uses `frontend-certificate-map`. A certificate that is still attached to a proxy cannot be deleted.

`frontend-cert-v3` was a manual zero-downtime rotation setting and is no longer part of the Terraform configuration. If the failed apply created it outside this Terraform state, Terraform cannot remove that orphan automatically.

The tenant provisioning workflow performs the targeted apply, waits up to 30 minutes for `ACTIVE`, and then runs the full apply automatically.
