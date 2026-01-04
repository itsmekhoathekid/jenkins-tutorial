pipeline {
  agent any

  options {
    buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '14'))
    timestamps()
  }

  environment {
    DOCKERHUB_REPO    = 'chadkhoanguyen/house-price-prediction-api'
    DOCKERHUB_CRED_ID = 'dockerhub'

    PROJECT_ID   = 'tensile-axiom-482205-g8'
    REGION       = 'asia-southeast1'
    LOCATION     = 'global'

    POOL_ID      = 'jenkins-pool'
    PROVIDER_ID  = 'jenkins-oidc'
    SA_EMAIL     = 'terraform-jenkins@tensile-axiom-482205-g8.iam.gserviceaccount.com'

    GKE_CLUSTER_NAME = 'house-price-cluster'
    APP_NAME         = 'house-price-api'
    TF_VER           = '1.6.6'
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
          def tag = env.BUILD_NUMBER
          def image = "${DOCKERHUB_REPO}:${tag}"

          sh "docker build -t ${image} ."

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
              terraform init
              terraform apply -auto-approve
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
              export GOOGLE_APPLICATION_CREDENTIALS="$PWD/wif-creds.json"
              gcloud config set project ${PROJECT_ID}
              gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region ${REGION}

              kubectl set image deployment/${APP_NAME} \
                ${APP_NAME}=${DOCKERHUB_REPO}:${BUILD_NUMBER}

              kubectl rollout status deployment/${APP_NAME}
            '
          '''
        }
      }
    }
  }
}
