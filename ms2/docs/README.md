# ms2 Infrastructure

Terraform + GitOps for GKE Autopilot (trip + social microservices).

| Doc | Contents |
|-----|----------|
| **[gettingstarted/README.md](gettingstarted/README.md)** | **Start here** — step-by-step guide + [`dev-lifecycle.sh`](gettingstarted/dev-lifecycle.sh) (teardown / setup / reset) |
| [terraform/envs/dev/README.md](../terraform/envs/dev/README.md) | Terraform apply & import existing resources |
| [agents.instructions.md](agents.instructions.md) | Agent / maintainer notes |

**Quick start** (from this repo root — the directory that contains `ms2/`): `ms2/docs/gettingstarted/dev-lifecycle.sh reset` (or `teardown` then `setup`). If 409 errors, run `ms2/scripts/terraform-import-existing-dev.sh`.
