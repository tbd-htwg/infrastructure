# Plan: GKE Autopilot SaaS with GitOps

Migrate the app to microservices on GKE Autopilot while keeping managed services (Cloud SQL, Secret Manager, DNS, Storage) outside the cluster, and automate all infra and GitOps via Terraform + FluxCD. Use a shared free tier and database-per-tenant for paid tiers, and enforce isolation with namespaces, Gateway API, and network policies. Define a clear `ms2` folder structure to separate Terraform, FluxCD, Helm charts, and tenant provisioning logic.

## Steps

1. Define `ms2` repo structure for Terraform, FluxCD, Helm charts, and tenant provisioning assets. *blocks all other steps*

2. Terraform bootstrap for new GCP project: enable APIs, create service accounts, IAM bindings, Artifact Registry, Secret Manager, Cloud DNS, logging/monitoring sinks. *depends on step 1*

3. Terraform network + GKE Autopilot: VPC/subnets (if not default), Private Google Access/NAT, GKE Autopilot cluster, Workload Identity, and Gateway API feature enablement. *depends on step 2*

4. Terraform managed services: Cloud SQL instance, shared free-tier DB, per-tenant paid DBs, Cloud Storage buckets, optional KMS for secrets. *depends on step 2*

5. FluxCD bootstrap (automated via Terraform or a post-apply step): install Flux controllers and wire to this repo; define Kustomizations for platform and tenants. *depends on step 3*

6. Platform add-ons via GitOps: Gateway API controller, cert-manager, External Secrets Operator, network policy enforcement, metrics/logging stack. *depends on step 5*

7. Helm chart(s) for microservices: define Deployments, Services, HTTPRoutes, ConfigMaps/Secrets, autoscaling; follow 12-factor (env-driven config, stateless services, logs to stdout). *parallel with step 6 once chart scaffolding exists*

8. Tenant provisioning flow: define GitOps templates (namespace, quotas, NetworkPolicies, Gateway/HTTPRoute, secrets, DB config). Optional provisioning API writes tenant config into Git. *depends on steps 5–7*

9. Tier enforcement: Free vs Standard vs Enterprise mapped to quotas, allowed features, and database isolation; define values overlays. *depends on steps 4, 7, 8*

10. Cutover: run pilot tenant, migrate data, verify routing, then expand tenants and retire old deployment.

## Simple overview (what we’ve used so far)

- **Terraform:** creates cloud resources from code.
- **GCP project bootstrap:** turns on required APIs and creates base IAM + Artifact Registry + Secret Manager + DNS + logs.
- **VPC/Subnet/NAT:** the private network where your cluster runs; NAT gives private nodes outbound internet.
- **GKE Autopilot:** managed Kubernetes; Google runs control plane and nodes.
- **Cloud SQL:** managed Postgres; you don’t run the DB yourself.
- **Cloud Storage:** buckets for assets/images/tfstate.
- **FluxCD:** watches your Git repo and applies Kubernetes manifests automatically.
- **Kustomize:** organizes Kubernetes YAML (like “folders of manifests”).
- **Helm:** installs complex apps (cert-manager, external-secrets, observability stack).

## Add-ons we just added

- **cert-manager:** automatically issues TLS certificates (HTTPS).
- **External Secrets Operator:** syncs secrets from GCP Secret Manager into Kubernetes.
- **NetworkPolicies:** firewall rules inside Kubernetes between pods.
- **Prometheus + Grafana:** metrics collection and dashboards.
- **Loki + Promtail:** log collection and log search.

---

## What’s still coming

- App Helm charts for your microservices.
- Gateway/HTTPRoute resources to expose services.
- ExternalSecrets / SecretStore wiring for GCP Secret Manager.
- Tenant templates + automation (namespaces, quotas, DBs, routes).
- Optional tenant provisioning service (API for sales/dev).

## Goal workflow for adding a tenant (simple view)

### 1) Sales/dev creates a tenant record

Free / Standard / Enterprise is chosen.

### 2) A “tenant config” is added in Git

Example: `infrastructure/ms2/gitops/tenants/tenant-acme/`

- namespace
- quotas
- network policies
- gateway routes
- helm values
- DB name

### 3) Flux detects the Git change

Flux applies it automatically.

### 4) Background work happens

- Namespace created
- Quotas and NetworkPolicies applied
- DB created (for paid tiers)
- Secrets synced from GCP Secret Manager
- Routes created for `acme.k8s.tbd-htwg.de`
- App pods deployed

### 5) Tenant goes live

DNS + Gateway route + workloads are ready.

---

## Free vs Standard vs Enterprise (what changes)

- **Free:** shared namespace + shared DB.
- **Standard:** dedicated namespace + dedicated DB in same Cloud SQL instance.
- **Enterprise:** dedicated namespace (and optionally dedicated DB or separate instance/cluster later).
