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

    stages {
        stage('Checkout') {
            steps {
                // Jenkins’s built-in “Declarative: Checkout SCM” already ran, so no git step is needed here.
                echo "Repository checked out by Jenkins."
            }
        }

        stage('Terraform Init & Plan & Apply/Destroy') {
            steps {
                // Bind the GCP JSON key into a workspace file named by ${GCLOUD_AUTH}
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    dir('terraform') {
                        // 1) Initialize Terraform (no color)
                        sh 'terraform init -no-color'

                        // 2) Plan, passing the path to the key file (no color)
                        sh "terraform plan -no-color -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""

                        // 3) Conditionally apply or destroy (no color)
                        script {
                            if (params.DO_DESTROY) {
                                input message: "Are you REALLY sure you want to destroy ALL infrastructure? This cannot be undone!", ok: "Yes, destroy!"
                                sh "terraform destroy -no-color -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                            } else {
                                input message: "Deploy new/updated cluster? (This creates/destroys cloud resources!)", ok: "Yes, apply!"
                                sh "terraform apply -no-color -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                            }
                        }
                    }
                }
            }
        }

        stage('Configure RKE2') {
            steps {
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    // Auth gcloud for this shell session
                    sh '''
                        gcloud auth activate-service-account --key-file=$GCLOUD_AUTH
                        gcloud config set project bachelors-project-461620
                        gcloud config set compute/zone europe-central2-a

                        # Install RKE2 on master
                        gcloud compute ssh mlops-master --command="curl -sfL https://get.rke2.io | sudo sh - && sudo systemctl enable rke2-server && sudo systemctl start rke2-server"

                        # Wait a bit for the server to become ready
                        sleep 60

                        # Fetch the node token from master for joining workers
                        NODE_TOKEN=$(gcloud compute ssh mlops-master --command='sudo cat /var/lib/rancher/rke2/server/node-token' --quiet)

                        # Install RKE2 and join cluster on worker 1
                        gcloud compute ssh mlops-worker-1 --command="curl -sfL https://get.rke2.io | sudo sh - && echo -e 'server: https://10.186.0.4:9345\\ntoken: $NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"

                        # Install RKE2 and join cluster on worker 2
                        gcloud compute ssh mlops-worker-2 --command="curl -sfL https://get.rke2.io | sudo sh - && echo -e 'server: https://10.186.0.4:9345\\ntoken: $NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"
                    '''
                }
            }
        }
    }
}
