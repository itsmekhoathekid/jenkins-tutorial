pipeline {
  agent any

  options {
    buildDiscarder(logRotator(numToKeepStr: '5', daysToKeepStr: '5'))
    timestamps()
  }

  environment {
    REGISTRY = 'chadkhoanguyen/house-price-prediction-api'
    REGISTRY_CREDENTIAL = 'dockerhub'

    PROJECT_ID  = 'tensile-axiom-482205-g8'
    REGION      = 'asia-southeast1'
    CLUSTER     = 'tensile-axiom-482205-g8-new-gke'

    LOCATION    = 'global'
    POOL_ID     = 'jenkins-pool'
    PROVIDER_ID = 'jenkins-oidc'
    SA_EMAIL    = 'terraform-jenkins@tensile-axiom-482205-g8.iam.gserviceaccount.com'

    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
  }

  stages {

    stage('Test') {
        agent { docker { image 'python:3.8' } }
        steps {
            sh '''
            bash -lc '
                set -euo pipefail
                pip install -r requirements.txt
                pytest
            '
            '''
        }
    }


    stage('Build & Push') {
      steps {
        script {
          echo 'Building image...'
          def dockerImage = docker.build("${REGISTRY}:${BUILD_NUMBER}")

          echo 'Pushing image to DockerHub...'
          docker.withRegistry('https://index.docker.io/v1/', REGISTRY_CREDENTIAL) {
            dockerImage.push()
            dockerImage.push('latest')
          }
        }
      }
    }

    stage('Auth (WIF) + Terraform Apply') {
      agent { docker { image 'google/cloud-sdk:slim' } }
      steps {
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            set -euo pipefail

            apt-get update -y
            apt-get install -y curl unzip

            TF_VER="1.6.6"
            curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_amd64.zip"
            unzip -o /tmp/terraform.zip -d /usr/local/bin
            terraform -version
            gcloud --version

            PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

            cat > wif-creds.json <<EOF
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA_EMAIL}:generateAccessToken",
  "credential_source": {
    "file": "${ID_TOKEN_FILE}",
    "format": { "type": "text" }
  }
}
EOF

            gcloud auth login --brief --cred-file="$PWD/wif-creds.json"
            export GOOGLE_APPLICATION_CREDENTIALS="$PWD/wif-creds.json"

            terraform init
            terraform validate
            terraform plan -out=tfplan
            terraform apply -auto-approve tfplan
          '''
        }
      }
    }

    stage('Deploy to GKE (pull Docker Hub image)') {
      agent { docker { image 'google/cloud-sdk:slim' } }
      steps {
        withCredentials([file(credentialsId: 'jenkins-oidc-token-file', variable: 'ID_TOKEN_FILE')]) {
          sh '''
            set -euo pipefail

            apt-get update -y
            apt-get install -y curl

            # Install kubectl if missing
            if ! command -v kubectl >/dev/null 2>&1; then
              curl -fsSL -o /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/$(curl -fsSL https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x /usr/local/bin/kubectl
            fi
            kubectl version --client=true

            PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

            cat > wif-creds.json <<EOF
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA_EMAIL}:generateAccessToken",
  "credential_source": {
    "file": "${ID_TOKEN_FILE}",
    "format": { "type": "text" }
  }
}
EOF

            gcloud auth login --brief --cred-file="$PWD/wif-creds.json"
            gcloud config set project "$PROJECT_ID"
            gcloud config set compute/region "$REGION"

            gcloud container clusters get-credentials "$CLUSTER" --region "$REGION"

            IMAGE="${REGISTRY}:${BUILD_NUMBER}"

            mkdir -p /tmp/k8s
            sed "s|image: .*|image: ${IMAGE}|g" k8s/deployment.yaml > /tmp/k8s/deployment.yaml
            cp k8s/service.yaml /tmp/k8s/service.yaml

            kubectl apply -f /tmp/k8s
            kubectl rollout status deployment/house-price-api --timeout=180s

            kubectl get svc house-price-api-svc
          '''
        }
      }
    }
  }
}
