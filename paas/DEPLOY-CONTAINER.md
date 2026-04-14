# Guide for deploying on Google Cloud Run

Precondition: image has been built.

### Create Google Cloud Environment

Create Google Cloud project. After creation you need to activate billing in the Google cloud console.
```bash
APP_NAME="Camping Application 2026s-swqs"
PROJECT_ID="swqs-2026s-camping-application"
VERSION=26.2
REGION="europe-west1"
SERVICE="camping-app"
RUN_SA="swqs-2026s-camping-app-sa"
```
DB Config:
``` bash
INSTANCE="camping-mysql-2026s-swqs"
DB="cad_test"
DB_USER="usercad_test"
```

Set password
```
DB_PASS="...."
```


## Create ressources

```bash
gcloud auth login   

gcloud projects create "$PROJECT_ID" --name="$APP_NAME"

gcloud config set project "$PROJECT_ID" 

gcloud services enable run.googleapis.com   
gcloud services enable sqladmin.googleapis.com secretmanager.googleapis.com
gcloud services enable artifactregistry.googleapis.com  
```
```bash
gcloud sql instances create "$INSTANCE" \
  --database-version=MYSQL_8_0 \
  --cpu=1 \
  --memory=3840MB \
  --region="$REGION" \
  --root-password='my-root-password'

gcloud sql databases create "$DB" --instance="$INSTANCE"
gcloud sql users create "$DB_USER" --instance="$INSTANCE" --password="$DB_PASS"
CONN_NAME="$(gcloud sql instances describe "$INSTANCE" --format='value(connectionName)')"
echo "Connection name: $CONN_NAME"   # looks like: PROJECT:REGION:INSTANCE
```

### Create docker repo and activate cloud run

```bash
gcloud artifacts repositories create docker-repo \                                                          
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for Camping application"

 gcloud auth configure-docker europe-west1-docker.pkg.dev 
```

### Deployment to Google Cloud Environment

To deploy a container follow the steps below. Change version if needed:

Service Account to connect SQL Database to Cloud Run:

```bash
gcloud iam service-accounts create "$RUN_SA" --display-name="Cloud Run SA for camping app"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${RUN_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```


On mac with ARM Architecture first build a linux/amd64 image, on amd64 architectures you can omit this step:
```bash
mvn package
docker build --platform linux/amd64 -t de.htwg-konstanz.in/camping:"$VERSION" .
```
Then tag it and push it:
```bash
docker tag de.htwg-konstanz.in/camping:"$VERSION" europe-west1-docker.pkg.dev/"$PROJECT_ID"/docker-repo/camping:"$VERSION"

docker push europe-west1-docker.pkg.dev/"$PROJECT_ID"/docker-repo/camping:"$VERSION"
```

With Cloud SQL
```bash
gcloud run deploy "$SERVICE" \
--image=europe-west1-docker.pkg.dev/${PROJECT_ID}/docker-repo/camping:${VERSION} \
--platform=managed \
--region=${REGION} \
--allow-unauthenticated \
--port=8081 \
--memory=1Gi \
--service-account="${RUN_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
--add-cloudsql-instances="${PROJECT_ID}:${REGION}:${INSTANCE}" \
--set-env-vars \
"SPRING_PROFILES_ACTIVE=dev,SPRING_DATASOURCE_URL=jdbc:mysql:///cad_test?cloudSqlInstance=${PROJECT_ID}:${REGION}:${INSTANCE}&socketFactory=com.google.cloud.sql.mysql.SocketFactory,SPRING_DATASOURCE_USERNAME=${DB_USER},SPRING_DATASOURCE_PASSWORD=${DB_PASS}"
```

### DNS

To map the domain to the cloud run service you need to add a DNS entry.
```bash
gcloud domains verify htwg-cloud.org

gcloud beta run domain-mappings create --region=europe-west1 --service camping-app --domain my-camping.htwg-cloud.org
```

# CI

## Setup service account to push docker container to google cloud registry

gcloud iam service-accounts create camping-ci-push-image
gcloud iam service-accounts keys create camping-ci-push-image.json --iam-account camping-ci-push-image@swqs-camping.iam.gserviceaccount.com
gcloud artifacts repositories add-iam-policy-binding docker-repo --location=europe-west1 --member="serviceAccount:camping-ci-push-image@swqs-camping.iam.gserviceaccount.com" --role="roles/artifactregistry.createOnPushWriter"

### Cleanup

gcloud sql instances delete "$INSTANCE" --quiet

## Heroku

For running the app on heroku use:
```
SPRING_PROFILES_ACTIVE=dev
SPRING_DATASOURCE_URL=jdbc:mysql://193.196.53.194:33061/cad_test
SPRING_DATASOURCE_USERNAME=usercad_test
SPRING_DATASOURCE_PASSWORD=a11699
```
