# Getting started — Trip Planner on GKE (ms2, minimal dev)

**Paths:** This guide assumes the **`infrastructure` git repository** is your working tree root (the folder that contains **`ms2/`**). Command examples use **`ms2/docs/gettingstarted`**, **`ms2/terraform/...`**, etc. If you use a larger monorepo where `infrastructure` is nested, prefix those paths with **`infrastructure/`**.

## TL;DR

**Goal:** Tear down everything ms2 in GCP project `milestone2-tbd-cad`, then recreate VPC + GKE + Cloud SQL + trip/social behind the Gateway — **kubectl only**, minimal quota footprint.

1. **One-time:** `gcloud auth login`, `gcloud auth application-default login`, `gcloud config set project milestone2-tbd-cad`, and install tools from [§0](#0-prerequisites) (including `google-cloud-cli-gke-gcloud-auth-plugin`). For ad-hoc `kubectl` outside this script, also `export USE_GKE_GCLOUD_AUTH_PLUGIN=True` (or add it to your shell profile).

2. **Configure secrets:** [`dev-lifecycle.sh`](dev-lifecycle.sh) **loads `.env` from this directory** if the file exists (`set -a` / `set +a`, so all variables are exported).

   ```bash
   cd ms2/docs/gettingstarted
   cp .env.example .env
   # Edit .env: JWT_SECRET must be ≥ 32 characters
   ```

3. **Full reset** (destroys cluster/SQL/VPC in project, then rebuilds and deploys). Defaults when using `dev-lifecycle.sh`: **`AUTO_APPROVE=true`** (Terraform `-auto-approve`) and **`AUTO_CONTINUE=true`** (no “Continue with setup?” after teardown). Set **`AUTO_APPROVE=false`** or **`AUTO_CONTINUE=false`** if you want prompts.

   ```bash
   cd ms2/docs/gettingstarted
   ./dev-lifecycle.sh reset
   ```

   Equivalent without `.env`:  
   `JWT_SECRET='replace-with-your-jwt-secret-min-32-chars!!' ./dev-lifecycle.sh reset`

**What `reset` does:** `teardown` (K8s cleanup → `terraform destroy` with `-auto-approve` by default) → `terraform-apply` (same) → `secrets` → `deploy` (build/push images, `kubectl apply`, bootstrap K8s secrets) → `verify` → Firestore composite index → `gateway-info` → `frontend` (GCS upload). **Quota audit** during teardown/reset is **off** by default; set `RUN_AUDIT=true` to run [§1](#1-audit-quota-usage-optional-before-teardown) first.

**After it finishes:** `post-gateway` waits for the Gateway IP, runs Terraform DNS A records, installs cert-manager, and issues HTTPS certs (default). **Before** `https://api.k8s…` works from your machine: complete [§8a Set nameservers at the registrar](#8a-set-nameservers-at-the-registrar-manual) (one-time). Then `curl -sS "https://api.k8s.tbd-htwg.de/actuator/health/readiness"` and open **`https://k8s.tbd-htwg.de`**. If SSD / persistent-disk quota errors appear, see the **SSD quota** section below.

---

Step-by-step guide for a **single dev environment** in GCP project `milestone2-tbd-cad`: tear down existing ms2 resources, stay within quota limits, then recreate VPC + GKE + Cloud SQL + the trip/social microservices.

**Defaults:** region `europe-west1` · cluster `tripplanning-gke`

> **Canonical automation:** [`dev-lifecycle.sh`](dev-lifecycle.sh) implements §0–§10 below (plus manual [§8a](#8a-set-nameservers-at-the-registrar-manual) at your domain registrar). It exports `USE_GKE_GCLOUD_AUTH_PLUGIN=True`, defaults **`AUTO_APPROVE=true`** and **`AUTO_CONTINUE=true`** (set either to `false` for interactive prompts), and loads **`.env`** from this directory when present. Keep this README and that script in sync when changing steps or flags.

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh help
./dev-lifecycle.sh reset          # full teardown + setup (use AUTO_CONTINUE=false to prompt before setup)
./dev-lifecycle.sh teardown       # §2 only
./dev-lifecycle.sh setup          # §3–§10
```

Lower-level scripts (called by `dev-lifecycle.sh`): [`../../scripts/teardown-dev.sh`](../../scripts/teardown-dev.sh), [`../../scripts/audit-dev-quotas.sh`](../../scripts/audit-dev-quotas.sh), [`../../scripts/install-k8s-dependencies.sh`](../../scripts/install-k8s-dependencies.sh), [`../../scripts/deploy-app-to-gke.sh`](../../scripts/deploy-app-to-gke.sh), [`../../scripts/bootstrap-k8s-secrets.sh`](../../scripts/bootstrap-k8s-secrets.sh).

---

## Minimal dev profile

Designed for a single dev cluster with **~8 vCPUs** of Autopilot capacity (pod **CPU requests** drive node size; see deployments under `gitops/tenants/tripplanning` and `k8s/dependencies`), minimal persistent disk growth.

| Included | Excluded (saves CPU / storage) |
|----------|--------------------------------|
| One GKE Autopilot cluster | Flux GitOps |
| trip-service + social-service + **in-cluster Redis/ES** (1 replica each) | kube-prometheus / Loki / Grafana |
| Cloud SQL `tripplanning` DB only | Extra tenant DBs (`tenant_acme`, …) |
| Firestore `tbd-firestore` | Log export sink → GCS |
| GCS images + frontend buckets | Our GitOps kube-prometheus / Grafana stack (commented out in `gitops/platform`) |
| *(Google default)* | **GKE Managed Prometheus** in `gke-gmp-system` — always on Autopilot ≥1.25, cannot be disabled |
| Gateway API (HTTP + HTTPS via cert-manager) | External Secrets (default path) |
| Secrets via `bootstrap-k8s-secrets.sh` | |

Terraform defaults: [`terraform/envs/dev/terraform.tfvars`](../../terraform/envs/dev/terraform.tfvars) — `tenant_databases = []`, `log_sink.enabled = false`, `manage_firestore_database = false`, `db-g1-small`.

---

## What you will run

| Piece | Technology |
|-------|------------|
| Platform | Terraform → VPC, GKE, Cloud SQL, GCS, Firestore, DNS |
| Trip API | Spring Boot + Cloud SQL Auth Proxy sidecar (`--private-ip`) |
| Social API | Spring Boot + Firestore |
| Ingress | Gateway API HTTPS (`api.k8s.tbd-htwg.de`) — `dev-lifecycle.sh` wires DNS + TLS by default |
| Frontend | Vite build → GCS bucket |

---

<a id="identity-google-manual"></a>

## Identity: Google Cloud (manual — before Sign in with Google)

The SPA uses **Firebase Authentication**; trip-service validates Firebase **ID** tokens and issues an app JWT (`POST /api/v2/auth/google`). None of that is created by Terraform in this repo—you set it up in Google Cloud / Firebase. A fuller write-up (OAuth ↔ Identity Platform, testing mode) is in [progress-reports/4/report_4.md](../../../../progress-reports/4/report_4.md) (**Cloud setup** and **Addendum**).

1. **Project**  
   Use your GCP project (e.g. **`milestone2-tbd-cad`**). Enable **Identity Platform** / add **Firebase** to the project if you have not already.

2. **Firebase auth host**  
   After Firebase is linked, the hosted auth base is typically **`https://<PROJECT_ID>.firebaseapp.com`** (e.g. `https://milestone2-tbd-cad.firebaseapp.com`). You will use this host for the OAuth client below.

3. **OAuth 2.0 client (Web application)** — *Google Cloud Console* → **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID** → type **Web application** (after completing the **OAuth consent screen** if prompted).

   - **Authorized JavaScript origins** (examples; add every UI origin you use):  
     - **`https://<PROJECT_ID>.firebaseapp.com`** (Firebase gate — e.g. `https://milestone2-tbd-cad.firebaseapp.com`)  
     - **`http://localhost:5173`** (and **`http://127.0.0.1:5173`** if you use it) for local Vite  
     - Your deployed site origins (e.g. `https://k8s.tbd-htwg.de`)  
     Wildcards are not allowed; list each origin explicitly.
   - **Authorized redirect URIs**:  
     - **`https://<PROJECT_ID>.firebaseapp.com/__/auth/handler`** — required for the Firebase Auth handler on the same host as above.

4. **Identity Platform provider**  
   In **Identity Platform** (or **Firebase** → **Authentication** → **Sign-in method** → **Google**), register **Google** as a provider and enter this Web client’s **client ID** and **client secret**. Identity Platform needs the same OAuth client you configured in step 3.

5. **Who can sign in (testing)**  
   On the **OAuth consent screen**, while the app is in **Testing**, add accounts under **Test users** (the console may describe this as who is in the app’s audience before production). Without that, only valid test users can complete Google sign-in.

6. **App configuration**  
   - **Frontend:** Firebase Console → **Project settings** → **Your apps** → **Web app** → in the **Firebase SDK snippet** / Web config, copy **`apiKey`**, **`authDomain`**, and **`projectId`** into **`frontend/.env`** as **`VITE_FIREBASE_API_KEY`**, **`VITE_FIREBASE_AUTH_DOMAIN`**, and **`VITE_FIREBASE_PROJECT_ID`** (see [§10](#10-frontend)). These are the **Web SDK** values from Identity Platform / Firebase—**not** the Google Cloud **OAuth 2.0 client**’s client ID or client secret (those belong in the Identity Platform Google provider only).  
   - **Backend:** [`trip-service/configmap.yaml`](../../gitops/tenants/tripplanning/trip-service/configmap.yaml) **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`** must be the **same** GCP/Firebase **`projectId`**.

---

<a id="registrar-dns-manual"></a>

> **Registrar nameservers (one-time):** Point **`tbd-htwg.de`** at Cloud DNS using the four nameservers from Terraform. Full walkthrough: **[§8a Set nameservers at the registrar](#8a-set-nameservers-at-the-registrar-manual)** (after `terraform-apply`, before public `https://api.k8s…` works). Gateway A records and TLS: [§9](#9-gateway-api-dns--tls).

### Other manual steps (not in scripts)

| Item | Where | Notes |
|------|--------|--------|
| **Let’s Encrypt contact** | [`.env`](.env.example) → `ACME_EMAIL` | Used by `cluster-issuer`; optional override of default in GitOps |
| **Firebase authorized domains** | Firebase / Identity Platform → Authentication | Add **`api.k8s.tbd-htwg.de`** (and frontend host, e.g. **`k8s.tbd-htwg.de`**, if you serve the SPA on that host) |
| **OAuth authorized JavaScript origins** | Google Cloud → Credentials → OAuth Web client | Same hosts as above + `http://localhost:5173` — see [Identity](#identity-google-manual) |
| **Frontend / API env** | `frontend/.env`, trip-service ConfigMap | `VITE_API_BASE_URL`, `VITE_FIREBASE_*`, `TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID` |
| **CORS** | [`trip-service/configmap.yaml`](../../gitops/tenants/tripplanning/trip-service/configmap.yaml), social ConfigMap | Include your real `https://…` origins if you change hostnames |
| **JWT / internal secrets** | `.env` → `./dev-lifecycle.sh secrets` | `JWT_SECRET` (≥32 chars) |
| **Cloud Run domain mapping / Google-managed SSL trust** | — | **Not used** on this GKE path (unlike ms1 Cloud Run); TLS is **cert-manager** + Let’s Encrypt |

There is **no** extra “trust domain” or certificate approval step in the GCP load-balancer console for this setup.

Operational detail (Gateway `PROGRAMMED`, curls, troubleshooting): [§9](#9-gateway-api-dns--tls).

---

## 0. Prerequisites

| Tool | Purpose |
|------|---------|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | GCP auth, cluster credentials |
| `google-cloud-cli-gke-gcloud-auth-plugin` | **Required** for `kubectl` on GKE |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Cluster access |
| [Minikube](https://minikube.sigs.k8s.io/docs/start/) | **Local only** — `backend/scripts/local-dev.sh` ([§11](#11-local-development-without-gke)) |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5 | Infrastructure |
| Java 21 + Maven 3.9+ | Backend build |
| Docker | Container images |
| Node.js 20+ | Frontend build |

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project milestone2-tbd-cad
# For kubectl outside dev-lifecycle.sh:
export USE_GKE_GCLOUD_AUTH_PLUGIN=True   # add to ~/.bashrc
```

**Optional — `.env`:** Copy [`.env.example`](.env.example) to `.env` in this directory and set `JWT_SECRET` (≥32 chars). [`dev-lifecycle.sh`](dev-lifecycle.sh) sources `.env` automatically so you do not need to export secrets in the shell for `reset`, `setup`, `deploy`, or `secrets`.

---

## 1. Audit quota usage (optional, before teardown)

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh audit
```

Equivalent: `../../scripts/audit-dev-quotas.sh` from `ms2/`.

**Typical quota drivers:** Autopilot node disks, GKE Managed Prometheus, Flux/cert-manager/ESO pods, log-export GCS bucket.

---

## 2. Teardown (in-project wipe, keep GCP project)

Removes **all** ms2 dev resources inside `milestone2-tbd-cad` (cluster, VPC, SQL, buckets, K8s namespaces). Does **not** delete the GCP project.

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh teardown
```

| Variable | Effect |
|----------|--------|
| `SKIP_K8S=true` | Only `terraform destroy` |
| `SKIP_TF=true` | Only Kubernetes cleanup |
| `AUTO_APPROVE=false` | Prompt for `terraform apply` / `destroy` (default when using `dev-lifecycle.sh` is **`true`** = `-auto-approve`) |
| `AUTO_CONTINUE=false` | After `reset` teardown, prompt before `setup` (default is **`true`**) |

### Quota check (optional)

By default teardown skips the slow project quota API call. To run a full audit before/after teardown:

```bash
RUN_AUDIT=true ./dev-lifecycle.sh teardown
# or
./dev-lifecycle.sh audit
```

---

## 3. Terraform (recreate dev foundation)

```bash
./dev-lifecycle.sh terraform-apply
```

For **interactive** confirmation on plan/apply: `AUTO_APPROVE=false ./dev-lifecycle.sh terraform-apply`

If **409 already exists**:

```bash
cd ms2
./scripts/terraform-import-existing-dev.sh
cd docs/gettingstarted && ./dev-lifecycle.sh terraform-apply
```

**Cloud SQL import** (only if instance exists outside Terraform):

```bash
cd ms2/terraform/envs/dev
terraform import \
  module.cloudsql.google_sql_database_instance.instance \
  projects/milestone2-tbd-cad/instances/tripplanning-dev-pg
```

More detail: [terraform/envs/dev/README.md](../../terraform/envs/dev/README.md)

---

## 4. Secret Manager

```bash
# JWT_SECRET from shell, or from .env when running via dev-lifecycle.sh in this directory
export JWT_SECRET='replace-with-your-jwt-secret-min-32-chars!!'
export INTERNAL_SECRET='replace-internal-secret'   # optional, has default
./dev-lifecycle.sh secrets
```

`tripplanning-db-password` is set by the Cloud SQL module. Set `ES_PASSWORD` before `secrets` if using remote Elasticsearch.

---

## Identity: Google (Firebase / Identity Platform)

**Console setup** (OAuth client, Identity Platform provider, test users): see **[Identity: Google Cloud (manual — before Sign in with Google)](#identity-google-manual)** at the top of this README.

**App wiring:** **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`** in [`trip-service/configmap.yaml`](../../gitops/tenants/tripplanning/trip-service/configmap.yaml) must match your Firebase **`projectId`**. **Frontend:** Firebase Web SDK **`apiKey`** / **`authDomain`** / **`projectId`** as **`VITE_FIREBASE_*`** in **`frontend/.env`** — not the OAuth client id/secret — [§10](#10-frontend).

If **`terraform state`** still lists **`module.identity_platform.*`** from an older Identity Terraform module, **`terraform destroy`** may fail, asking for **`hashicorp/google-beta`**, until those addresses are removed. **`terraform state rm 'module.identity_platform[0].…'`** per address (after Identity is manual-only) drops Terraform tracking; **`teardown-dev.sh`** does this before **`terraform destroy`**. Skip **`state rm`** only when you intentionally reintroduce that module and want Terraform to delete the matching GCP objects.

Course context: [progress-reports/4/report_4.md](../../../../progress-reports/4/report_4.md).

---

## 5. kubectl access

Included in `deploy` / `setup`. Manual check:

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
gcloud container clusters get-credentials tripplanning-gke \
  --region europe-west1 --project milestone2-tbd-cad
kubectl get nodes
```

---

## 6. Deploy application (kubectl only)

```bash
./dev-lifecycle.sh deploy
```

Builds images, pushes to Artifact Registry, installs **in-cluster Redis + Elasticsearch** (`k8s/dependencies`), `kubectl apply -k` tenant manifests, runs `bootstrap-k8s-secrets.sh`. No Flux, cert-manager, or External Secrets. `deploy` sets the GKE kubectl context at the start.

> **Do not use `kubectl apply -k` alone** for trip/social/external-info — that skips **image build/push** and **Artifact Registry IAM** for the Autopilot node SA. Symptom: `ErrImagePull` / `403 Forbidden` on `europe-west1-docker.pkg.dev/...`. Use **`./dev-lifecycle.sh deploy`**.

Shortcut from `ms2/`: `./scripts/deploy-app-to-gke.sh` (same deploy path).

### Search + cache (in-cluster Elasticsearch + Redis)

`deploy` runs [`install-k8s-dependencies.sh`](../../scripts/install-k8s-dependencies.sh) (`kubectl apply -k` [`k8s/dependencies/`](../../k8s/dependencies/)):

- **Redis** — `redis:7-alpine`, Service `redis:6379`; shared cache for trip-service and external-info-service (`SPRING_DATA_REDIS_HOST`); **no PVC**.
- **Elasticsearch** — official `docker.elastic.co/elasticsearch/elasticsearch:8.15.x` single-node (Autopilot-safe, no privileged sysctl); Service `elasticsearch:9200`; **emptyDir** (no PVC — faster scheduling; index rebuilds on pod restart).

App microservices stay **stateless** (no PVCs). See **SSD quota** below for disk budgeting.

After changing the trip-service image or ConfigMap:

```bash
kubectl apply -k ms2/gitops/tenants/tripplanning
kubectl rollout restart deployment/trip-service -n tripplanning
```

**Social trip APIs** (`/api/v2/trips/{id}/community`, etc.) are proxied by trip-service to social-service so the GKE Gateway does not need regex path rules.

### List pods

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
kubectl get pods -n tripplanning
kubectl get pods -A    # all namespaces (system + app)
```

Cloud SQL proxy: `milestone2-tbd-cad:europe-west1:tripplanning-dev-pg` (`--private-ip`; NetworkPolicy allows `10.40.0.0/16:3307`).

### Cluster CPU (Autopilot)

**`tripplanning-gke`** is **GKE Autopilot**: there is no fixed “8 vCPU” node size in Terraform. The console **vCPU** count follows **pod CPU requests** (trip-service, Elasticsearch, Redis, social, etc.). Defaults target **~8 vCPUs** total with system pods. If the cluster still shows ~2 vCPUs, re-apply manifests and wait for new nodes:

```bash
kubectl apply -k ms2/k8s/dependencies
kubectl apply -k ms2/gitops/tenants/tripplanning
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu
```

---

## 7. Verify workloads

```bash
./dev-lifecycle.sh verify
```

Port-forward manually if needed:

```bash
kubectl port-forward -n tripplanning svc/trip-service 8080:8080
curl -s http://127.0.0.1:8080/actuator/health
```

---

## 8. Firestore indexes

```bash
./dev-lifecycle.sh firestore-indexes
```

Next for public hostnames: [§8a Set nameservers at the registrar](#8a-set-nameservers-at-the-registrar-manual), then [§9 Gateway API, DNS & TLS](#9-gateway-api-dns--tls).

---

<a id="set-registrar-nameservers"></a>
<a id="8a-set-nameservers-at-the-registrar-manual"></a>

## 8a. Set nameservers at the registrar (manual)

Public URLs such as **`https://api.k8s.tbd-htwg.de`** need two things outside the cluster: **Cloud DNS** in GCP (Terraform) and **delegation** at the domain registrar. [`dev-lifecycle.sh`](dev-lifecycle.sh) creates **A records** and **HTTPS** in [§9](#9-gateway-api-dns--tls) (`wire-dns`, `setup-tls`); it **cannot** log in to your registrar.

**When to do this:** After **`./dev-lifecycle.sh terraform-apply`** (managed zones exist) and **before** you expect hostnames to resolve — typically **before** or in parallel with **`./dev-lifecycle.sh post-gateway`**. Pods can be healthy while `curl https://api.k8s…` still fails until nameservers and A records are in place.

### 1. Read Cloud DNS nameservers from Terraform

Default layout uses a **parent** zone for **`tbd-htwg.de`**:

```bash
cd ms2/terraform/envs/dev
terraform output parent_dns_zone_name_servers
```

Copy all **four** nameserver hostnames (e.g. `ns-cloud-a1.googledomains.com`, …). They are **project-specific** — not `8.8.8.8` / `8.8.4.4` and not another GCP project’s zone.

Or from gettingstarted:

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh gateway-info   # prints Gateway IP + NS hint after zones exist
```

**Child zone only:** If `enable_parent_dns_zone = false` in [`terraform.tfvars`](../../terraform/envs/dev/terraform.tfvars), use:

```bash
terraform output k8s_subdomain_dns_zone_name_servers
```

### 2. Set nameservers at the registrar

At the provider where you bought **`tbd-htwg.de`** (e.g. INWX, Strato, Cloudflare registrar, Google Domains):

1. Open the domain **`tbd-htwg.de`** → **DNS** or **Nameservers** (wording varies).
2. Choose **Custom nameservers** / **Use external DNS** (not “default parking” DNS).
3. Replace the current list with **exactly the four** Cloud DNS nameservers from step 1.
4. Save. Remove any registrar-side **A / AAAA / CNAME** records you added for `api.k8s…` or `k8s…` — those belong in **Cloud DNS**, not at the registrar.

### 3. What not to configure at the registrar

| At registrar | Handled by |
|--------------|------------|
| **Nameservers** for `tbd-htwg.de` | **You** (this section) |
| **A** record `api.k8s.tbd-htwg.de` → Gateway IP | **`./dev-lifecycle.sh wire-dns`** / **`post-gateway`** (Terraform child zone `k8s.tbd-htwg.de`) |
| **HTTPS / TLS certificate** | **`./dev-lifecycle.sh setup-tls`** / **`post-gateway`** (cert-manager + Let’s Encrypt) |

### 4. Verify delegation

After saving at the registrar (often a few minutes; up to 48h in rare cases):

```bash
dig NS tbd-htwg.de +short
# Should list the four ns-cloud-*.googledomains.com (or similar) from Terraform

dig +short api.k8s.tbd-htwg.de
# Empty until post-gateway creates A records; then should show the Gateway LB IP
```

After **`./dev-lifecycle.sh post-gateway`**:

```bash
dig +short api.k8s.tbd-htwg.de
curl -sS "https://api.k8s.tbd-htwg.de/actuator/health/readiness"
```

### ms1 / another GCP project

Only **one** Cloud DNS zone can be authoritative for **`tbd-htwg.de`**. If ms1 still hosts that zone, either point the registrar NS to **this** project (`milestone2-tbd-cad`) or use a different apex and update Terraform / GitOps hostnames.

### DNS split: who does what

| Item | Who sets it |
|------|-------------|
| Cloud DNS managed zones (parent + child) | **Terraform** (`terraform-apply`) |
| NS delegation `k8s.tbd-htwg.de` → child zone | **Terraform** (when parent zone enabled) |
| **Registrar nameservers** for apex domain | **You** (once) — this section |
| A records `api.k8s`, `social.api.k8s`, `k8s.tbd-htwg.de` → Gateway LB IP | **`wire-dns`** / **`post-gateway`** |
| GKE Gateway + HTTPRoutes | **`deploy`** |
| cert-manager + Let’s Encrypt + HTTPS listeners | **`setup-tls`** / **`post-gateway`** |

Other manual items (Firebase authorized domains, OAuth origins, `.env` secrets): see tables in [Identity](#identity-google-manual) and [§4](#4-secret-manager).

---

## 9. Gateway API, DNS & TLS

`setup` / `reset` run **`post-gateway`** by default: wait for Gateway → Terraform A records (`gke_gateway_ip`) → cert-manager + Let's Encrypt → `gateway-info`. Complete [§8a](#8a-set-nameservers-at-the-registrar-manual) first if hostnames do not resolve yet.

```bash
./dev-lifecycle.sh post-gateway   # wire-dns + setup-tls + gateway-info
./dev-lifecycle.sh gateway-info
kubectl describe gateway tripplanning-api -n tripplanning
kubectl get httproute -n tripplanning -o yaml
```

Disable with `SKIP_GATEWAY_POST=true`, or `SKIP_DNS_WIRE=true` / `SKIP_TLS=true`. Set `ACME_EMAIL` in `.env` for Let's Encrypt.

### Why is `ADDRESS` empty?

The load balancer IP is assigned only when the Gateway is **`PROGRAMMED=True`**. Common causes when it stays **False**:

| Cause | What to do |
|--------|------------|
| HTTPRoute / listener mismatch | HTTPRoutes use `sectionName: http-api` / `http-social` matching the Gateway listeners; `kubectl apply -k` tenant manifests. |
| Unhealthy backends | If **trip-service** is not **Ready** (e.g. Cloud SQL / secrets), GKE may not finish programming. Fix pods first (see below). |

You **cannot** point public DNS at an IP until `status.addresses` is populated. Use **port-forward** or **`kubectl get gateway -o wide`** until then.

### Actuator `DOWN` and Swagger “loading forever”

**Load balancer vs `/actuator/health`:** Probes and the **nominal** Gateway checks use **`/actuator/health/readiness`** (see `gateway/healthcheck-policy.yaml`). That path reflects the **readiness** group only. **`/actuator/health` (no suffix)** aggregates **every** health contributor (disk space, Flyway, etc.). It can return **`"status":"DOWN"`** (often HTTP **503**) while readiness stays **UP** and the LB still shows healthy — compare **`/actuator/health/readiness`** and inspect JSON **details** for the failing contributor.

If **`readiness`** is actually down, that almost always means **trip-service is not ready** (often **database**: proxy, password, or Flyway).

```bash
curl -sS "http://api.k8s.tbd-htwg.de/actuator/health/readiness"
curl -sS "http://api.k8s.tbd-htwg.de/actuator/health"
```

Swagger UI loads **`/v3/api-docs`**; if the app is down, returns errors, or the **load balancer times out** (default backend timeout is short; first OpenAPI build can be slow), the UI never finishes. Tenant manifests set **`GCPBackendPolicy`** (`gateway/gcp-backend-policy.yaml`) with a **120s** timeout on **`trip-service`** / **`social-service`**.

```bash
kubectl get pods -n tripplanning
kubectl describe pod -n tripplanning -l app=trip-service
kubectl logs -n tripplanning deployment/trip-service -c cloud-sql-proxy --tail=80
kubectl logs -n tripplanning deployment/trip-service -c trip-service --tail=80
```

After the pod is **Ready**, re-apply the tenant if you changed Gateway policies (`kubectl apply -k …`), wait a few minutes, then retry Swagger.

### Registrar vs Cloud DNS

See **[§8a Set nameservers at the registrar](#8a-set-nameservers-at-the-registrar-manual)**. Summary: **registrar = custom nameservers only**; **`wire-dns`** creates **`api.k8s`** / **`social.api.k8s`** A records in Cloud DNS; **`setup-tls`** issues HTTPS certs.

```bash
./dev-lifecycle.sh wire-dns    # wait until dig matches Gateway IP
./dev-lifecycle.sh setup-tls   # cert-manager + Let's Encrypt HTTP-01
./dev-lifecycle.sh frontend      # rebuild SPA with https:// API base URL
curl -sS "https://api.k8s.tbd-htwg.de/actuator/health/readiness"
```

If **`setup-tls`** times out, the script prints **Certificate / Challenge** diagnostics. Typical fixes: complete [§8a](#8a-set-nameservers-at-the-registrar-manual), re-run **`wire-dns`**, wait for DNS propagation, then **`setup-tls`** again.

Do **not** enable [`gitops/platform/observability`](../../gitops/platform/observability/) for dev.

### GCS signed image uploads

Trip-service mints browser **PUT** URLs via a dedicated signer SA (`tripplanning-image-url-sig`), configured in Terraform [`app_workload.tf`](../../terraform/envs/dev/app_workload.tf) and **`GCP_IMPERSONATE_SERVICE_ACCOUNT`** on the trip-service ConfigMap. After **`terraform-apply`**, run **`deploy`** so the ConfigMap rolls out. See also [`frontend/doc/image-bucket-cors/README.md`](../../../../frontend/doc/image-bucket-cors/README.md) (project/bucket names differ for ms2: **`milestone2-tbd-cad-images-bucket`**).

---

## 10. Frontend

**Production URL:** **`https://k8s.tbd-htwg.de`** (same Gateway load balancer and TLS certificate as the API). GKE Gateway cannot attach a GCS bucket directly as a backend, so the flow is:

1. **`frontend`** builds the SPA and **`gsutil rsync`** uploads to **`gs://<project>-frontend-bucket`**.
2. The **`frontend`** Deployment (nginx) syncs that bucket on pod start and serves files on port **8080**.
3. **`httproute-frontend.yaml`** routes hostname **`k8s.tbd-htwg.de`** to that Service; **`wire-dns`** creates the apex **A** record; **`setup-tls`** includes **`k8s.tbd-htwg.de`** on the shared certificate.

**Local dev against the GKE API:** from **`frontend/`**, copy [`.env.example`](../../../../frontend/.env.example) to **`.env`**:

- **`VITE_API_BASE_URL=`** (empty) — Vite proxies **`/api/v2`** and **`/api/search`** to **`VITE_DEV_API_PROXY_TARGET`** (default `http://api.k8s.tbd-htwg.de`); avoids browser CORS.
- Or set **`VITE_API_BASE_URL=http://api.k8s.tbd-htwg.de`** for direct calls (requires localhost in service **`CORS_ALLOWED_ORIGINS`**).
- **`VITE_FIREBASE_API_KEY`**, **`VITE_FIREBASE_AUTH_DOMAIN`**, **`VITE_FIREBASE_PROJECT_ID`** — Firebase Web SDK fields (see [Identity](#identity-google-manual)). **`VITE_FIREBASE_PROJECT_ID`** must equal **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`** on trip-service.

```bash
cd frontend
npm install
npm run dev
```

**Deploy to GKE + bucket:** put **`VITE_FIREBASE_*`** in **`ms2/docs/gettingstarted/.env`** (sourced by `dev-lifecycle.sh`), then:

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh frontend
```

This builds with **`VITE_API_BASE_URL`** defaulting to **`https://api.k8s.tbd-htwg.de`**, uploads to GCS, and restarts the **`frontend`** Deployment so nginx picks up new assets. Open **`https://k8s.tbd-htwg.de`**. After changing hostnames, re-run **`./dev-lifecycle.sh setup-tls`** so the certificate includes the frontend SAN.

## Full reset (teardown + setup)

Prefer **`.env`** with `JWT_SECRET` (see **TL;DR**):

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh reset
```

Optional: after **`reset`** teardown, confirm before **`setup`**:

```bash
AUTO_CONTINUE=false ./dev-lifecycle.sh reset
```

Without `.env` (e.g. CI) — defaults already non-interactive:

```bash
JWT_SECRET='your-dev-jwt-secret-min-32-chars!!' ./dev-lifecycle.sh reset
```

Skip optional steps:

```bash
SKIP_FRONTEND=true SKIP_FIRESTORE_INDEXES=true ./dev-lifecycle.sh setup
```

---

## 11. Local development (without GKE)

### Minikube (backend script)

Fast iteration with Kubernetes manifests under `backend/k8s/local` (H2 + in-cluster **Redis/Elasticsearch** via `install-k8s-dependencies.sh` + **gcloud** Firestore emulator + **GCP Identity Platform** for auth, no Cloud SQL). Requires **Minikube** ([§0](#0-prerequisites)); default `MINIKUBE_MEMORY=24576` (24 GiB).

```bash
cd ../../../backend
cp .env.local.example .env.local   # JWT_SECRET ≥ 32 characters
./scripts/local-dev.sh setup
./scripts/local-dev.sh port-forward
```

**GKE deploy:** `dev-lifecycle.sh` switches kubectl to GKE automatically (and calls `local-dev.sh use-gke` if you were on minikube). No manual context step required:

```bash
cd infrastructure/ms2/docs/gettingstarted && ./dev-lifecycle.sh deploy
```

`local-dev.sh` switches to minikube for all its commands except `use-gke`.

### JVM only (no Kubernetes)

| Terminal | Command |
|----------|---------|
| Firestore emulator | `gcloud emulators firestore start --host-port=0.0.0.0:9090` (or use `backend/scripts/local-dev.sh setup`) |
| External-info (:8082) | `mvn -pl tripplanning-external-info-service spring-boot:run` |
| Trip (:8080) | `SPRING_PROFILES_ACTIVE=local TRIPPLANNING_SOCIAL_SERVICE_URL=http://localhost:8081 TRIPPLANNING_EXTERNAL_INFO_SERVICE_URL=http://localhost:8082 mvn -pl tripplanning-trip-service spring-boot:run` |
| Social (:8081) | `SPRING_PROFILES_ACTIVE=local TRIPPLANNING_TRIP_SERVICE_URL=http://localhost:8080 mvn -pl tripplanning-social-service spring-boot:run` |

See [backend/README-GKE.md](../../../backend/README-GKE.md).

---

## `dev-lifecycle.sh` command reference

| Command | README § | Description |
|---------|----------|-------------|
| `audit` | §1 | Quota / resource audit |
| `teardown` | §2 | K8s + Terraform destroy |
| `terraform-apply` | §3 | `terraform init` + `apply` |
| `secrets` | §4 | GSM JWT + internal (+ optional ES) |
| `deploy` | §5–§6 | Build, push, kubectl, bootstrap secrets |
| `verify` | §7 | Health smoke tests |
| `firestore-indexes` | §8 | Composite index |
| *(manual)* | §8a | Registrar nameservers → `terraform output parent_dns_zone_name_servers` |
| `wire-dns` | §9 | Wait for Gateway IP + Terraform A records |
| `setup-tls` | §9 | cert-manager + Let’s Encrypt + HTTPS Gateway |
| `post-gateway` | §9 | `wire-dns` + `setup-tls` + `gateway-info` |
| `gateway-info` | §9 | Gateway IP + registrar hint |
| `frontend` | §10 | npm build + GCS rsync |
| `setup` | §3–§10 | All setup steps (honours `SKIP_*`) |
| `reset` | §2 + §3–§10 | `teardown` → `setup` (audit skipped unless `RUN_AUDIT=true`) |

**Logs:** Each run (except `help`) appends to `logs/dev-lifecycle-YYYYMMDD-HHMMSS.log` and updates `logs/latest.log`. Override with `LIFECYCLE_LOG_FILE` or disable with `NO_LOG=true`.

---

## Checklist

| Step | Command |
|------|---------|
| ☐ Audit quotas | `./dev-lifecycle.sh audit` |
| ☐ Teardown + quota headroom | `./dev-lifecycle.sh teardown` |
| ☐ Terraform applied | `./dev-lifecycle.sh terraform-apply` |
| ☐ GSM secrets | `./dev-lifecycle.sh secrets` (set `JWT_SECRET` in `.env` or export) |
| ☐ App deployed | `./dev-lifecycle.sh deploy` |
| ☐ Pods Running | `./dev-lifecycle.sh verify` |
| ☐ Redis + ES pods Running | `kubectl get pods -n tripplanning` (§6) |
| ☐ Firestore indexes | `./dev-lifecycle.sh firestore-indexes` |
| ☐ **Registrar nameservers** (custom NS at domain provider) | [§8a](#8a-set-nameservers-at-the-registrar-manual) → `terraform output parent_dns_zone_name_servers` |
| ☐ DNS A records + TLS | `./dev-lifecycle.sh post-gateway` (after §8a; or `reset` / `setup`) |
| ☐ Gateway reachable | `./dev-lifecycle.sh gateway-info` |
| ☐ Frontend built + bucket + pod | `./dev-lifecycle.sh frontend` → `https://k8s.tbd-htwg.de` |

---

## Observability: what is actually running?

| Source | On your cluster? | Can disable? |
|--------|------------------|--------------|
| **kube-prometheus-stack / Grafana** (`observability` namespace) | **No** — not in our minimal deploy; GitOps has it commented out | Yes (do not apply `gitops/platform/observability`) |
| **GKE Managed Prometheus** (`gke-gmp-system`, `collector-*` pods) | **Yes** — Autopilot default | **No** (GCP API returns 400 if you try) |
| **Console events** mentioning `kube-prometheus-stack-grafana` | Often **stale** from a cluster before teardown (timestamps like “6 days ago”) | N/A — filter by namespace `tripplanning` or last 1h |

So: you are **not** deploying Grafana via ms2 scripts. The errors you see are either **old event history** or **Google’s built-in** Managed Prometheus collectors (much lighter than a full Grafana stack).

---

## SSD quota (500 GB) — minimize node / disk count

Stay **under 500 GB** project SSD / persistent-disk quota. Two different disk sources:

1. **Autopilot node boot disks** (~**100 GB per node**, not configurable) — grows with **node count**.
2. **Dependency PVCs** — **none** in the minimal profile (Elasticsearch uses **emptyDir**; Redis cache is ephemeral). **App pods have no PVCs** (stateless).

| Component | PVC? |
|-----------|------|
| trip / social / external-info / frontend | No |
| Redis | No |
| Elasticsearch | No (emptyDir; dev only) |

**What we do in the minimal profile:**

| Measure | Purpose |
|---------|---------|
| **1 replica** + `revisionHistoryLimit: 1` | No spare ReplicaSets holding old pods |
| **`strategy: Recreate`** on trip/social | No overlap of old + new pod during image updates |
| **Pod affinity** (`tripplanning.io/colocate`) | Prefer trip, social, Redis, ES on the **same** node |
| **Single-node ES** (official Elastic image, emptyDir) | No dependency PVCs |
| **Sequential rollouts** in `dev-lifecycle.sh deploy` | One extra pod at a time |
| **`install-k8s-dependencies.sh` PVC audit** | Fails deploy if any PVC in `tripplanning` exists (set `MAX_PVC_COUNT` if you add storage) |

You still get **system** disks (`gke-gmp-system`, etc.) and **orphan PDs** after scale-down.

| Problem | What to do |
|---------|------------|
| **Orphan PDs** after teardown / rollouts | `DRY_RUN=false ../../scripts/cleanup-gke-disks.sh` |
| **Leftover Bitnami Helm releases** (legacy) | `helm uninstall redis elasticsearch -n tripplanning`; then `kubectl delete -k ms2/k8s/dependencies` |
| **Before recreate** | `./dev-lifecycle.sh teardown` then delete orphans; `RUN_AUDIT=true ./dev-lifecycle.sh audit` |

```bash
cd ms2
./scripts/cleanup-gke-disks.sh          # DRY_RUN=true (default)
DRY_RUN=false ./scripts/cleanup-gke-disks.sh
./scripts/audit-dev-quotas.sh
```

---

<a id="recovery-after-failed-deploy"></a>

## Recovery after failed deploy

If `deploy` stopped after image push (API timeout, Bitnami `ImagePullBackOff`, or Elasticsearch blocked on Autopilot), resume from `ms2/docs/gettingstarted`:

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
gcloud container clusters get-credentials tripplanning-gke --region europe-west1 --project milestone2-tbd-cad

# Remove legacy Bitnami Helm releases if present
helm uninstall redis elasticsearch -n tripplanning 2>/dev/null || true

NS=tripplanning ../../scripts/install-k8s-dependencies.sh
kubectl apply -k ../../gitops/tenants/tripplanning
GOOGLE_PROJECT=milestone2-tbd-cad ../../scripts/bootstrap-k8s-secrets.sh

kubectl rollout restart deployment/trip-service deployment/external-info-service -n tripplanning
kubectl rollout status deployment/trip-service -n tripplanning --timeout=600s
kubectl get pods -n tripplanning
```

Continue the rest of setup without rebuilding images:

```bash
SKIP_TERRAFORM=true SKIP_SECRETS=true SKIP_DEPLOY=true ./dev-lifecycle.sh setup
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **SSD / PD quota 500 GB** | § SSD quota above; teardown + `cleanup-gke-disks.sh` |
| Gateway **regex** or **HTTP method** match (GWCER104) | PathPrefix only; no `method:` on rules — like mutations proxied via trip-service |
| Setup hangs / trip CrashLoop | Check `kubectl get pods -n tripplanning` (Elasticsearch/Redis ready?); rebuild image + redeploy; or `SKIP_ROLLOUT_WAIT=true ./dev-lifecycle.sh deploy` |
| `externalsecret` resource type not found | Expected — minimal dev uses `bootstrap-k8s-secrets.sh`, not ESO |
| Gateway `PROGRAMMED=False` | Check `describe gateway` for GWCER104 (regex); else wait 5–15 min after fix |
| **`unconditional drop overload`** / **503** via Gateway IP | LB health checks default to **`/`**; use **`HealthCheckPolicy`** on `trip-service` / `social-service` (`gateway/healthcheck-policy.yaml` → `/actuator/health/readiness`, pod ports **8080** / **8081**). `kubectl apply -k` tenant, wait ~2–5 min |
| **Swagger** / **`/v3/api-docs`** **504** Gateway Timeout | Default LB **backend timeout ~30s**; first OpenAPI generation can exceed it. Use **`GCPBackendPolicy`** (`gateway/gcp-backend-policy.yaml`, **120s**); `kubectl apply -k` tenant and retry |
| **`/actuator/health` DOWN** but LB healthy | Compare **`/actuator/health/readiness`**; aggregate endpoint includes extra contributors (see §9); check JSON **details** |
| CPU / PD quota exceeded | `./dev-lifecycle.sh audit` then `teardown` |
| `terraform destroy`: `tripplanning_app` user cannot be dropped | `teardown-dev.sh` deletes Cloud SQL via `gcloud` first; re-run teardown |
| `terraform destroy`: VPC in use by `tripplanning-dev-pg-private-range` | `teardown-dev.sh` deletes peering + global address before `terraform destroy`; re-run teardown |
| `terraform destroy`: Service Networking in use | `gcloud sql instances delete tripplanning-dev-pg --quiet`; `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=tripplanning-vpc`; `terraform destroy` (see `teardown-dev.sh` fallback) |
| **`terraform plan` / `destroy`**: **google-beta** / **Failed to load plugin schemas** / inconsistent lock (beta in config, not in lock) | This stack uses **`hashicorp/google` only**. Beta was only needed for the removed **Identity Platform** module. **Stale state** still tracking that module forces Terraform to load **`google-beta`**. Run **`./dev-lifecycle.sh teardown`** (it drops `module.identity_platform` addresses from state before destroy), or from `terraform/envs/dev`: `terraform init`, then `terraform state list \| grep identity` and **`terraform state rm '<addr>'`** for each stray address (only if those GCP resources are gone or managed manually). |
| `terraform destroy`: log bucket | `gsutil -m rm -r gs://milestone2-tbd-cad-project-logs/**`; buckets use `bucket_force_destroy` on new applies |
| `gke-gcloud-auth-plugin not found` | Install plugin; `export USE_GKE_GCLOUD_AUTH_PLUGIN=True` |
| All pods `Pending` | Wait for Autopilot provisioning |
| `ImagePullBackOff` / `403` on AR | **`./dev-lifecycle.sh deploy`** (not `kubectl apply` only). Node SA needs `roles/artifactregistry.reader` (Terraform `app_workload.tf` + deploy). Then `kubectl rollout restart deployment -n tripplanning trip-service social-service external-info-service` |
| **`setup-tls`**: webhook CA / `unknown authority` on Autopilot | Cainjector cannot use `kube-system` for leader election. Re-run **`./dev-lifecycle.sh setup-tls`** (patches `--leader-election-namespace=cert-manager`). Or check `kubectl logs -n cert-manager deployment/cert-manager-cainjector` for `kube-system` lease denied |
| **`setup-tls`**: `x509: certificate signed by unknown authority` on `webhook.cert-manager.io` | After Autopilot patch above, re-run `./dev-lifecycle.sh setup-tls`; script also injects CA from `cert-manager-webhook-ca` secret if cainjector is slow |
| Trip DB: `PUBLIC` IP error | cloud-sql-proxy needs `--private-ip` |
| Trip DB: `10.40.0.3:3307` timeout | NetworkPolicy: `10.40.0.0/16` TCP 3307 |
| `terraform apply` Firestore 409 | Set `manage_firestore_database = false` in `terraform.tfvars` (DB already exists) |
| `terraform apply` workload SA 404 | Re-run `terraform apply` after fix (SAs created by `project_bootstrap` first) |
| `terraform apply` Managed Prometheus 400 | Cannot disable on Autopilot; ignore — not configurable |
| Trip crashes after DB / ES | Check cloud-sql-proxy; `kubectl logs -n tripplanning deployment/elasticsearch`; wait for ES ready then **rebuild** trip-service image |
| **social-service** timeout from trip-service; ES **sniffer** `Connection refused` | `TRIPPLANNING_SOCIAL_SERVICE_URL` must use **Service port 8080** (not pod **8081**) — `NetworkPolicy` allows 8080/8082. ConfigMap + `allow-egress.yaml` in tenant gitops; `kubectl apply -k` + `kubectl rollout restart deployment/trip-service -n tripplanning` |
| Redis `ImagePullBackOff` / ES Autopilot **privileged sysctl** | Migrate off Bitnami Helm — use `install-k8s-dependencies.sh` (plain manifests). See [Recovery after failed deploy](#recovery-after-failed-deploy) |
| Social Firestore errors | WI + `roles/datastore.user`; database `tbd-firestore` |
| `secret not found` | `./dev-lifecycle.sh secrets` |
| **401** on **`POST /api/v2/auth/google`** / login fails | Firebase Web **`projectId`** (frontend `.env`) must match **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`**; enable Google provider + **authorized domains** (`localhost`, production host). Do not reuse another project’s Web config (e.g. ms1) |
| Gateway HTTPS fails | Run **`wire-dns`** then **`setup-tls`**; registrar NS must delegate to Cloud DNS ([§8a](#8a-set-nameservers-at-the-registrar-manual)); script prints challenge diagnostics on timeout |
| **CORS** on **comments/likes** / **countLikes** from **`npm run dev`** | **social-service** must allow **`http://localhost:5173`** (comments + countLikes hit social directly). Easiest local dev: empty **`VITE_API_BASE_URL`** in **`frontend/.env`** so Vite proxies to GKE (no browser CORS). **`deploy`** rolls out ConfigMaps |
| **CORS** on **comments/likes** while deployed UI is **HTTP** | Add **`http://k8s.tbd-htwg.de`** to **`CORS_ALLOWED_ORIGINS`** on both services; build UI with **`SKIP_TLS=true`** + **`VITE_API_BASE_URL=http://api.k8s.tbd-htwg.de`** |
| **GCS** image **CORS** (profile / trip photos) | **`./dev-lifecycle.sh setup-bucket-cors`** (or **`deploy`**, which runs it) — policy in **`frontend/doc/image-bucket-cors/cors.json`** |
| **Location** insert fails (**`city` NOT NULL**) | Frontend must use **`POST /api/v2/trip-locations`** with **`city`** (geocoding via external-info), not **`POST /locations` with `name`** |
| Image upload: **`signBlob` denied** | **`terraform-apply`** (signer SA + TokenCreator) + **`GCP_IMPERSONATE_SERVICE_ACCOUNT`** on trip-service ConfigMap + **`deploy`** |

---

## Related docs

- [docs/README.md](../README.md)
- [terraform/envs/dev/README.md](../../terraform/envs/dev/README.md)

