# Infrastructure as Code

## Management Summary

The infrastructure is split by responsibility:

- Terraform creates durable Google Cloud resources.
- Flux applies Kubernetes and Helm resources from Git.
- Helm describes the application runtime once and changes behavior through tier
  values.
- Tenant YAML files are the source of truth for standard and enterprise tenant
  infrastructure.

This structure is useful because cloud resources and Kubernetes workloads have
different lifecycles. Databases, DNS records, static IPs, buckets, and identity
tenants need controlled Terraform changes. Deployments, ConfigMaps, services,
and tenant Helm releases are better managed continuously by GitOps.

## Repository Structure

Relevant paths:

```text
infrastructure/ms2/
  charts/tripplanning/        Helm chart for backend runtime
  gitops/                     Flux-managed cluster state
  scripts/render-tenants.py   Tenant renderer
  tenants/                    Human-readable tenant definitions
  terraform/envs/dev/         Main Terraform environment
  terraform/modules/          Reusable Terraform modules
```

The YAML organization follows this model:

- Global platform manifests live under `gitops/platform`.
- Cluster-level Flux entry points live under `gitops/clusters/dev`.
- Tenant runtime manifests live under `gitops/tenants`.
- Hand-written tenant inputs live under `tenants/<tier>/<tenant>.yaml`.
- Generated tenant output is committed under Terraform and GitOps paths.

That keeps human-owned inputs separate from generated deployment output.

## Terraform

Main environment: `terraform/envs/dev`.

Main modules:

- `project-bootstrap`: APIs, Secret Manager secrets, IAM bindings, logging sink,
  Firestore setup.
- `network`: VPC, subnet, pod/service secondary ranges.
- `gke-autopilot`: GKE Autopilot cluster.
- `storage`: frontend, image, Terraform state, and enterprise image buckets.
- `frontend-lb`: global HTTPS load balancer, certificates, frontend bucket
  backend, API backend routing.
- `tenant-dns`: tenant DNS records.
- `tenant-cloudsql`: standard and enterprise Cloud SQL resources.
- `github-wif`: GitHub Actions Workload Identity Federation.
- `cloud-service-mesh`: fleet membership and managed service mesh.
- `kms`: optional key management setup.

Terraform is responsible for resources that should not be recreated casually:
databases, buckets, network, load balancer, DNS, service accounts, IAM, identity
configuration, and static IP addresses.

## GitOps and Flux

Flux starts from `gitops/clusters/dev/kustomization.yaml` and reconciles:

- platform bootstrap resources,
- platform configuration,
- platform workloads,
- tenants.

The tenants Flux Kustomization has `prune: true`, so removed generated tenant
resources are cleaned up. It depends on platform workloads so tenant releases
are not applied before shared platform services and operators exist.

External Secrets Operator bridges Google Secret Manager to Kubernetes Secrets.
This keeps secret values out of Git while still letting deployments reference
Kubernetes-native Secrets.

## Helm Chart

The Helm chart `charts/tripplanning` contains:

- deployments,
- services,
- ConfigMaps,
- backing services,
- HPAs,
- deployment info ConfigMaps,
- optional tenant-specific behavior.

The default `values.yaml` defines the common baseline. Tier files override only
the differences:

- `values-free.yaml`: small development/free runtime.
- `values-standard.yaml`: shared paid runtime with HPA and shared backing services.
- `values-enterprise.yaml`: dedicated runtime with enterprise features.

This avoids duplicated manifests and makes tier differences reviewable.

## Tenant Rendering

Tenant source files are stored in:

- `tenants/standard/*.yaml`
- `tenants/enterprise/*.yaml`

`scripts/render-tenants.py` converts those files into:

- `terraform/envs/dev/generated-tenants.auto.tfvars.json`
- `gitops/tenants/standard/shared/generated-tenants-configmap.yaml`
- `gitops/tenants/standard/shared/generated-db-external-secret.yaml`
- `gitops/tenants/enterprise/<tenant>/...`
- `gitops/tenants/enterprise/kustomization.yaml`

The renderer lets platform operations work from compact tenant definitions
instead of editing Terraform variables, Helm values, and Kustomize files by
hand.

## Why This Organization Works

The current setup follows several cloud-native practices:

- Configuration is externalized through values files, ConfigMaps, Secrets, and
  environment variables.
- Runtime services are stateless where possible; persistent state lives in Cloud
  SQL, Firestore, Cloud Storage, OpenSearch, or Valkey.
- Services expose health endpoints and resource requests so Kubernetes can
  schedule, restart, and scale them.
- Credentials are delivered through workload identity and Secret Manager rather
  than static files in the repository.

