pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '5', daysToKeepStr: '5'))
        timestamps()
    }

    environment {
        REGISTRY = 'chadkhoanguyen/house-price-prediction-api'
        REGISTRY_CREDENTIAL = 'dockerhub'
    }

    stages {

        stage('Test') {
            agent {
                docker {
                    image 'python:3.8'
                }
            }
            steps {
                echo 'Testing model correctness..'
                sh '''
                    pip install -r requirements.txt
                    pytest
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

        stage('Deploy') {
            steps {
                echo 'Deploying application...'
                echo 'You can add docker run / kubectl here'
            }
        }
    }
}
