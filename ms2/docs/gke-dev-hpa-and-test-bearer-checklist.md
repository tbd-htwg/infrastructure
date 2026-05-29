# GKE dev — HPA + test bearer checklist

Enable CPU-based HPA (1–8 replicas per app service) and the Locust/seeder test bearer on the **free/shared** tenant (`tripplanning-free`).

**Applies to:** trip-service, social-service, external-info-service (not api-router, postgres, valkey, or search).

---

## Prerequisites

- [ ] `kubectl` and `flux` CLI installed
- [ ] Access to GCP project **`tbd-cloudappdev`** and cluster **`tripplanning-gke`**
- [ ] Push rights to **`tbd-htwg/infrastructure`** (`main`)
- [ ] GitHub secret **`TRIPPLANNING_AUTH_TEST_BEARER_TOKEN`** set on backend repo, environment **`gke-dev`**
- [ ] Infra changes merged or ready to push:
  - [values-configmap.yaml](gitops/tenants/free/shared/values-configmap.yaml) — HPA `enabled: true`, `minReplicas: 1`, `maxReplicas: 8`
  - [external-secrets.yaml](gitops/tenants/free/shared/external-secrets.yaml) — `TRIPPLANNING_AUTH_TEST_BEARER_TOKEN` from `tripplanning-auth-test-bearer-token`
  - [terraform env dev main.tf](../terraform/envs/dev/main.tf) — Secret Manager placeholder (optional if sync workflow creates the secret)

---

## Step 0a — Sync sample images to GKE bucket

Required before the first seed-job run (references `sample/…` paths in trip DB). One-time or re-run when `_sample_images/` changes.

```bash
cd backend
./scripts/gke-sync-sample-images.sh
# or: ./scripts/sync-sample-images.sh --target prod
# → gs://tbd-cloudappdev-images-bucket/sample/
```

Requires `gcloud auth application-default login` with access to project `tbd-cloudappdev`.

---

## Step 0b — Seed perf dataset (seed job)

Recommended for the **5000-user / 15000-trip** Locust dataset (direct PostgreSQL + Firestore wipe/seed).

1. Publish seed-job image: GitHub → backend → **Docker GKE services** (workflow_dispatch)
2. Push infrastructure chart (includes `job-seed.yaml`) and Flux reconcile (Steps 1 + 3 below)
3. Run:

```bash
cd backend
./scripts/gke-seed-job.sh --skip-sync --yes   # use --skip-sync if Step 0a already done
```

Copies `performance/seeding_example/perf_seed_manifest.json` locally. **Destructive** on shared dev Postgres + Firestore (`comments`, `likes`).

---

## Step 1 — Push infrastructure GitOps

```bash
cd infrastructure   # or your clone of tbd-htwg/infrastructure
git add ms2/gitops/tenants/free/shared/values-configmap.yaml
git add ms2/gitops/tenants/free/shared/external-secrets.yaml
# include main.tf if terraform placeholder not applied yet
git commit -m "Enable HPA 1-8 and wire test bearer ExternalSecret for gke-dev"
git push origin main
```

---

## Step 2 — Sync test bearer to GCP Secret Manager

**Required.** Pushing the backend repo does **not** update the cluster. The GitHub secret must be copied to GCP Secret Manager first; only then can External Secrets populate `trip-service-secrets`.

Backend workflow copies GitHub secrets → Secret Manager (External Secrets then copies into the cluster).

1. Open **GitHub → backend repo → Actions → “Sync GKE Secret Manager secrets”**
2. **Run workflow** (environment **`gke-dev`**)
3. Confirm the job logs show **`Updated tripplanning-auth-test-bearer-token`** (or **No change** if already synced)

**Save the token value** from your GitHub secret — you need the same string for Locust `PERF_TEST_BEARER`.

---

## Step 3 — Reconcile Flux (coworker commands)

```bash
gcloud container clusters get-credentials tripplanning-gke \
  --region europe-west1 \
  --project tbd-cloudappdev

flux reconcile source git flux-system -n flux-system
flux reconcile kustomization tenants -n flux-system
flux reconcile helmrelease tripplanning-free -n tripplanning-free
```

