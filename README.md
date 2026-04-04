# Infrastructure

This repo contains the deployment stack for the trip-planning app.

## What This Repo Does

- Runs `frontend`, `backend`, and `caddy` with Docker Compose.
- Exposes only Caddy on ports `80` and `443` in production.
- Routes traffic:
	- `/v1/*`, `/v3/*`, `/swagger-ui/*` -> backend
	- everything else -> frontend

## CI/CD Overview

Application images are built in their own repos and published to GHCR:

1. Push to `main` in `frontend` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/frontend:main`.
2. Push to `main` in `backend` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/backend:main`.
3. Push tag in `caddy-hetzner` -> GitHub Actions builds and pushes `ghcr.io/tbd-htwg/caddy-hetzner:<tag>` and `latest`.
4. This infrastructure repo pulls those images and starts/restarts the stack on the VM.

## Production Usage (VM)

### 1) Configure environment

Copy `.env.example` to `.env` and set values:

```env
CADDY_DOMAIN=yourdomain.com
HETZNER_API_TOKEN=your_hetzner_dns_token
```

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

The frontend uses relative API paths (`/v1/...`) and Vite proxy forwards them to `http://localhost:8080` during local dev.

## Files

- `docker-compose.yml`: production stack using GHCR images
- `Caddyfile`: production reverse-proxy + TLS (Hetzner DNS challenge)
- `docker-compose.local.yml`: local all-in-one stack (builds frontend/backend locally)
- `Caddyfile.local`: local reverse-proxy routing (HTTP only)
