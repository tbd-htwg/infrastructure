# Routing

## Management Summary

Routing has two layers:

- Google Cloud routes browser traffic to the frontend bucket or to Kubernetes.
- The Kubernetes `api-router` routes API requests to the correct backend service
  and tenant context.

The important product-level behavior is that tenants are reached by hostnames.
Those hostnames decide the tenant ID, Identity Platform tenant ID, branding, and
backend data context.

## External Routing

The global HTTPS load balancer is created by Terraform module `frontend-lb`.

It handles:

- `https://k8s.tbd-htwg.de` frontend traffic.
- wildcard frontend/tenant certificates for `*.k8s.tbd-htwg.de`.
- wildcard enterprise certificate coverage for `*.enterprise.k8s.tbd-htwg.de`.
- static frontend assets from the Cloud Storage bucket.
- `/api/*` forwarding to the API backend endpoint.

The API backend endpoint points to the regional Kubernetes LoadBalancer address
for the relevant `api-router`.

## Kubernetes LoadBalancers

`api-router` is a Kubernetes Service. Depending on the tier values it is either:

- `ClusterIP` for internal-only cases, or
- `LoadBalancer` with a static regional IP for externally reachable tenant APIs.

Terraform reserves static IPs:

- one standard/default API IP,
- one shared standard tenant API IP,
- one enterprise API IP per enterprise tenant.

Those addresses make DNS and load balancer configuration stable even when
Kubernetes services are recreated.

## API Router

The `api-router` is nginx configured by Helm in
`templates/configmaps/api-router-configmap.yaml`.

It performs three main tasks:

1. Map request hostnames to tenant IDs.
2. Add tenant headers before proxying to services.
3. Route API paths to the correct backend service.

Tenant headers:

- `X-Tenant-ID`
- `X-Identity-Platform-Tenant-ID`

When `enforceKnownHosts` is enabled, unknown hosts receive `404`. This is
enabled for Standard and Enterprise and disabled for Free.

## Path Routing

Important path ownership:

| Path | Target |
| --- | --- |
| `/api/v2/comments` | `social-service` |
| selected trip community/like paths | `social-service` |
| `/api/v2/external` | `external-info-service` |
| `/api/v2/custom-fields` | `customfield-service` when enabled |
| `/api/v2/auth` | `platform-service` |
| `/api/v2/admin` | `platform-service` |
| `/api/v2/tenants` | `platform-service` |
| `/api/v2/platform` | `platform-service` |
| `/api/search` | `trip-service` |
| fallback `/` | `trip-service` |

The router also exposes:

- `/healthz` for load balancer health checks.
- `/api/v2/deployment-info` for live deployment metadata.

## Tenant Host Routing

Standard tenants are listed in the generated standard ConfigMap. Enterprise
tenants are rendered into their own namespace and Helm release. In both cases,
the router receives a list of valid hostnames and Identity Platform tenant IDs.

This means tenant routing changes do not require application code changes. They
require updated tenant definitions and regenerated infrastructure output.

## Frontend Routing

The frontend is a single-page application served from Cloud Storage. The
frontend pipeline uploads `index.html`, assets, `version.json`, and aliases for
known client-side routes. The load balancer's custom behavior covers SPA deep
links.

Browser API calls normally use same-origin `/api/v2`, which avoids cross-origin
CORS issues for the public frontend host.