**Order:** Git source → tenant kustomization (ConfigMap + ExternalSecrets) → Helm release (Deployments + HPAs).

Optional — wait for HelmRelease:

```bash
flux get helmrelease tripplanning-free -n tripplanning-free
```

---

## Step 4 — Refresh trip-service secret (if test bearer was added after Step 3)

External Secrets refresh on an interval; force sync after Secret Manager update:

```bash
kubectl annotate externalsecret trip-service-secrets -n tripplanning-free \
  force-sync=$(date +%s) --overwrite

kubectl rollout restart deployment/trip-service -n tripplanning-free
kubectl rollout status deployment/trip-service -n tripplanning-free
```

---

## Step 5 — Verify HPA

```bash
kubectl get hpa -n tripplanning-free
kubectl describe hpa trip-service -n tripplanning-free
```

Expected:

| HPA | min | max | target |
|-----|-----|-----|--------|
| trip-service | 1 | 8 | CPU ~80% |
| social-service | 1 | 8 | CPU ~80% |
| external-info-service | 1 | 8 | CPU ~80% |

```bash
kubectl get pods -n tripplanning-free -l 'app.kubernetes.io/component in (trip-service,social-service,external-info-service)'
```

---

## Step 6 — Verify test bearer on trip-service

```bash
# Secret key exists in K8s (value is hidden)
kubectl get secret trip-service-secrets -n tripplanning-free -o jsonpath='{.data}' | grep TRIPPLANNING_AUTH_TEST_BEARER_TOKEN

# Quick functional check (replace TOKEN and a real user id from your DB)
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer YOUR_TEST_BEARER_TOKEN" \
  -H "X-Act-As-User: 1" \
  https://k8s.tbd-htwg.de/api/v2/trips?page=0&size=1
```

Expect **200** (not 401).

---

## Locust pending pods (Autopilot)

Cluster **`tripplanning-gke`** is **GKE Autopilot** — Google manages node sizing and placement from pod **requests/limits** and cluster load. Do **not** override Autopilot settings (autoscaling profile, ComputeClasses, etc.).

If trip-service replicas stay **Pending** while HPA scales (`Insufficient cpu/memory` in `kubectl describe pod`), the cluster is out of schedulable capacity — often because **CPU quota** (~16 vCPUs) blocks adding nodes. Tune **Kubernetes only**: HPA min/max, pod requests, or reduce competing replicas during a run. Autopilot will add capacity when quota and scheduling allow.

```bash
kubectl describe pod -n tripplanning-free -l app.kubernetes.io/component=trip-service | grep -A3 Events:
kubectl get hpa -n tripplanning-free
```

---

## Step 7 — Locust

In [performance/.env](../../../performance/.env):

```bash
PERF_TEST_BEARER='<same value as GitHub TRIPPLANNING_AUTH_TEST_BEARER_TOKEN>'
```

Run against the dev API:

```bash
cd performance
set -a && source .env && set +a
locust -f locustfile.py --host=https://k8s.tbd-htwg.de
```

Under load, watch HPA scale up:

```bash
watch kubectl get hpa,pods -n tripplanning-free
```

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| No HPAs | `flux get helmrelease tripplanning-free -n tripplanning-free`; check `autoscaling.enabled: true` in ConfigMap |
| HPA shows 1 pod only | **Normal at low CPU** — HPA min is 1; run Locust and `watch kubectl get hpa -n tripplanning-free` to see scale-up |
| 401 with test bearer | **`SecretSyncedError` on `trip-service-secrets`** → run Step 2 (backend sync workflow); confirm secret exists: `gcloud secrets describe tripplanning-auth-test-bearer-token --project tbd-cloudappdev` |
| Flux not picking up Git | `flux reconcile source git flux-system -n flux-system --with-source` |
| Secret missing in GCP | Re-run backend sync workflow; or `gcloud secrets describe tripplanning-auth-test-bearer-token --project tbd-cloudappdev` |

---

## Roll back HPA

In [values-configmap.yaml](gitops/tenants/free/shared/values-configmap.yaml):

```yaml
autoscaling:
  enabled: false
```

Push → run the three `flux reconcile` commands again. HPAs are removed; deployments stay at chart default replica count (1).
