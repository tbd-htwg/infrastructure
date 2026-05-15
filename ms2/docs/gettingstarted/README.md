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

**After it finishes:** Point DNS **`api.k8s.tbd-htwg.de`** at the Gateway IP from `./dev-lifecycle.sh gateway-info`, then `curl -sS "http://api.k8s.tbd-htwg.de/actuator/health"`. If SSD / persistent-disk quota errors appear, see the **SSD quota** section below.

---

Step-by-step guide for a **single dev environment** in GCP project `milestone2-tbd-cad`: tear down existing ms2 resources, stay within quota limits, then recreate VPC + GKE + Cloud SQL + the trip/social microservices.

**Defaults:** region `europe-west1` · cluster `tripplanning-gke`

> **Canonical automation:** [`dev-lifecycle.sh`](dev-lifecycle.sh) implements §0–§10 below. It exports `USE_GKE_GCLOUD_AUTH_PLUGIN=True`, defaults **`AUTO_APPROVE=true`** and **`AUTO_CONTINUE=true`** (set either to `false` for interactive prompts), and loads **`.env`** from this directory when present. Keep this README and that script in sync when changing steps or flags.

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh help
./dev-lifecycle.sh reset          # full teardown + setup (use AUTO_CONTINUE=false to prompt before setup)
./dev-lifecycle.sh teardown       # §2 only
./dev-lifecycle.sh setup          # §3–§10
```

Lower-level scripts (called by `dev-lifecycle.sh`): [`../../scripts/teardown-dev.sh`](../../scripts/teardown-dev.sh), [`../../scripts/audit-dev-quotas.sh`](../../scripts/audit-dev-quotas.sh), [`../../scripts/deploy-app-to-gke.sh`](../../scripts/deploy-app-to-gke.sh), [`../../scripts/bootstrap-k8s-secrets.sh`](../../scripts/bootstrap-k8s-secrets.sh).

---

## Minimal dev profile

Designed for tight budget / quota (target **≤16 CPUs** in the cluster, minimal persistent disk growth).

| Included | Excluded (saves CPU / storage) |
|----------|--------------------------------|
| One GKE Autopilot cluster | Flux GitOps |
| trip-service + social-service (1 replica each) | kube-prometheus / Loki / Grafana |
| Cloud SQL `tripplanning` DB only | Extra tenant DBs (`tenant_acme`, …) |
| Firestore `tbd-firestore` | Log export sink → GCS |
| GCS images + frontend buckets | Our GitOps kube-prometheus / Grafana stack (commented out in `gitops/platform`) |
| *(Google default)* | **GKE Managed Prometheus** in `gke-gmp-system` — always on Autopilot ≥1.25, cannot be disabled |
| Gateway API (HTTP) | cert-manager + External Secrets (default path) |
| Secrets via `bootstrap-k8s-secrets.sh` | |

Terraform defaults: [`terraform/envs/dev/terraform.tfvars`](../../terraform/envs/dev/terraform.tfvars) — `tenant_databases = []`, `log_sink.enabled = false`, `manage_firestore_database = false`, `db-g1-small`.

---

## What you will run

| Piece | Technology |
|-------|------------|
| Platform | Terraform → VPC, GKE, Cloud SQL, GCS, Firestore, DNS |
| Trip API | Spring Boot + Cloud SQL Auth Proxy sidecar (`--private-ip`) |
| Social API | Spring Boot + Firestore |
| Ingress | Gateway API HTTP (`api.k8s.tbd-htwg.de`) — HTTPS optional |
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

## 0. Prerequisites

| Tool | Purpose |
|------|---------|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | GCP auth, cluster credentials |
| `google-cloud-cli-gke-gcloud-auth-plugin` | **Required** for `kubectl` on GKE |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Cluster access |
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

If Terraform **previously** managed Firebase/Identity resources, **`terraform plan`** may propose **destroying** them; **`terraform state rm 'module.identity_platform[0].…'`** (per-address) orphans GCP resources if you need to keep them.

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

Builds images, pushes to Artifact Registry, `kubectl apply -k` tenant manifests, runs `bootstrap-k8s-secrets.sh`. No Flux, cert-manager, or External Secrets.

Shortcut from `ms2/`: `./scripts/deploy-app-to-gke.sh` (same deploy path).

### Search (default: in-pod Lucene, no Elasticsearch)

The minimal dev kustomization sets `SPRING_PROFILES_ACTIVE=gke-dev` (see `application-gke-dev.yml`) so trip-service uses **in-pod Lucene** — no Elasticsearch Deployment. That avoids an extra Autopilot node and large boot disks.

Optional: uncomment `elasticsearch/` in [`kustomization.yaml`](../../gitops/tenants/tripplanning/kustomization.yaml) and set `ELASTICSEARCH_HOSTS` in the ConfigMap (costs ~1 node + disk; see **SSD quota** below).

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

---

## 9. Gateway API & DNS (HTTP)

```bash
./dev-lifecycle.sh gateway-info
kubectl describe gateway tripplanning-api -n tripplanning
kubectl get httproute -n tripplanning -o yaml
```

### Why is `ADDRESS` empty?

The load balancer IP is assigned only when the Gateway is **`PROGRAMMED=True`**. Common causes when it stays **False**:

| Cause | What to do |
|--------|------------|
| HTTPRoute / listener mismatch | HTTPRoutes use `sectionName: http-api` / `http-social` matching the Gateway listeners; `kubectl apply -k` tenant manifests. |
| Unhealthy backends | If **trip-service** is not **Ready** (e.g. Cloud SQL / secrets), GKE may not finish programming. Fix pods first (see below). |

You **cannot** point public DNS at an IP until `status.addresses` is populated. Use **port-forward** or **`kubectl get gateway -o wide`** until then.

### Actuator `DOWN` and Swagger “loading forever”

**Load balancer vs `/actuator/health`:** Probes and the **nominal** Gateway checks use **`/actuator/health/readiness`** (see `gateway/healthcheck-policy.yaml`). That path reflects the **readiness** group only. **`/actuator/health` (no suffix)** aggregates **every** health contributor (disk space, Flyway, etc.). It can return **`"status":"DOWN"`** (often HTTP **503**) while readiness stays **UP** and the LB still shows healthy — especially **`diskSpace`** in a container. On the **`gke-dev`** profile, **disk space** health is disabled and **`show-details`** is **always** so one `curl` shows which component failed.

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

### Where to put DNS records

**Option A — only the child zone `k8s.tbd-htwg.de` (simplest):**  
At your registrar, set **nameservers** to the Terraform output **`k8s_subdomain_dns_zone_name_servers`** (child zone only). Then add an **A** record **`api.k8s`** → Gateway IP in that zone (Cloud Console or Terraform `gke_gateway_ip` in [`terraform/envs/dev/terraform.tfvars`](../../terraform/envs/dev/terraform.tfvars)).

**Option B — root zone `tbd-htwg.de` in this project (matches ms1-style root):**  
Set `enable_parent_dns_zone = true` in `terraform.tfvars`. Terraform creates zone **`tbd-htwg.de`** and an **NS** delegation for **`k8s.tbd-htwg.de`** to the child zone. At the **registrar** for `tbd-htwg.de`, use nameservers from **`terraform output parent_dns_zone_name_servers`**.  
Only **one** public delegation can be authoritative for `tbd-htwg.de` — if another project (e.g. ms1) already hosts it, move NS to **this** project or keep a single zone.

**Gateway A records** live in the **child** zone (`api.k8s.tbd-htwg.de.`, `social.api.k8s.tbd-htwg.de.`). After `PROGRAMMED=True`, set:

```bash
IP="$(kubectl get gateway tripplanning-api -n tripplanning -o jsonpath='{.status.addresses[0].value}')"
echo "$IP"
```

Put that value in **`gke_gateway_ip`** in `terraform.tfvars` and run `terraform apply` (or create the A records by hand in the **k8s.tbd-htwg.de** zone).

Then:

```bash
curl -sS "http://api.k8s.tbd-htwg.de/actuator/health"
```

### Optional: HTTPS with cert-manager

1. Install cert-manager and wait for webhook readiness.
2. Add to [`kustomization.yaml`](../../gitops/tenants/tripplanning/kustomization.yaml): `gateway/cluster-issuer.yaml`, `gateway/certificate.yaml`.
3. Restore HTTPS listener on [`gateway/gateway.yaml`](../../gitops/tenants/tripplanning/gateway/gateway.yaml).

Do **not** enable [`gitops/platform/observability`](../../gitops/platform/observability/) for dev.

---

## 10. Frontend

**Local dev against the GKE API:** from your **frontend** repository root (in the course layout this is usually a **sibling** of the `infrastructure` repo, not inside it), copy [`.env.example`](../../../../frontend/.env.example) to **`.env`** and set:


- **`VITE_API_BASE_URL`** — Gateway trip API origin **without** trailing slash (e.g. `http://api.k8s.tbd-htwg.de`). The client appends `/api/v2`.
- **`VITE_FIREBASE_API_KEY`**, **`VITE_FIREBASE_AUTH_DOMAIN`**, **`VITE_FIREBASE_PROJECT_ID`** — from Firebase **Project settings → Your apps → Web app**: the **Web SDK** fields **`apiKey`**, **`authDomain`**, **`projectId`** (same values shown in the Firebase config object / snippet). **Do not** put the Google Cloud **OAuth 2.0 client**’s client ID or client secret here; those are only for the Identity Platform Google provider in the console. **`VITE_FIREBASE_PROJECT_ID`** must equal **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`** on trip-service (see **Identity** above).

Then:

```bash
cd frontend
npm install
npm run dev
```

**GCS deploy via lifecycle:** [`dev-lifecycle.sh`](dev-lifecycle.sh) **`frontend`** runs `npm run build` with **`VITE_API_BASE_URL`** defaulting to `http://api.k8s.tbd-htwg.de`. Put the **`VITE_FIREBASE_*`** variables in **this directory’s `.env`** (the script sources it with `set -a`), so the build picks them up:

