#!/usr/bin/env bash
# Run Terraform for this root inside hashicorp/terraform (no local Terraform binary).
# Mounts the parent infrastructure/ directory as /tf so paths like ../docker-compose.yml and
# ../.env in terraform.tfvars resolve.
#
# Prerequisites: Docker; gcloud auth application-default login (creates ADC below).
#
#   ./run-terraform-docker.sh init
#   ./run-terraform-docker.sh plan
#   ./run-terraform-docker.sh apply
#
# Override image: DOCKER_TERRAFORM_IMAGE=hashicorp/terraform:1.10 ./run-terraform-docker.sh plan
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${MODULE_DIR}/.." && pwd)"
MODULE_NAME="$(basename "${MODULE_DIR}")"
ADC="${HOME}/.config/gcloud/application_default_credentials.json"
IMAGE="${DOCKER_TERRAFORM_IMAGE:-hashicorp/terraform:1.9}"

if [[ ! -f "${ADC}" ]]; then
  echo "Missing ${ADC} — run: gcloud auth application-default login" >&2
  exit 1
fi
if ! command -v docker &>/dev/null; then
  echo "docker not found in PATH." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <terraform subcommand> [args...]" >&2
  echo "Example: $0 init && $0 plan && $0 apply" >&2
  exit 1
fi

drun=(docker run --rm)
if [[ -t 0 ]] && [[ -t 1 ]]; then
  drun+=(-it)
else
  drun+=(-i)
fi
drun+=(
  -v "${INFRA_ROOT}:/tf:z"
  -w "/tf/${MODULE_NAME}"
  -v "${ADC}:/root/adc.json:ro,z"
  -e GOOGLE_APPLICATION_CREDENTIALS=/root/adc.json
  "${IMAGE}"
)
drun+=("$@")

exec "${drun[@]}"
