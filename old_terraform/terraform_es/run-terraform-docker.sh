#!/usr/bin/env bash
# Run Terraform in hashicorp/terraform; mounts infrastructure/ as /tf.
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
