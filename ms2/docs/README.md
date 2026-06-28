# TripPlanning MS2 Infrastructure Documentation

This documentation describes the current `ms2` infrastructure only. Historical
migration notes are intentionally left out.

## Chapters

- [Cloud and Kubernetes Architecture](cloud-kubernetes-architecture.md)
- [CI/CD](cicd.md)
- [Infrastructure as Code](iac.md)
- [Monitoring](monitoring.md)
- [Scaling](scaling.md)
- [Multi Tenancy](multi-tenancy.md)
- [Routing](routing.md)
- [M3 Report](m3_report.md)

## Important Source Locations

- Terraform environment: `infrastructure/ms2/terraform/envs/dev`
- Terraform modules: `infrastructure/ms2/terraform/modules`
- GitOps manifests: `infrastructure/ms2/gitops`
- Helm chart: `infrastructure/ms2/charts/tripplanning`
- Tenant definitions: `infrastructure/ms2/tenants`
- Tenant renderer: `infrastructure/ms2/scripts/render-tenants.py`
- Backend deployment pipeline: `backend/.github/workflows/docker-publish-gke.yml`
- Frontend deployment pipeline: `frontend/.github/workflows/deploy-gcp-gke.yml`
