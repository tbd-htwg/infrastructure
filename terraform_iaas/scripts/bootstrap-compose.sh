#!/bin/bash
# Run on the VM (GCE startup or manually): install Docker + gcloud if missing, then sync compose
# from GCS, load .env + SA JSON from Secret Manager, start the stack. Caddy uses
# GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-sa.json (see docker-compose.iaas.yml).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

INSTALL_DIR="${INSTALL_DIR:-/opt/tripplanning}"
META_BASE="http://metadata.google.internal/computeMetadata/v1"

iaas_log() {
  echo "[iaas-bootstrap] $*"
}

# Wait only while dpkg is actually locked. Do not match unattended-upgrade-shutdown (idle helper).
dpkg_is_busy() {
  if command -v fuser >/dev/null 2>&1; then
    fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
      || fuser /var/lib/dpkg/lock >/dev/null 2>&1
  else
    pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1
  fi
}

wait_for_apt_lock() {
  local max_wait="${1:-600}"
  local deadline=$((SECONDS + max_wait))
  while (( SECONDS < deadline )); do
    if dpkg_is_busy; then
      iaas_log "Waiting for dpkg lock (another apt/dpkg run)..."
      sleep 5
      continue
    fi
    sleep 1
    if ! dpkg_is_busy; then
      return 0
    fi
  done
  iaas_log "ERROR: timed out after ${max_wait}s waiting for dpkg lock"
  return 1
}

ensure_apt_base() {
  wait_for_apt_lock
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  iaas_log "Installing Docker Engine (get.docker.com)"
  curl -fsSL https://get.docker.com | sh
}

ensure_gcloud() {
  if command -v gsutil >/dev/null 2>&1 && command -v gcloud >/dev/null 2>&1; then
    return 0
  fi
  iaas_log "Installing Google Cloud CLI (gsutil + gcloud)"
  wait_for_apt_lock
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
  echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt-get update -qq
  apt-get install -y -qq google-cloud-cli
}

# Install tooling first (logs go to serial console / cloud-init before we attach tee).
ensure_apt_base
ensure_docker
ensure_gcloud

mkdir -p /var/log
exec > >(tee -a /var/log/iaas-bootstrap.log) 2>&1

get_attr() {
  curl -fsS -H "Metadata-Flavor: Google" "${META_BASE}/instance/attributes/$1"
}

PROJECT_ID=$(curl -fsS -H "Metadata-Flavor: Google" "${META_BASE}/project/project-id")
BUCKET=$(get_attr iaas_assets_bucket)
ENV_SECRET=$(get_attr iaas_env_secret_id)
SA_SECRET=$(get_attr iaas_sa_secret_id)
ELASTIC_SECRET_ID=$(get_attr iaas_elasticsearch_secret_id)
TIER_HOST=$(get_attr iaas_tier_hostname)
ES_JAVA_OPTS=$(get_attr es_java_opts)

iaas_log "Syncing stack files from gs://${BUCKET}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
gsutil cp "gs://${BUCKET}/docker-compose.yml" .
gsutil cp "gs://${BUCKET}/docker-compose.iaas.yml" .
gsutil cp "gs://${BUCKET}/Caddyfile" .

iaas_log "Fetching shared .env from Secret Manager"
gcloud secrets versions access latest --secret="${ENV_SECRET}" --project="${PROJECT_ID}" > .env.raw
sed -e '/^CADDY_DOMAIN=/d' -e '/^GCP_PROJECT=/d' -e '/^GOOGLE_APPLICATION_CREDENTIALS=/d' \
  -e '/^ELASTIC_PASSWORD=/d' -e '/^ES_SECURITY_ENABLED=/d' \
  -e '/^ELASTICSEARCH_USERNAME=/d' -e '/^ELASTICSEARCH_PASSWORD=/d' \
  -e '/^GHCR_TOKEN=/d' -e '/^GITHUB_TOKEN=/d' \
  .env.raw > .env
rm -f .env.raw
printf '\n# Per-VM (IaaS)\nCADDY_DOMAIN=%s\nGCP_PROJECT=%s\nGOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-sa.json\n' \
  "${TIER_HOST}" "${PROJECT_ID}" >> .env

iaas_log "Fetching Elasticsearch password for this tier"
ES_PASS="$(gcloud secrets versions access latest --secret="${ELASTIC_SECRET_ID}" --project="${PROJECT_ID}")"
{
  echo ""
  echo "# Elasticsearch (xpack; HTTPS via Caddy /es/)"
  echo "ES_SECURITY_ENABLED=true"
  echo "ELASTIC_PASSWORD=${ES_PASS}"
  echo "ELASTICSEARCH_USERNAME=elastic"
  echo "ELASTICSEARCH_PASSWORD=${ES_PASS}"
} >> .env

iaas_log "Writing service account JSON for Caddy DNS-01"
gcloud secrets versions access latest --secret="${SA_SECRET}" --project="${PROJECT_ID}" > gcp-sa.json
chmod 600 gcp-sa.json .env

mkdir -p data config static logs

iaas_log "Writing Elasticsearch heap override"
cat > docker-compose.es.yml <<EOF
services:
  elasticsearch:
    environment:
      ES_JAVA_OPTS: "${ES_JAVA_OPTS}"
EOF

# Optional: ghcr.io (metadata set by Terraform when ghcr_username + ghcr_token_file are configured).
GHCR_USER=$(curl -fsS --fail -H "Metadata-Flavor: Google" "${META_BASE}/instance/attributes/iaas_ghcr_username" 2>/dev/null || true)
GHCR_SECRET_ID=$(curl -fsS --fail -H "Metadata-Flavor: Google" "${META_BASE}/instance/attributes/iaas_ghcr_token_secret_id" 2>/dev/null || true)
if [[ -n "${GHCR_USER}" && -n "${GHCR_SECRET_ID}" ]]; then
  iaas_log "Logging in to ghcr.io as ${GHCR_USER}"
  GHCR_PAT="$(gcloud secrets versions access latest --secret="${GHCR_SECRET_ID}" --project="${PROJECT_ID}")"
  printf '%s' "${GHCR_PAT}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
fi

iaas_log "docker compose pull && up -d"
docker compose -f docker-compose.yml -f docker-compose.iaas.yml -f docker-compose.es.yml pull
docker compose -f docker-compose.yml -f docker-compose.iaas.yml -f docker-compose.es.yml up -d

iaas_log "Done. Host: ${TIER_HOST} (logs: /var/log/iaas-bootstrap.log)"
