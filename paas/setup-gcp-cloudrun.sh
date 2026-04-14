#!/usr/bin/env bash
set -euo pipefail

############################################################################
# ENVIRONMENT SETUP
############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/gcp.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "Missing ${ENV_FILE}. Copy gcp.env.example to gcp.env and fill it." >&2
  exit 1
fi

required=(
  PROJECT_ID
  REGION
  ARTIFACT_REPO
  BACKEND_SERVICE
  RUN_SA_NAME
  DB_INSTANCE
  DB_NAME
  DB_USER
  DB_PASSWORD
  DB_PASSWORD_SECRET
)

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable: ${key}" >&2
    exit 1
  fi
done

############################################################################
# GCP RESOURCE SETUP
############################################################################

if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  if [[ -z "${APP_NAME:-}" ]]; then
    echo "Project ${PROJECT_ID} does not exist and APP_NAME is not set." >&2
    echo "Set APP_NAME in gcp.env to let this script create the project." >&2
    exit 1
  fi
  echo "Project ${PROJECT_ID} not found. Creating project..."
  gcloud projects create "${PROJECT_ID}" --name="${APP_NAME}"
  echo "Project created. Ensure billing is enabled before continuing deployments."
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
RUN_SA_EMAIL="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

############################################################################
# CORE SERVICES AND RESOURCE CREATION
############################################################################

echo "Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Enabling required APIs..."
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

echo "Creating Artifact Registry repository if missing..."
if ! gcloud artifacts repositories describe "${ARTIFACT_REPO}" --location="${REGION}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${ARTIFACT_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Tripplanning container images"
fi

echo "Creating Cloud SQL Postgres instance if missing..."
if ! gcloud sql instances describe "${DB_INSTANCE}" >/dev/null 2>&1; then
  gcloud sql instances create "${DB_INSTANCE}" \
    --database-version=POSTGRES_15 \
    --cpu=1 \
    --memory=3840MB \
    --region="${REGION}"
fi

echo "Creating database if missing..."
if ! gcloud sql databases describe "${DB_NAME}" --instance="${DB_INSTANCE}" >/dev/null 2>&1; then
  gcloud sql databases create "${DB_NAME}" --instance="${DB_INSTANCE}"
fi

echo "Creating/updating DB user..."
if gcloud sql users list --instance="${DB_INSTANCE}" --format='value(name)' | grep -Fxq "${DB_USER}"; then
  gcloud sql users set-password "${DB_USER}" --instance="${DB_INSTANCE}" --password="${DB_PASSWORD}"
else
  gcloud sql users create "${DB_USER}" --instance="${DB_INSTANCE}" --password="${DB_PASSWORD}"
fi

echo "Creating Cloud Run service account if missing..."
if ! gcloud iam service-accounts describe "${RUN_SA_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${RUN_SA_NAME}" \
    --display-name="Tripplanning Cloud Run runtime"
fi

############################################################################
# IAM AND SECRET ACCESS CONFIGURATION
############################################################################

echo "Granting Cloud SQL client role to runtime SA..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${RUN_SA_EMAIL}" \
  --role="roles/cloudsql.client" >/dev/null

echo "Creating/updating Secret Manager secret for DB password..."
if ! gcloud secrets describe "${DB_PASSWORD_SECRET}" >/dev/null 2>&1; then
  gcloud secrets create "${DB_PASSWORD_SECRET}" --replication-policy="automatic"
fi
printf '%s' "${DB_PASSWORD}" | gcloud secrets versions add "${DB_PASSWORD_SECRET}" --data-file=- >/dev/null

echo "Granting runtime SA access to DB password secret..."
gcloud secrets add-iam-policy-binding "${DB_PASSWORD_SECRET}" \
  --member="serviceAccount:${RUN_SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null

CONNECTION_NAME="$(gcloud sql instances describe "${DB_INSTANCE}" --format='value(connectionName)')"

############################################################################
# SUMMARY OUTPUT
############################################################################

cat <<EOF

Setup complete.

Project number: ${PROJECT_NUMBER}
Cloud Run runtime SA: ${RUN_SA_EMAIL}
Cloud SQL connection name: ${CONNECTION_NAME}
Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}

Next step:
1) Run deploy-backend-cloudrun.sh for backend manual deploy
2) Run deploy-frontend-cloudrun.sh for frontend manual deploy
3) Configure GitHub Actions secrets/vars and use backend/.github/workflows/deploy-gcp-cloudrun.yml and frontend/.github/workflows/deploy-gcp-cloudrun.yml
EOF