```bash
cd ms2/docs/gettingstarted
./dev-lifecycle.sh frontend
```

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

| Terminal | Command |
|----------|---------|
| Firestore emulator | `cd backend && firebase emulators:start --only firestore` |
| Trip (:8080) | `SPRING_PROFILES_ACTIVE=local TRIPPLANNING_SOCIAL_SERVICE_URL=http://localhost:8081 mvn -pl tripplanning-trip-service spring-boot:run` |
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
| `gateway-info` | §9 | Gateway IP + DNS hint |
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
| ☐ Search profile `gke-dev` (no ES pod) | §6 |
| ☐ Firestore indexes | `./dev-lifecycle.sh firestore-indexes` |
| ☐ DNS + Gateway | `./dev-lifecycle.sh gateway-info` |
| ☐ Frontend uploaded | `./dev-lifecycle.sh frontend` |

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

On **GKE Autopilot**, each node has a **persistent boot disk** (often ~100 GB). Quota blows up when **many nodes** exist at once—not because a single disk is huge.

**What we do in the minimal profile:**

| Measure | Purpose |
|---------|---------|
| **1 replica** + `revisionHistoryLimit: 1` | No spare ReplicaSets holding old pods |
| **`strategy: Recreate`** on trip/social | No overlap of old + new pod during image updates |
| **Pod affinity** (`tripplanning.io/colocate`) | Prefer trip + social on the **same** node |
| **No in-cluster Elasticsearch** (default) | Avoids an extra Autopilot node |
| **Sequential rollouts** in `dev-lifecycle.sh deploy` | Restart trip, wait, then social—not both at once |

