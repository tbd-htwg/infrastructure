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
- GKE Autopilot, Gateway API.
- Cloud SQL private IP, zonal, no backups in dev.
- Free tier: shared namespace + shared DB.
- Paid tiers: database-per-tenant on same instance (can evolve later).
- FluxCD manages cluster state from repo.

## Next steps
1. Wire External Secrets Operator to GCP Secret Manager (ClusterSecretStore).
2. Add tenant templates (namespace, quotas, network policies, HTTPRoute).
3. Add app Helm charts and environments for tenants.
4. Define tenant provisioning flow (GitOps-driven, optional API later).

## Repository paths
- Terraform envs: infrastructure/ms2/terraform/envs
- GitOps root: infrastructure/ms2/gitops
- Platform add-ons: infrastructure/ms2/gitops/platform
- Tenant configs: infrastructure/ms2/gitops/tenants
