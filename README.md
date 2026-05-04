# Infrastructure

This repo contains the deployment stack for the trip-planning app.

## What This Repo Does

- Runs `frontend`, `backend`, `postgres`, and `caddy` with Docker Compose.
- Exposes only Caddy on ports `80` and `443` in production.
- Routes traffic:
	- `/api/v2/*`, `/v3/*`, `/swagger-ui/*` -> backend
	- everything else -> frontend

## CI/CD Overview

Application images are built in their own repos and published to GHCR:

1. Push to `main` in `frontend` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/frontend:main`.
2. Push to `main` in `backend` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/backend:main`.
3. Push tag in `caddy-google` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/caddy-google:<tag>` and `latest`.
4. This infrastructure repo pulls those images and starts/restarts the stack on the VM.

## Production Usage (VM)

### 1) Configure environment

Copy `.env.example` to `.env` and set values:

```env
CADDY_DOMAIN=iaas.tbd-htwg.de
GCP_PROJECT=your-gcp-project-id
GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-sa.json
POSTGRES_DB=tripplanning
POSTGRES_USER=postgres
POSTGRES_PASSWORD=secret
```

Set `GOOGLE_APPLICATION_CREDENTIALS` to the path of a [service account](https://cloud.google.com/iam/docs/service-accounts) JSON key inside the container and mount that file in `docker-compose.yml`, or use another [Google Cloud auth method](https://github.com/libdns/googleclouddns#authenticating) supported by the client library.

### 2) Start or update stack

```bash
docker compose pull
docker compose up -d
```

If GHCR packages are private, log in first:

```bash
echo YOUR_GHCR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

## Local Development

Two simple options are available.

### Option A: Full local stack with one compose file

This mimics production routing with local builds.
It also starts a local Postgres container used by the backend.
Database credentials for local compose are read from `.env` in this folder.

```bash
docker compose -f docker-compose.local.yml up --build
```

Open: `http://localhost:8080`

Stop:

```bash
docker compose -f docker-compose.local.yml down
```

### Option B: Frontend hot-reload + local backend

Run backend:

```bash
cd ../backend
mvn spring-boot:run
```

Run frontend (Vite):

```bash
cd ../frontend
npm install
npm run dev
```

Open: `http://localhost:5173`

The frontend uses relative API paths (`/api/v2/...`) and Vite proxy forwards them to `http://localhost:8080` during local dev.

## Files

- `docker-compose.yml`: production stack using GHCR images
- `Caddyfile`: production reverse-proxy + TLS (Google Cloud DNS challenge)
- `docker-compose.local.yml`: local all-in-one stack (builds frontend/backend locally + runs Postgres)
- `Caddyfile.local`: local reverse-proxy routing (HTTP only)

## Terraform IaaS

The Terraform IaaS setup lives in `infrastructure/iaas_terraform` and provisions a Compute Engine VM for the full Docker Compose stack. It attaches a persistent data disk for Docker state, sets up DNS for `iaas-tf.tbd-htwg.de`, pulls secrets from Secret Manager, and runs the production compose file from the `main` branch at boot.