You still get **system** disks (`gke-gmp-system`, etc.) and **orphan PDs** after scale-down. GKE cannot shrink boot disk size on Autopilot; the lever is **fewer nodes**.

| Problem | What to do |
|---------|------------|
| **Orphan PDs** after teardown / rollouts | `DRY_RUN=false ../../scripts/cleanup-gke-disks.sh` |
| **Leftover elasticsearch** | `kubectl delete deployment elasticsearch -n tripplanning --ignore-not-found` |
| **Before recreate** | `./dev-lifecycle.sh teardown` then delete orphans; `RUN_AUDIT=true ./dev-lifecycle.sh audit` |

```bash
cd ms2
./scripts/cleanup-gke-disks.sh          # DRY_RUN=true (default)
DRY_RUN=false ./scripts/cleanup-gke-disks.sh
./scripts/audit-dev-quotas.sh
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **SSD / PD quota 500 GB** | § SSD quota above; teardown + `cleanup-gke-disks.sh` |
| Gateway **regex** or **HTTP method** match (GWCER104) | PathPrefix only; no `method:` on rules — like mutations proxied via trip-service |
| Setup hangs / trip CrashLoop | Rebuild image + redeploy (`gke-dev` profile avoids external ES); or `SKIP_ROLLOUT_WAIT=true ./dev-lifecycle.sh deploy` |
| `externalsecret` resource type not found | Expected — minimal dev uses `bootstrap-k8s-secrets.sh`, not ESO |
| Gateway `PROGRAMMED=False` | Check `describe gateway` for GWCER104 (regex); else wait 5–15 min after fix |
| **`unconditional drop overload`** / **503** via Gateway IP | LB health checks default to **`/`**; use **`HealthCheckPolicy`** on `trip-service` / `social-service` (`gateway/healthcheck-policy.yaml` → `/actuator/health/readiness`, pod ports **8080** / **8081**). `kubectl apply -k` tenant, wait ~2–5 min |
| **Swagger** / **`/v3/api-docs`** **504** Gateway Timeout | Default LB **backend timeout ~30s**; first OpenAPI generation can exceed it. Use **`GCPBackendPolicy`** (`gateway/gcp-backend-policy.yaml`, **120s**); `kubectl apply -k` tenant and retry |
| **`/actuator/health` DOWN** but LB healthy | Compare **`/actuator/health/readiness`**; aggregate endpoint includes extra contributors (see §9). **`gke-dev`** disables **diskSpace** health noise; check JSON **details** for the real failing indicator |
| CPU / PD quota exceeded | `./dev-lifecycle.sh audit` then `teardown` |
| `terraform destroy`: `tripplanning_app` user cannot be dropped | `teardown-dev.sh` deletes Cloud SQL via `gcloud` first; re-run teardown |
| `terraform destroy`: VPC in use by `tripplanning-dev-pg-private-range` | `teardown-dev.sh` deletes peering + global address before `terraform destroy`; re-run teardown |
| `terraform destroy`: Service Networking in use | `gcloud sql instances delete tripplanning-dev-pg --quiet`; `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=tripplanning-vpc`; `terraform destroy` (see `teardown-dev.sh` fallback) |
| `terraform destroy`: log bucket | `gsutil -m rm -r gs://milestone2-tbd-cad-project-logs/**`; buckets use `bucket_force_destroy` on new applies |
| `gke-gcloud-auth-plugin not found` | Install plugin; `export USE_GKE_GCLOUD_AUTH_PLUGIN=True` |
| All pods `Pending` | Wait for Autopilot provisioning |
| `ImagePullBackOff` / `403` on AR | Re-run `deploy`; node SA needs `artifactregistry.reader` (Terraform + deploy script) |
| Trip DB: `PUBLIC` IP error | cloud-sql-proxy needs `--private-ip` |
| Trip DB: `10.40.0.3:3307` timeout | NetworkPolicy: `10.40.0.0/16` TCP 3307 |
| `terraform apply` Firestore 409 | Set `manage_firestore_database = false` in `terraform.tfvars` (DB already exists) |
| `terraform apply` workload SA 404 | Re-run `terraform apply` after fix (SAs created by `project_bootstrap` first) |
| `terraform apply` Managed Prometheus 400 | Cannot disable on Autopilot; ignore — not configurable |
| Trip crashes after DB | Check cloud-sql-proxy; use default `gke-dev` profile and **rebuild** trip-service image |
| Social Firestore errors | WI + `roles/datastore.user`; database `tbd-firestore` |
| `secret not found` | `./dev-lifecycle.sh secrets` |
| **401** on **`POST /api/v2/auth/google`** / login fails | Firebase Web **`projectId`** (frontend `.env`) must match **`TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID`**; enable Google provider + **authorized domains** (`localhost`, production host). Do not reuse another project’s Web config (e.g. ms1) |
| Gateway HTTPS fails | Use HTTP default or optional cert-manager §9 |

---

## Related docs

- [docs/README.md](../README.md)
- [terraform/envs/dev/README.md](../../terraform/envs/dev/README.md)

