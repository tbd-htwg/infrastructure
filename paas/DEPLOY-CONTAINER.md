# Google Cloud PaaS Deployment (Project-Specific)

This guide adds a parallel deployment path to Google Cloud Run for frontend and backend, with Cloud SQL (PostgreSQL) for backend.

## What This Setup Deploys

- Frontend container -> Cloud Run service (`tripplanning-frontend`)
- Backend container -> Cloud Run service (`tripplanning-backend`)
- PostgreSQL database -> Cloud SQL instance
- Images -> Artifact Registry
- Database password -> Secret Manager

## Prerequisites

- `gcloud` CLI installed and authenticated
- Docker installed locally
- Billing enabled on your Google Cloud project
- A local config file based on `gcp.env.example`

## 1) One-Time Project Setup

1. Copy env template:

```bash
cd infrastructure/paas
cp gcp.env.example gcp.env
```

2. Fill `gcp.env` with your project values and a strong DB password.

3. Run setup script:

```bash
bash setup-gcp-cloudrun.sh
```

This creates/updates:
- required APIs
- Artifact Registry repo
- Cloud SQL Postgres instance + DB + user
- Cloud Run runtime service account
- Secret Manager secret for DB password
- IAM bindings for Cloud SQL and Secret Manager access

## 2) Manual Deploy to Cloud Run

Deploy backend:

```bash
bash deploy-backend-cloudrun.sh
```

Deploy frontend:

```bash
bash deploy-frontend-cloudrun.sh
```

API base strategy on PaaS:
- Frontend image is built with `VITE_API_BASE_URL` (set to your backend public URL, for example `https://api.paas.tbd-htwg.de`).
- This avoids any dependency on VM path routing.

What scripts do:
- `deploy-backend-cloudrun.sh`: builds backend image, pushes to Artifact Registry, deploys backend with Cloud SQL + secret + CORS env
- `deploy-frontend-cloudrun.sh`: builds frontend image with `VITE_API_BASE_URL`, pushes image, deploys frontend service

## 3) Parallel CI/CD Pipeline (GitHub Actions)

Dedicated workflows exist at:
- `backend/.github/workflows/deploy-gcp-cloudrun.yml`
- `frontend/.github/workflows/deploy-gcp-cloudrun.yml`

They run in parallel to your existing GHCR/VM pipelines.

### Required GitHub repository secrets

- `GCP_SA_KEY`: JSON key of a deploy service account

### Required GitHub repository variables

- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GCP_ARTIFACT_REPO`
- `GCP_BACKEND_SERVICE`
- `GCP_FRONTEND_SERVICE`
- `GCP_RUN_SA_EMAIL`
- `GCP_CLOUDSQL_CONNECTION_NAME` (format: `project:region:instance`)
- `GCP_DB_NAME`
- `GCP_DB_USER`
- `GCP_DB_PASSWORD_SECRET` (Secret Manager name)
- `GCP_FRONTEND_API_BASE_URL` (for example `https://api.paas.tbd-htwg.de`)
- `GCP_CORS_ALLOWED_ORIGINS` (for example `https://paas.tbd-htwg.de`)

### Minimum IAM roles for deploy service account

- `roles/run.admin`
- `roles/iam.serviceAccountUser` (on runtime service account)
- `roles/artifactregistry.writer`
- `roles/cloudsql.client`
- `roles/secretmanager.secretAccessor`

## Notes

- Backend config in `backend/src/main/resources/application.yml` reads datasource from environment variables. This is compatible with Cloud Run.
- `caddy-hetzner` is not needed for Cloud Run. Cloud Run handles TLS and custom domain mapping directly.

## Domain Setup: `paas.tbd-htwg.de` and `iaas.tbd-htwg.de`

Yes, this split is possible.

Recommended mapping:
- `paas.tbd-htwg.de` -> Cloud Run frontend service
- `api.paas.tbd-htwg.de` -> Cloud Run backend service
- `iaas.tbd-htwg.de` -> your VM public IP (Caddy on the VM)

Cloud Run domain mapping examples:

```bash
gcloud run domain-mappings create \
	--region=europe-west1 \
	--service=tripplanning-frontend \
	--domain=paas.tbd-htwg.de

gcloud run domain-mappings create \
	--region=europe-west1 \
	--service=tripplanning-backend \
	--domain=api.paas.tbd-htwg.de
```

Then add the DNS records requested by Google Cloud for each mapping.

For IaaS:
- point `iaas.tbd-htwg.de` DNS to your VM IP
- keep current Caddy-based routing there
