#!/usr/bin/env bash
# Run lifecycle stages for this stack (see README.md). Two idempotent stages:
#
#   1  terraform -chdir=stage1 init + apply (Artifact Registry + GCS frontend bucket),
#      then docker build/push backend image, npm ci/build the SPA, gcloud storage rsync dist/
#      to the bucket, best-effort Cloud CDN invalidation (skipped if the URL map does not
#      yet exist, e.g. before stage 2 has run).
#
#   2  terraform -chdir=stage2 init + apply (APIs, Cloud SQL with PITR, service account,
#      Secret Manager, Cloud Run, HTTPS LB + CDN + managed SSL + HTTP→HTTPS redirect,
#      Cloud DNS A records, optional Cloud Armor). Image tag comes from stage 1 (saved to
#      .terraform-stage-tag) or from TAG.
#
#   --destroy   Destroy stage 2, then stage 1 (no stage number).
#               If sql_deletion_protection=true or frontend_bucket_force_destroy=false in
#               terraform.tfvars, flip the value, re-apply the matching stage, then retry.
#
#   --docker    Run Terraform inside hashicorp/terraform:1.9 with ADC mounted (Fedora SELinux
#               :z on the stack dir and the credentials file).
#
# Environment (optional):
#   AUTO_APPROVE=1              terraform apply/destroy -auto-approve (stages 1, 2, --destroy)
#   DOCKER_TERRAFORM_IMAGE=...  override image for --docker (default: hashicorp/terraform:1.9)
#   TAG=abc123                  backend image tag (default: git short SHA); written by stage 1
#   VITE_API_BASE_URL           stage 1: optional; defaults from cloud_run_api_hostname in tfvars
#   CORS_ALLOWED_ORIGINS        stage 2: comma-separated origins for CORS_ALLOWED_ORIGINS env
#   SKIP_FRONTEND_STATIC=1      stage 1: skip npm build + GCS upload + CDN invalidate
#   BACKEND_CONTEXT_DIR         stage 1: backend dir (default: auto-detect). Relative paths
#                               are anchored at this script's directory.
#   FRONTEND_CONTEXT_DIR        stage 1: frontend dir (same rules).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "${SCRIPT_DIR}" rev-parse --show-toplevel &>/dev/null; then
  REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
TAG_FILE="${SCRIPT_DIR}/.terraform-stage-tag"
TFVARS_FILE="${SCRIPT_DIR}/terraform.tfvars"
STAGE1_DIR="${SCRIPT_DIR}/stage1"
STAGE2_DIR="${SCRIPT_DIR}/stage2"

DOCKER_TERRAFORM_IMAGE="${DOCKER_TERRAFORM_IMAGE:-hashicorp/terraform:1.9}"

# ---------- helpers ---------------------------------------------------------

