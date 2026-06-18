#!/usr/bin/env python3
"""Render tenant YAML definitions into Terraform and GitOps inputs."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover - dependency guard for local use
    raise SystemExit("PyYAML is required: python3 -m pip install pyyaml") from exc


ROOT = Path(__file__).resolve().parents[1]
TENANTS_DIR = ROOT / "tenants"
TERRAFORM_OUT = ROOT / "terraform/envs/dev/generated-tenants.auto.tfvars.json"
STANDARD_GITOPS_OUT = ROOT / "gitops/tenants/standard/shared/generated-tenants-configmap.yaml"
STANDARD_DB_SECRET_OUT = ROOT / "gitops/tenants/standard/shared/generated-db-external-secret.yaml"
ENTERPRISE_GITOPS_DIR = ROOT / "gitops/tenants/enterprise"


def load_tenants(tier: str) -> dict[str, dict[str, Any]]:
    tenants: dict[str, dict[str, Any]] = {}
    tier_dir = TENANTS_DIR / tier
    if not tier_dir.exists():
        return tenants

    for path in sorted(tier_dir.glob("*.yaml")):
        if path.name.startswith("example-"):
            continue
        with path.open("r", encoding="utf-8") as handle:
            tenant = yaml.safe_load(handle) or {}
        tenant_id = tenant.get("tenantId")
        if not tenant_id:
            raise ValueError(f"{path} is missing tenantId")
        if tenant.get("tier") != tier:
            raise ValueError(f"{path} must set tier: {tier}")
        tenants[tenant_id] = tenant
    return tenants


def identity_platform_config(tenant: dict[str, Any]) -> dict[str, Any]:
    identity = tenant["identityPlatform"]
    return {
        "display_name": identity["displayName"],
        "tenant_id": identity.get("tenantId"),
        "email_password_enabled": identity.get("emailPasswordEnabled", True),
        "email_link_signin": identity.get("emailLinkSignin", False),
        "mfa_enabled": identity.get("mfaEnabled", False),
        "auth_disabled": identity.get("authDisabled", False),
    }


def render_standard_tfvars(tenants: dict[str, dict[str, Any]]) -> dict[str, Any]:
    rendered: dict[str, Any] = {}
    for tenant_id, tenant in tenants.items():
        rendered[tenant_id] = {
            "hostnames": tenant["hostnames"],
            "identity_platform": identity_platform_config(tenant),
            "database": {
                "name": tenant["database"]["databaseName"],
                "user_name": tenant["database"].get("userName", "tripplanning_app"),
            },
            "frontend": {
                "bucket_prefix": tenant["frontend"]["bucketPrefix"],
                "brand_name": tenant["frontend"]["brandName"],
                "color_scheme": tenant["frontend"]["colorScheme"],
                "brand_icon": tenant["frontend"]["brandIcon"],
            },
            "storage": {
                "images_prefix": tenant["storage"]["imagesPrefix"],
            },
            "search": {
                "index_name": tenant["search"]["indexName"],
            },
            "cache": {
                "key_prefix": tenant["cache"]["keyPrefix"],
            },
        }
    return rendered


def render_enterprise_tfvars(tenants: dict[str, dict[str, Any]]) -> dict[str, Any]:
    rendered: dict[str, Any] = {}
    for tenant_id, tenant in tenants.items():
        rendered[tenant_id] = {
            "namespace": tenant["namespace"],
            "hostnames": tenant["hostnames"],
            "identity_platform": identity_platform_config(tenant),
            "database": {
                "instance_name": tenant["database"]["cloudSqlInstance"],
                "name": tenant["database"].get("databaseName", "tripplanning"),
                "user_name": tenant["database"].get("userName", "tripplanning_app"),
            },
            "frontend": {
                "bucket_prefix": tenant["frontend"]["bucketPrefix"],
                "brand_name": tenant["frontend"]["brandName"],
                "color_scheme": tenant["frontend"]["colorScheme"],
                "brand_icon": tenant["frontend"]["brandIcon"],
            },
            "storage": {
                "image_bucket_name": tenant["storage"]["imageBucketName"],
            },
            "search": {
                "release_name": tenant["search"]["releaseName"],
            },
            "cache": {
                "dedicated": tenant.get("cache", {}).get("dedicated", True),
            },
        }
    return rendered


def identity_tenant_id(
    tier: str,
    tenant_id: str,
    tenant: dict[str, Any],
    terraform_outputs: dict[str, Any],
) -> str:
    output = terraform_outputs.get("identity_platform_tenant_ids", {}).get("value", {})
    computed = output.get(tier, {}).get(tenant_id)
    return computed or tenant["identityPlatform"].get("tenantId", tenant_id)


def cloudsql_connection_name(
    tier: str,
    tenant_id: str,
    terraform_outputs: dict[str, Any],
) -> str:
    output_name = "enterprise_cloudsql" if tier == "enterprise" else "standard_cloudsql"
    output = terraform_outputs.get(output_name, {}).get("value")
    if tier == "enterprise":
        return (output or {}).get(tenant_id, {}).get("connection_name", "")
    return (output or {}).get("connection_name", "")


def load_balancer_ip(tier: str, tenant_id: str, terraform_outputs: dict[str, Any]) -> str:
    if tier == "enterprise":
        return terraform_outputs.get("enterprise_load_balancer_ips", {}).get("value", {}).get(tenant_id, "")
    return terraform_outputs.get("standard_load_balancer_ip", {}).get("value", "")


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def render_standard_configmap(
    tenants: dict[str, dict[str, Any]],
    terraform_outputs: dict[str, Any],
) -> str:
    router_tenants = []
    cors_origins = ",".join(
        ["https://k8s.tbd-htwg.de"]
        + [
            f"https://{hostname}"
            for tenant in tenants.values()
            for hostname in tenant["hostnames"]
        ]
    )
    for tenant_id, tenant in tenants.items():
        router_tenants.append(
            {
                "tenantId": tenant_id,
                "identityPlatformTenantId": identity_tenant_id("standard", tenant_id, tenant, terraform_outputs),
                "hostnames": tenant["hostnames"],
            }
        )

    primary_tenant_id = next(iter(tenants), None)
    primary_tenant = tenants[primary_tenant_id] if primary_tenant_id else None

    values = {
        "apiRouter": {
            "tenants": router_tenants,
            "loadBalancer": {
                "ip": load_balancer_ip("standard", "standard", terraform_outputs),
            },
        }
    }
    if not primary_tenant:
        values["services"] = {
            "trip": {
                "replicas": 0,
            }
        }
    if primary_tenant_id and primary_tenant:
        values["global"] = {
            "cloudSql": {
                "enabled": True,
                "connectionName": cloudsql_connection_name("standard", primary_tenant_id, terraform_outputs),
                "databaseName": primary_tenant["database"]["databaseName"],
                "userName": primary_tenant["database"].get("userName", "tripplanning_app"),
            }
        }
        values["services"] = {
            "trip": {
                "secretRefs": [
                    "trip-service-secrets",
                    "trip-service-db-secrets",
                ],
                "env": {
                    "CORS_ALLOWED_ORIGINS": cors_origins,
                    "TRIPPLANNING_TENANT_DATASOURCE_ROUTING": "false",
                    "TRIPPLANNING_PLATFORM_BASE_URL": "http://platform-service.tripplanning-system:8083",
                }
            }
        }
        values["services"]["social"] = {
            "env": {
                "CORS_ALLOWED_ORIGINS": cors_origins,
            }
        }
        values["services"]["externalInfo"] = {
            "env": {
                "CORS_ALLOWED_ORIGINS": cors_origins,
            }
        }

    values_yaml = yaml.safe_dump(values, sort_keys=False)
    indented = "\n".join(f"    {line}" if line else "" for line in values_yaml.splitlines())
    return f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: tripplanning-standard-generated-tenants
  namespace: tripplanning-standard
data:
  values.yaml: |
{indented}
"""


