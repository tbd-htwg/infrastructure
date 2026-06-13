# Tenant Definitions

Tenant definitions are the source of truth for Standard and Enterprise provisioning.

- Standard tenants live in `standard/<tenant-id>.yaml`.
- Enterprise tenants live in `enterprise/<tenant-id>.yaml`.
- Example files are intentionally named `example-*.yaml` and should not be applied as real tenants.

The provisioning flow is:

1. Add a tenant YAML file.
2. Generate Terraform tenant variables and GitOps/Helm values from the YAML.
3. Apply Terraform for cloud resources.
4. Let Flux reconcile generated GitOps manifests.
5. Run smoke tests for DNS, Identity Platform tenant matching, database routing, storage prefixes/buckets, and service health.

Run the renderer from `infrastructure/ms2`:

```bash
python3 scripts/render-tenants.py
```

For CI or manual preparation before Terraform has been applied, render only Terraform variables:

```bash
python3 scripts/render-tenants.py --terraform-only
```

After Terraform has created Identity Platform tenants, render again with real computed tenant IDs:

```bash
terraform -chdir=terraform/envs/dev output -json > /tmp/ms2-terraform-output.json
python3 scripts/render-tenants.py --terraform-output-json /tmp/ms2-terraform-output.json
```

The renderer skips files named `example-*.yaml` and writes:

- `terraform/envs/dev/generated-tenants.auto.tfvars.json`
- `gitops/tenants/standard/shared/generated-tenants-configmap.yaml`
- `gitops/tenants/enterprise/<tenant-id>/`
- `gitops/tenants/enterprise/kustomization.yaml`
