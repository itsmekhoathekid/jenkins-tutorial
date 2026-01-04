// Jenkinsfile — Full pipeline (Option A: WIF + REST projectNumber + Terraform + GKE deploy)
// Trigger: push to branch main

pipeline {
  agent any

  options {
    buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '14'))
    timestamps()
    ansiColor('xterm')
  }

  environment {
    // ---------- Docker Hub ----------
    DOCKERHUB_REPO        = 'chadkhoanguyen/house-price-prediction-api'
    DOCKERHUB_CRED_ID     = 'dockerhub'              // Jenkins credential (Username/Password)

    // ---------- GitHub ----------
    // (SCM checkout uses Jenkins job's SCM config; credential is in job config)

    // ---------- GCP / GKE / Terraform (WIF) ----------
    PROJECT_ID            = 'tensile-axiom-482205-g8'
    REGION                = 'asia-southeast1'        // or your region
    LOCATION              = 'global'                // WIF pool location is usually "global"
    POOL_ID               = 'jenkins-pool'
    PROVIDER_ID           = 'jenkins-oidc'
    SA_EMAIL              = 'terraform-jenkins@tensile-axiom-482205-g8.iam.gserviceaccount.com'

    // GKE cluster info
    GKE_CLUSTER_NAME      = 'house-price-cluster'
    GKE_NAMESPACE         = 'default'

    // K8S deploy settings
    APP_NAME              = 'house-price-api'
    CONTAINER_PORT        = '5000'
    SERVICE_PORT          = '80'

    // Terraform
    TF_VER                = '1.6.6'
    TF_IN_AUTOMATION      = 'true'
    TF_INPUT              = 'false'
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
          args  '-u 0:0'
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
          def tag = "${env.BUILD_NUMBER}"
          def image = "${env.DOCKERHUB_REPO}:${tag}"

          sh """
            set -euo pipefail
            docker build -t ${image} .
          """

          docker.withRegistry('https://index.docker.io/v1/', env.DOCKERHUB_CRED_ID) {
            sh """
              set -euo pipefail
              docker tag ${image} ${env.DOCKERHUB_REPO}:latest
              docker push ${env.DOCKERHUB_REPO}:${tag}
              docker push ${env.DOCKERHUB_REPO}:latest
            """
          }
        }
      }
    }

    stage('Auth (WIF) + Terraform Apply') {
      agent {
        docker {
          image 'google/cloud-sdk:slim'
          args  '-u 0:0'
        }
      }

      steps {
        // This credential must be "OpenID Connect id token as file"
        // Jenkins credentialId: jenkins-oidc-token-file
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            bash -lc '
              set -euo pipefail

              echo "=== Install deps ==="
              apt-get update -y
              apt-get install -y curl unzip python3

              echo "=== Install Terraform ==="
              curl -fsSL -o /tmp/terraform.zip \
                https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_amd64.zip
              unzip -o /tmp/terraform.zip -d /usr/local/bin
              terraform -version

              echo "=== Build WIF external account credential file ==="
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

              echo "=== Get ACCESS_TOKEN via ADC (NO active gcloud account needed) ==="
              ACCESS_TOKEN="$(gcloud auth application-default print-access-token)"
              echo "Access token length=${#ACCESS_TOKEN}"

              echo "=== Get PROJECT_NUMBER via Cloud Resource Manager API ==="
              PROJECT_NUMBER="$(
                curl -fsSL \
                  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                  "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}" \
                | python3 - <<PY
import json,sys
print(json.load(sys.stdin)["projectNumber"])
PY
              )"
              echo "PROJECT_NUMBER=${PROJECT_NUMBER}"

              # Optional: pass into terraform if you use variable "project_number"
              export TF_VAR_project_number="${PROJECT_NUMBER}"

              echo "=== Terraform init/validate/plan/apply ==="
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
          args  '-u 0:0'
        }
      }

      steps {
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            bash -lc '
              set -euo pipefail

              echo "=== Install deps ==="
              apt-get update -y
              apt-get install -y curl python3

              echo "=== Build WIF credential file ==="
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

              echo "=== Configure gcloud to use ADC token for GKE calls ==="
              gcloud config set project "${PROJECT_ID}" >/dev/null

              echo "=== Get GKE credentials ==="
              gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}"

              echo "=== Apply K8s manifests (inline) ==="
              IMAGE_TAG="${BUILD_NUMBER}"
              IMAGE="${DOCKERHUB_REPO}:${IMAGE_TAG}"

              cat > k8s.yaml <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${GKE_NAMESPACE}
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
          imagePullPolicy: Always
          ports:
            - containerPort: ${CONTAINER_PORT}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-svc
  namespace: ${GKE_NAMESPACE}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      port: ${SERVICE_PORT}
      targetPort: ${CONTAINER_PORT}
  type: LoadBalancer
YAML

              kubectl apply -f k8s.yaml

              echo "=== Rollout status ==="
              kubectl rollout status deployment/${APP_NAME} -n ${GKE_NAMESPACE} --timeout=180s

              echo "=== Service ==="
              kubectl get svc ${APP_NAME}-svc -n ${GKE_NAMESPACE} -o wide
            '
          '''
        }
      }
    }
  }

  post {
    always {
      echo "Build finished: ${currentBuild.currentResult}"
      // optional cleanup to save disk
      sh '''
        set +e
        docker system prune -f >/dev/null 2>&1 || true
      '''
    }
  }
}