def render_standard_db_external_secret(tenants: dict[str, dict[str, Any]]) -> str:
    primary_tenant_id = next(iter(tenants), None)
    if not primary_tenant_id:
        data = "  data: []"
    else:
        data = f"""  data:
    - secretKey: SPRING_DATASOURCE_PASSWORD
      remoteRef:
        key: tripplanning-standard-{primary_tenant_id}-db-password"""

    return f"""apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: trip-service-db-secrets
  namespace: tripplanning-standard
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: trip-service-db-secrets
    creationPolicy: Owner
{data}
"""


def render_enterprise_values(
    tenant_id: str,
    tenant: dict[str, Any],
    terraform_outputs: dict[str, Any],
) -> str:
    project_id = tenant.get("projectId", "tbd-cloudappdev")
    frontend_bucket_name = tenant["frontend"].get("bucketName", f"{project_id}-frontend-bucket")
    cors_origins = ",".join(f"https://{hostname}" for hostname in tenant["hostnames"])
    services = tenant.get("services", {})
    service_defaults = {
        "trip": {
            "env": {
                "CORS_ALLOWED_ORIGINS": cors_origins,
                "TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID": project_id,
                "GCP_IMPERSONATE_SERVICE_ACCOUNT": f"tripplanning-image-url-sig@{project_id}.iam.gserviceaccount.com",
                "TRIPPLANNING_PLATFORM_BASE_URL": "http://platform-service.tripplanning-system:8083",
            },
            "bootstrap": {
                "waitForValkey": True,
                "waitForSearch": True,
            },
        },
        "social": {
            "env": {
                "CORS_ALLOWED_ORIGINS": cors_origins,
                "TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID": project_id,
                "SPRING_DATA_REDIS_HOST": "valkey",
            },
            "bootstrap": {
                "waitForValkey": True,
            },
        },
        "externalInfo": {
            "env": {
                "CORS_ALLOWED_ORIGINS": cors_origins,
                "SPRING_DATA_REDIS_HOST": "valkey",
            },
            "bootstrap": {
                "waitForValkey": True,
            },
        },
    }
    merged_services = deep_merge(service_defaults, services)
    values = {
        "global": {
            "tier": "enterprise",
            "tenantId": tenant_id,
            "hostnames": list(tenant["hostnames"]),
            "identityPlatform": {
                "tenantId": identity_tenant_id("enterprise", tenant_id, tenant, terraform_outputs),
            },
            "frontend": {
                "bucketName": frontend_bucket_name,
                "bucketPrefix": tenant["frontend"]["bucketPrefix"],
                "brandName": tenant["frontend"]["brandName"],
                "colorScheme": tenant["frontend"]["colorScheme"],
                "brandIcon": tenant["frontend"]["brandIcon"],
            },
            "storage": {
                "imagesBucketName": tenant["storage"]["imageBucketName"],
                "imagesPrefix": "",
            },
            "search": {
                "indexName": f"tripentity-{tenant_id}",
            },
            "cache": {
                "keyPrefix": f"ent:{tenant_id}",
            },
            "cloudSql": {
                "enabled": True,
                "connectionName": cloudsql_connection_name("enterprise", tenant_id, terraform_outputs),
                "databaseName": tenant["database"].get("databaseName", "tripplanning"),
                "userName": tenant["database"].get("userName", "tripplanning_app"),
            },
            "imagePullSecrets": ["ghcr-pull"],
        },
        "apiRouter": {
            "mode": "enterprise",
            "enforceKnownHosts": True,
            "tenants": [
                {
                    "tenantId": tenant_id,
                    "identityPlatformTenantId": identity_tenant_id("enterprise", tenant_id, tenant, terraform_outputs),
                    "hostnames": list(tenant["hostnames"]),
                }
            ],
            "loadBalancer": {
                "enabled": True,
                "ip": load_balancer_ip("enterprise", tenant_id, terraform_outputs),
                "externalTrafficPolicy": "Cluster",
            },
        },
        "services": merged_services,
        "backingServices": {
            "postgres": {"enabled": False},
            "elasticsearch": {
                "enabled": True,
                "serviceName": tenant["search"]["releaseName"],
            },
            "valkey": {"enabled": tenant.get("cache", {}).get("dedicated", True)},
        },
    }
    return yaml.safe_dump(values, sort_keys=False)


