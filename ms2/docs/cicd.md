# CI/CD

## Management Summary

There are two relevant deployment pipelines:

- Backend pipeline: builds changed backend service images and updates running
  Kubernetes deployments.
- Frontend pipeline: builds the React application, uploads static files to Cloud
  Storage, and invalidates the load balancer cache.

Both pipelines use GitHub Actions and Google Workload Identity Federation. No
long-lived Google Cloud key file is required in GitHub.

The backend pipeline changes running container images. The frontend pipeline
changes static files in the frontend bucket. Terraform and GitOps are not
normally changed by these two pipelines.

## Backend Pipeline

Source: `backend/.github/workflows/docker-publish-gke.yml`

Triggers:

- Manual `workflow_dispatch`.
- Push to `develop` or `main`.
- Only runs for relevant backend source, Dockerfile, parent POM, shared module,
  service module, seed job, or workflow changes.

Workflow:

1. Detect changed services.
2. Build only the affected Docker images.
3. Push images to GitHub Container Registry.
4. Authenticate to Google Cloud through Workload Identity Federation.
5. Get GKE credentials.
6. Update the relevant Kubernetes deployments with commit SHA image tags.
7. Annotate deployments with deployment metadata.
8. Wait for rollout completion.
9. Refresh `api-router-live-deployment-info` ConfigMaps.

Image tags:

- Every build gets the immutable tag `${GITHUB_SHA}`.
- `develop` branch also updates the `develop` tag.
- `main` branch also updates the `prod` tag.

Deployment behavior:

- `develop` deploys changed runtime services to `tripplanning-free`.
- `main` deploys changed runtime services to `tripplanning-standard` and all
  `tripplanning-ent-*` namespaces.
- `platform-service` is deployed to `tripplanning-system`.
- `customfield-service` is only deployed from `main` when changed, because it is
  an enterprise feature.

This pipeline is intentionally direct: it updates image fields in live
Deployments instead of committing image changes back to GitOps. Flux still owns
the base manifests; the pipeline owns the currently running image revision.

## Frontend Pipeline

Source: `frontend/.github/workflows/deploy-gcp-gke.yml`

Triggers:

- Manual `workflow_dispatch`.
- Push to `main` or `develop`.

Workflow:

1. Install Node.js 20 dependencies with `npm ci`.
2. Authenticate to Google Cloud through Workload Identity Federation.
3. Read browser API keys from Secret Manager.
4. Build the Vite/React frontend.
5. Write `dist/version.json` with branch, commit, repository, run id, and build time.
6. Upload `dist` to Cloud Storage.
7. Set no-cache headers for `index.html` and `version.json`.
8. Publish selected SPA route aliases.
9. Invalidate the Cloud CDN/load balancer cache.

Deployment channels:

- `develop` writes to the `dev` frontend channel.
- `main` writes to the `prod` frontend channel.

The frontend build receives its API base URL, Firebase/Identity Platform
configuration, and Google Maps browser key at build time. The pipeline prevents
the browser from using the tooling-only `api.k8s.tbd-htwg.de` origin and falls
back to same-origin `/api/v2` when needed.

## What Is Updated When?

| Change | Pipeline | Updated artifact | Runtime effect |
| --- | --- | --- | --- |
| Backend service code | Backend | GHCR image and Kubernetes Deployment image | Service rollout in selected namespaces |
| Shared backend module or Dockerfile | Backend | All relevant service images | Multiple service rollouts |
| Platform service code | Backend | Platform image and `tripplanning-system` Deployment | Tenant/admin API rollout |
| Frontend code | Frontend | Cloud Storage frontend files | New SPA version served by load balancer |
| Browser API config secret | Frontend on next run | Built frontend environment | New browser config in static assets |
| Tenant lifecycle | Separate tenant infrastructure workflow | Tenant YAML, Terraform vars, GitOps manifests | Tenant resources created/removed by Terraform and Flux |

## Release Strategy

The effective branch strategy is simple:

- `develop` is the development channel.
- `main` is the production channel for standard and enterprise tenants.

This matches the infrastructure values files: free defaults to development
images, while standard and enterprise use production image tags unless the
pipeline overrides them with a commit SHA.

