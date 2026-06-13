---
description: "Use when: working on ms2 infrastructure or GitOps"
applyTo: "infrastructure/ms2/**"
---

# ms2 plan overview

## Goal
Build a GKE Autopilot-based SaaS platform with GitOps (FluxCD), multi-tenancy, and managed services (Cloud SQL, Secret Manager, Cloud DNS, Cloud Storage).

## Current state
- Terraform: project bootstrap, network, GKE Autopilot, Cloud SQL, storage buckets.
- GitOps: Flux bootstrap done; platform add-ons managed via Kustomize + Helm.

## Decisions
- GKE Autopilot with Kubernetes LoadBalancer Services for tenant entrypoints.
- Cloud SQL private IP; Standard uses database-per-tenant on a shared instance, Enterprise uses instance-per-tenant.
- Free tier: shared namespace + shared DB.
- Standard tier: shared namespace/runtime and database-per-tenant on shared Cloud SQL.
- Enterprise tier: namespace-per-tenant, LoadBalancer-per-tenant, Cloud SQL instance-per-tenant, image bucket-per-tenant, and OpenSearch-per-tenant.
- FluxCD manages cluster state from repo.

## Next steps
1. Wire External Secrets Operator to GCP Secret Manager (ClusterSecretStore).
2. Add tenant templates (namespace, quotas, network policies, LoadBalancer/api-router config).
3. Add app Helm charts and environments for tenants.
4. Define tenant provisioning flow (GitOps-driven, optional API later).

## Repository paths
- Terraform envs: infrastructure/ms2/terraform/envs
- GitOps root: infrastructure/ms2/gitops
- Platform add-ons: infrastructure/ms2/gitops/platform
- Tenant configs: infrastructure/ms2/gitops/tenants