def render_enterprise_gitops(
    tenants: dict[str, dict[str, Any]],
    terraform_outputs: dict[str, Any],
    check: bool,
) -> None:
    desired_tenant_ids = set(tenants)
    if not check and ENTERPRISE_GITOPS_DIR.exists():
        for path in ENTERPRISE_GITOPS_DIR.iterdir():
            if path.is_dir() and path.name not in desired_tenant_ids:
                shutil.rmtree(path)

    resources: list[str] = []
    for tenant_id, tenant in tenants.items():
        project_id = tenant.get("projectId", "tbd-cloudappdev")
        tenant_dir = ENTERPRISE_GITOPS_DIR / tenant_id
        resources.append(tenant_id)
        files = {
            "namespace.yaml": f"""apiVersion: v1
kind: Namespace
metadata:
  name: {tenant["namespace"]}
  labels:
    app.kubernetes.io/name: tripplanning
    tier: enterprise
    tenant_id: {tenant_id}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tripplanning-enterprise-quota
  namespace: {tenant["namespace"]}
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "48"
    limits.memory: 64Gi
    pods: "80"
    persistentvolumeclaims: "10"
""",
            "serviceaccount-default.yaml": f"""apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: {tenant["namespace"]}
  annotations:
    iam.gke.io/gcp-service-account: workload@{project_id}.iam.gserviceaccount.com
""",
            "external-secrets.yaml": f"""apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ghcr-pull
  namespace: {tenant["namespace"]}
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: ghcr-pull
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: '{{{{ .dockerconfigjson }}}}'
  data:
    - secretKey: dockerconfigjson
      remoteRef:
        key: tripplanning-ghcr-pull-dockerconfigjson
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: trip-service-secrets
  namespace: {tenant["namespace"]}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: trip-service-secrets
  data:
    - secretKey: SPRING_DATASOURCE_PASSWORD
      remoteRef:
        key: tripplanning-enterprise-{tenant_id}-db-password
    - secretKey: TRIPPLANNING_AUTH_JWT_SECRET
      remoteRef:
        key: tripplanning-jwt-secret
    - secretKey: TRIPPLANNING_INTERNAL_SECRET
      remoteRef:
        key: tripplanning-internal-secret
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: social-service-secrets
  namespace: {tenant["namespace"]}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: social-service-secrets
  data:
    - secretKey: TRIPPLANNING_AUTH_JWT_SECRET
      remoteRef:
        key: tripplanning-jwt-secret
    - secretKey: TRIPPLANNING_INTERNAL_SECRET
      remoteRef:
        key: tripplanning-internal-secret
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: external-info-service-secrets
  namespace: {tenant["namespace"]}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: external-info-service-secrets
  data:
    - secretKey: TRIPPLANNING_AUTH_JWT_SECRET
      remoteRef:
        key: tripplanning-jwt-secret
    - secretKey: TRIPPLANNING_INTERNAL_SECRET
      remoteRef:
        key: tripplanning-internal-secret
    - secretKey: GOOGLE_MAPS_API_KEY
      remoteRef:
        key: tripplanning-google-maps-api-key
    - secretKey: VIATOR_API_KEY
      remoteRef:
        key: tripplanning-viator-api-key
""",
            "values-configmap.yaml": f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: tripplanning-enterprise-{tenant_id}-values
  namespace: {tenant["namespace"]}
data:
  values.yaml: |
{chr(10).join(f"    {line}" if line else "" for line in render_enterprise_values(tenant_id, tenant, terraform_outputs).splitlines())}
""",
            "helmrelease.yaml": f"""apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tripplanning-enterprise-{tenant_id}
  namespace: {tenant["namespace"]}
spec:
  interval: 10m
  chart:
    spec:
      chart: ms2/charts/tripplanning
      reconcileStrategy: Revision
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      interval: 1m
  valuesFrom:
    - kind: ConfigMap
      name: tripplanning-enterprise-{tenant_id}-values
      valuesKey: values.yaml
""",
            "kustomization.yaml": """apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - serviceaccount-default.yaml
  - external-secrets.yaml
  - values-configmap.yaml
  - helmrelease.yaml
""",
        }
        if check:
            print(f"would write enterprise GitOps directory: {tenant_dir}")
            continue
        tenant_dir.mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            (tenant_dir / name).write_text(content, encoding="utf-8")

    enterprise_kustomization = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n"
    if resources:
        enterprise_kustomization += "resources:\n" + "\n".join(f"  - {item}" for item in resources) + "\n"
    else:
        enterprise_kustomization += "resources: []\n"
    if not check:
        ENTERPRISE_GITOPS_DIR.mkdir(parents=True, exist_ok=True)
        (ENTERPRISE_GITOPS_DIR / "kustomization.yaml").write_text(enterprise_kustomization, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Validate and print generated paths without writing files.")
    parser.add_argument("--terraform-only", action="store_true", help="Only render Terraform tfvars; skip GitOps output.")
    parser.add_argument(
        "--terraform-output-json",
        type=Path,
        help="Optional file from `terraform output -json` used to inject computed Identity Platform tenant IDs.",
    )
    args = parser.parse_args()

    standard = load_tenants("standard")
    enterprise = load_tenants("enterprise")
    terraform_outputs: dict[str, Any] = {}
    if args.terraform_output_json:
        terraform_outputs = json.loads(args.terraform_output_json.read_text(encoding="utf-8"))
    tfvars = {
        "standard_tenants": render_standard_tfvars(standard),
        "enterprise_tenants": render_enterprise_tfvars(enterprise),
    }
    standard_configmap = render_standard_configmap(standard, terraform_outputs)

    if args.check:
        print(json.dumps(tfvars, indent=2, sort_keys=True))
        print(f"would write: {TERRAFORM_OUT}")
        if not args.terraform_only:
            print(f"would write: {STANDARD_GITOPS_OUT}")
            print(f"would write: {STANDARD_DB_SECRET_OUT}")
            render_enterprise_gitops(enterprise, terraform_outputs, check=True)
        return

    TERRAFORM_OUT.write_text(json.dumps(tfvars, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not args.terraform_only:
        STANDARD_GITOPS_OUT.write_text(standard_configmap, encoding="utf-8")
        STANDARD_DB_SECRET_OUT.write_text(render_standard_db_external_secret(standard), encoding="utf-8")
        render_enterprise_gitops(enterprise, terraform_outputs, check=False)
    print(f"wrote {TERRAFORM_OUT}")
    if not args.terraform_only:
        print(f"wrote {STANDARD_GITOPS_OUT}")
        print(f"wrote {STANDARD_DB_SECRET_OUT}")
        print(f"wrote {ENTERPRISE_GITOPS_DIR}")


if __name__ == "__main__":
    main()