resolve_path_from_script() {
  local p="$1"
  if [[ "${p}" == /* ]]; then
    echo "${p}"
  else
    echo "${SCRIPT_DIR}/${p}"
  fi
}

resolve_backend_dir() {
  local d
  if [[ -n "${BACKEND_CONTEXT_DIR:-}" ]]; then
    d="$(resolve_path_from_script "${BACKEND_CONTEXT_DIR}")"
    if [[ ! -d "${d}" ]]; then
      echo "BACKEND_CONTEXT_DIR is not a directory: ${BACKEND_CONTEXT_DIR} (resolved: ${d})" >&2
      return 1
    fi
    echo "$(cd "${d}" && pwd)"
    return
  fi
  for d in "${REPO_ROOT}/backend" "${SCRIPT_DIR}/backend" "${SCRIPT_DIR}/../../backend"; do
    if [[ -d "$d" ]]; then
      echo "$(cd "$d" && pwd)"
      return
    fi
  done
  echo "Could not find backend directory. Tried: \${REPO_ROOT}/backend, ${SCRIPT_DIR}/backend, ${SCRIPT_DIR}/../../backend. Set BACKEND_CONTEXT_DIR." >&2
  return 1
}

resolve_frontend_dir() {
  local d
  if [[ -n "${FRONTEND_CONTEXT_DIR:-}" ]]; then
    d="$(resolve_path_from_script "${FRONTEND_CONTEXT_DIR}")"
    if [[ ! -d "${d}" ]]; then
      echo "FRONTEND_CONTEXT_DIR is not a directory: ${FRONTEND_CONTEXT_DIR} (resolved: ${d})" >&2
      return 1
    fi
    echo "$(cd "${d}" && pwd)"
    return
  fi
  for d in "${REPO_ROOT}/frontend" "${SCRIPT_DIR}/../../frontend"; do
    if [[ -d "$d" ]]; then
      echo "$(cd "$d" && pwd)"
      return
    fi
  done
  echo "Could not find frontend directory. Tried: \${REPO_ROOT}/frontend, ${SCRIPT_DIR}/../../frontend. Set FRONTEND_CONTEXT_DIR." >&2
  return 1
}

# Read HCL "key = \"value\"" (first match, non-comment) from terraform.tfvars.
tfvars_get_string() {
  local key="$1"
  [[ -f "${TFVARS_FILE}" ]] || return 1
  local line
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${TFVARS_FILE}" | grep -v '^[[:space:]]*#' | head -1)" || return 1
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ "${line}" =~ ^\"(.*)\"$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "${line}" =~ ^\'(.*)\'$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "${line}"
  fi
}

docker_hint() {
  [[ "${USE_DOCKER}" == "1" ]] && echo "--docker " || true
}

usage() {
  sed -n '2,30p' "$0" | sed 's/^# //' >&2
  echo "" >&2
  echo "Usage: $0 [--docker] <1|2>" >&2
  echo "       $0 [--docker] --destroy   (no stage number; destroys stage2 then stage1)" >&2
  exit 1
}

require_tfvars() {
  if [[ ! -f "${TFVARS_FILE}" ]]; then
    echo "Missing ${TFVARS_FILE} — copy terraform.tfvars.example and edit." >&2
    exit 1
  fi
}

# tf <stage_dir> <terraform args...>
# Runs terraform for the given root module. With --docker, mounts SCRIPT_DIR so the shared
# terraform.tfvars (referenced as ../terraform.tfvars inside each stage dir) resolves.
tf() {
  local stage_dir="$1"
  shift
  if [[ "${USE_DOCKER}" == "1" ]]; then
    local adc="${HOME}/.config/gcloud/application_default_credentials.json"
    if [[ ! -f "${adc}" ]]; then
      echo "Missing ${adc} — run: gcloud auth application-default login" >&2
      exit 1
    fi
    if ! command -v docker &>/dev/null; then
      echo "docker not found in PATH (required for --docker)." >&2
      exit 1
    fi
    # Translate stage_dir (host) to the equivalent path inside the /tf mount.
    local rel="${stage_dir#"${SCRIPT_DIR}"}"
    local container_dir="/tf${rel}"
    local -a drun=(docker run --rm)
    if [[ -t 0 ]] && [[ -t 1 ]] && [[ "${AUTO_APPROVE:-}" != "1" ]]; then
      drun+=(-it)
    else
      drun+=(-i)
    fi
    drun+=(
      -v "${SCRIPT_DIR}:/tf:z"
      -w "${container_dir}"
      -v "${adc}:/root/adc.json:ro,z"
      -e GOOGLE_APPLICATION_CREDENTIALS=/root/adc.json
      "${DOCKER_TERRAFORM_IMAGE}"
    )
    drun+=("$@")
    "${drun[@]}"
  else
    terraform -chdir="${stage_dir}" "$@"
  fi
}

apply_args() {
  local -a a=()
  [[ "${AUTO_APPROVE:-}" == "1" ]] && a+=(-auto-approve)
  printf '%s\n' "${a[@]}"
}

# ---------- stage runners ---------------------------------------------------

run_stage1() {
  require_tfvars

  echo "==> Stage 1: terraform apply (assets)" >&2
  tf "${STAGE1_DIR}" init
  local -a a=()
  [[ "${AUTO_APPROVE:-}" == "1" ]] && a+=(-auto-approve)
  tf "${STAGE1_DIR}" apply "${a[@]}" -var-file=../terraform.tfvars

  # --- derive tag, build & push backend image ---
  if [[ -z "${TAG:-}" ]]; then
    if git -C "${REPO_ROOT}" rev-parse --short HEAD &>/dev/null; then
      TAG=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
    elif git rev-parse --short HEAD &>/dev/null; then
      TAG=$(git rev-parse --short HEAD)
    else
      TAG="$(date +%Y%m%d-%H%M%S)"
      echo "No git repo (or git unavailable); using TAG=${TAG}. Set TAG=... to override." >&2
    fi
  fi
  echo "${TAG}" >"${TAG_FILE}"
  echo "Using TAG=${TAG} for backend image" >&2

  local base region ar_host backend_service backend_image
  base="$(tf "${STAGE1_DIR}" output -raw artifact_registry_url)"
  region="$(tf "${STAGE1_DIR}" output -raw region)"
  ar_host="${region}-docker.pkg.dev"
  backend_service="$(tfvars_get_string cloud_run_backend_service_name || echo "tbd-tf-backend")"
  backend_image="${base}/${backend_service}:${TAG}"

  if ! command -v docker &>/dev/null; then
    echo "docker not found in PATH." >&2
    exit 1
  fi
  if ! command -v gcloud &>/dev/null; then
    echo "gcloud not found in PATH (required for Artifact Registry docker auth and GCS upload)." >&2
    exit 1
  fi
  case "${base}/" in
    "${ar_host}/"*) ;;
    *)
      echo "Mismatch: artifact_registry_url (${base}) does not use Terraform region host ${ar_host}. Check terraform.tfvars region." >&2
      exit 1
      ;;
  esac

  echo "Configuring Docker credentials for Artifact Registry (${ar_host}) …" >&2
  if ! gcloud auth configure-docker "${ar_host}" --quiet; then
    gcloud auth configure-docker "${ar_host}"
  fi

  local backend_dir
  backend_dir="$(resolve_backend_dir)" || exit 1
  echo "Building backend image: ${backend_image}" >&2
  echo "Backend build context: ${backend_dir}" >&2
  docker build -t "${backend_image}" "${backend_dir}"
  docker push "${backend_image}"

  # --- build & upload SPA ---
  if [[ "${SKIP_FRONTEND_STATIC:-}" == "1" ]]; then
    echo "SKIP_FRONTEND_STATIC=1 — skipped npm build and GCS upload." >&2
  else
    if [[ -z "${VITE_API_BASE_URL:-}" ]]; then
      local api_host
      api_host="$(tfvars_get_string cloud_run_api_hostname || true)"
      if [[ -n "${api_host}" ]]; then
        VITE_API_BASE_URL="https://${api_host}/api/v2"
        echo "Using VITE_API_BASE_URL=${VITE_API_BASE_URL} (from cloud_run_api_hostname in terraform.tfvars)" >&2
      else
        echo "Could not set VITE_API_BASE_URL: set cloud_run_api_hostname in terraform.tfvars, or export VITE_API_BASE_URL=..." >&2
        exit 1
      fi
    fi

    if ! command -v npm &>/dev/null; then
      echo "npm not found in PATH (required for frontend build)." >&2
      exit 1
    fi

    local frontend_dir bucket project
    frontend_dir="$(resolve_frontend_dir)" || exit 1
    bucket="$(tf "${STAGE1_DIR}" output -raw frontend_bucket_name)"
    project="$(tf "${STAGE1_DIR}" output -raw project_id)"

    echo "Building React app in ${frontend_dir} …" >&2
    (cd "${frontend_dir}" && npm ci && VITE_API_BASE_URL="${VITE_API_BASE_URL}" npm run build)

    echo "Uploading dist/ to gs://${bucket} (content-addressed rsync) …" >&2
    gcloud storage rsync "${frontend_dir}/dist" "gs://${bucket}" \
      --recursive \
      --checksums-only \
      --delete-unmatched-destination-objects \
      --project="${project}"

    # Best-effort CDN invalidate: only if the URL map from stage 2 already exists.
    local url_map
    url_map="$(tfvars_get_string frontend_url_map_name || echo "tbd-tf-lb")"
    if gcloud compute url-maps describe "${url_map}" --project="${project}" --global &>/dev/null; then
      echo "Invalidating Cloud CDN cache for url map ${url_map} …" >&2
      gcloud compute url-maps invalidate-cdn-cache "${url_map}" --path="/*" --project="${project}"
    else
      echo "URL map ${url_map} not found — skipping CDN invalidation (stage 2 has not created it yet, or the name differs)." >&2
    fi
  fi

  echo "Stage 1 done. Next: $0 $(docker_hint)2" >&2
}

run_stage2() {
  require_tfvars

  # Resolve TAG for backend_image_tag. Prefer the on-disk stage-tag written by stage 1.
  if [[ -z "${TAG:-}" ]]; then
    if [[ -f "${TAG_FILE}" ]]; then
      TAG="$(cat "${TAG_FILE}")"
    else
      echo "Missing ${TAG_FILE} — run stage 1 first ($0 $(docker_hint)1), or set TAG to match your pushed backend image." >&2
      exit 1
    fi
  fi
  echo "==> Stage 2: terraform apply (app) with backend_image_tag=${TAG}" >&2

  tf "${STAGE2_DIR}" init
  local -a a=()
  [[ "${AUTO_APPROVE:-}" == "1" ]] && a+=(-auto-approve)
  local -a vars=(
    -var-file=../terraform.tfvars
    -var="backend_image_tag=${TAG}"
  )
  if [[ -n "${CORS_ALLOWED_ORIGINS:-}" ]]; then
    vars+=(-var="cors_allowed_origins=${CORS_ALLOWED_ORIGINS}")
  fi
  tf "${STAGE2_DIR}" apply "${a[@]}" "${vars[@]}"

  echo "Stage 2 done." >&2
}

run_destroy() {
  require_tfvars

  local -a a=()
  [[ "${AUTO_APPROVE:-}" == "1" ]] && a+=(-auto-approve)

  # Stage 2 first — it depends on stage 1's AR repo and GCS bucket.
  if [[ -d "${STAGE2_DIR}" ]]; then
    echo "==> Destroy stage 2" >&2
    tf "${STAGE2_DIR}" init
    local tag="${TAG:-$( [[ -f "${TAG_FILE}" ]] && cat "${TAG_FILE}" || echo "destroy-placeholder" )}"
    tf "${STAGE2_DIR}" destroy "${a[@]}" \
      -var-file=../terraform.tfvars \
      -var="backend_image_tag=${tag}"
  fi

  if [[ -d "${STAGE1_DIR}" ]]; then
    echo "==> Destroy stage 1" >&2
    tf "${STAGE1_DIR}" init
    tf "${STAGE1_DIR}" destroy "${a[@]}" -var-file=../terraform.tfvars
  fi

  echo "Destroy complete. If Cloud SQL deletion_protection or bucket force_destroy blocked the run," >&2
  echo "flip those flags in terraform.tfvars, re-apply the matching stage, then rerun $0 $(docker_hint)--destroy." >&2
}

# ---------- argument parsing ------------------------------------------------

USE_DOCKER=0
DESTROY=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    --docker)
      USE_DOCKER=1
      shift
      ;;
    --destroy)
      DESTROY=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ "${DESTROY}" == "1" ]]; then
  if [[ -n "${1:-}" ]]; then
    echo "Do not pass a stage number with --destroy. Use: $0 $(docker_hint)--destroy" >&2
    exit 1
  fi
  run_destroy
  exit 0
fi

case "${1:-}" in
  "")
    usage
    ;;
  1)
    run_stage1
    ;;
  2)
    run_stage2
    ;;
  3)
    echo "Stage 3 no longer exists — the layout is two idempotent stages now. Use '1' then '2'." >&2
    exit 1
    ;;
  *)
    usage
    ;;
esac
