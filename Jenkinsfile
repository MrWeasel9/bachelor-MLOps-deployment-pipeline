properties([
    parameters([
        booleanParam(
            name: 'DO_DESTROY',
            defaultValue: false,
            description: 'Set to true to destroy all infrastructure (DANGER!)'
        )
    ])
])

pipeline {
    agent any

    environment {
        // You can add other env vars here if needed
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Repository checked out by Jenkins."
            }
        }

        stage('Terraform Init & Plan & Apply/Destroy') {
            steps {
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    dir('terraform') {
                        sh 'terraform init -no-color'
                        sh "terraform plan -no-color -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                        script {
                            if (params.DO_DESTROY) {
                                input message: "Are you REALLY sure you want to destroy ALL infrastructure? This cannot be undone!", ok: "Yes, destroy!"
                                sh "terraform destroy -no-color -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                            } else {
                                input message: "Deploy new/updated cluster? (This creates/destroys cloud resources!)", ok: "Yes, apply!"
                                sh "terraform apply -no-color -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""

                                // After apply, export the dynamic IPs as env vars for next stage
                                env.MASTER_IP = sh(script: "terraform output -raw master_internal_ip", returnStdout: true).trim()
                                env.WORKER1_IP = sh(script: "terraform output -raw worker_1_internal_ip", returnStdout: true).trim()
                                env.WORKER2_IP = sh(script: "terraform output -raw worker_2_internal_ip", returnStdout: true).trim()
                            }
                        }
                    }
                }
            }
        }

        stage('Configure RKE2') {
            when {
                expression { !params.DO_DESTROY }
            }
            steps {
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    sh '''
                        gcloud auth activate-service-account --key-file=$GCLOUD_AUTH
                        gcloud config set project bachelors-project-461620
                        gcloud config set compute/zone europe-central2-a

                        # Install RKE2 on master
                        gcloud compute ssh mlops-master --command="curl -sfL https://get.rke2.io | sudo sh - && sudo systemctl enable rke2-server && sudo systemctl start rke2-server"

                        sleep 60

                        NODE_TOKEN=$(gcloud compute ssh mlops-master --command='sudo cat /var/lib/rancher/rke2/server/node-token' --quiet)

                        # Use dynamic IPs from previous step
                        gcloud compute ssh mlops-worker-1 --command="curl -sfL https://get.rke2.io | sudo sh - && echo -e 'server: https://${MASTER_IP}:9345\\ntoken: $NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"

                        gcloud compute ssh mlops-worker-2 --command="curl -sfL https://get.rke2.io | sudo sh - && echo -e 'server: https://${MASTER_IP}:9345\\ntoken: $NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"
                    '''
                }
            }
        }
    }
}
