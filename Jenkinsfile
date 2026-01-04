pipeline {
  agent any

  options {
    buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '14'))
    timestamps()
  }

  environment {
    // ---------- Docker Hub ----------
    DOCKERHUB_REPO    = 'chadkhoanguyen/house-price-prediction-api'
    DOCKERHUB_CRED_ID = 'dockerhub'

    // ---------- GCP / GKE / Terraform ----------
    PROJECT_ID   = 'tensile-axiom-482205-g8'
    REGION       = 'asia-southeast1'
    LOCATION     = 'global'

    POOL_ID      = 'jenkins-pool'
    PROVIDER_ID  = 'jenkins-oidc'
    SA_EMAIL     = 'terraform-jenkins@tensile-axiom-482205-g8.iam.gserviceaccount.com'

    GKE_CLUSTER_NAME = 'house-price-cluster'
    GKE_NAMESPACE    = 'default'

    APP_NAME         = 'house-price-api'
    CONTAINER_PORT   = '5000'
    SERVICE_PORT     = '80'

    TF_VER           = '1.6.6'
    TF_IN_AUTOMATION = 'true'
    TF_INPUT         = 'false'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Test') {
      agent {
        docker {
          image 'python:3.8'
          args '-u 0:0'
        }
      }
      steps {
        sh '''
          set -euo pipefail
          pip install -r requirements.txt
          pytest
        '''
      }
    }

    stage('Build & Push') {
      steps {
        script {
          def tag = env.BUILD_NUMBER
          def image = "${DOCKERHUB_REPO}:${tag}"

          sh """
            set -euo pipefail
            docker build -t ${image} .
          """

          docker.withRegistry('https://index.docker.io/v1/', DOCKERHUB_CRED_ID) {
            sh """
              docker tag ${image} ${DOCKERHUB_REPO}:latest
              docker push ${DOCKERHUB_REPO}:${tag}
              docker push ${DOCKERHUB_REPO}:latest
            """
          }
        }
      }
    }

    stage('Auth (WIF) + Terraform Apply') {
      agent {
        docker {
          image 'google/cloud-sdk:slim'
          args '-u 0:0'
        }
      }

      steps {
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            bash -lc '
              set -euo pipefail

              apt-get update -y
              apt-get install -y curl unzip python3

              curl -fsSL -o /tmp/terraform.zip \
                https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_amd64.zip
              unzip -o /tmp/terraform.zip -d /usr/local/bin
              terraform -version

              cat > wif-creds.json <<EOF
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/${PROJECT_ID}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA_EMAIL}:generateAccessToken",
  "credential_source": {
    "file": "${ID_TOKEN_FILE}",
    "format": { "type": "text" }
  }
}
EOF

              export GOOGLE_APPLICATION_CREDENTIALS="$PWD/wif-creds.json"

              ACCESS_TOKEN="$(gcloud auth application-default print-access-token)"

              PROJECT_NUMBER="$(
                curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                  https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID} \
                | python3 - <<PY
import json,sys
print(json.load(sys.stdin)["projectNumber"])
PY
              )"

              export TF_VAR_project_number="${PROJECT_NUMBER}"

              terraform init
              terraform validate
              terraform plan -out=tfplan
              terraform apply -auto-approve tfplan
            '
          '''
        }
      }
    }

    stage('Deploy to GKE') {
      agent {
        docker {
          image 'google/cloud-sdk:slim'
          args '-u 0:0'
        }
      }

      steps {
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            bash -lc '
              set -euo pipefail

              cat > wif-creds.json <<EOF
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/${PROJECT_ID}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA_EMAIL}:generateAccessToken",
  "credential_source": {
    "file": "${ID_TOKEN_FILE}",
    "format": { "type": "text" }
  }
}
EOF

              export GOOGLE_APPLICATION_CREDENTIALS="$PWD/wif-creds.json"

              gcloud config set project ${PROJECT_ID}
              gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region ${REGION}

              IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"

              kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${IMAGE}
        ports:
        - containerPort: ${CONTAINER_PORT}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-svc
spec:
  type: LoadBalancer
  selector:
    app: ${APP_NAME}
  ports:
  - port: ${SERVICE_PORT}
    targetPort: ${CONTAINER_PORT}
YAML

              kubectl rollout status deployment/${APP_NAME} --timeout=180s
              kubectl get svc ${APP_NAME}-svc
            '
          '''
        }
      }
    }
  }
}
