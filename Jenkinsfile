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

                                sleep(time: 30, unit: 'SECONDS')

                                // Get IPs into Groovy variables
                                MASTER_INTERNAL_IP = sh(script: "terraform output -raw master_internal_ip", returnStdout: true).trim()
                                WORKER1_INTERNAL_IP = sh(script: "terraform output -raw worker_1_internal_ip", returnStdout: true).trim()
                                WORKER2_INTERNAL_IP = sh(script: "terraform output -raw worker_2_internal_ip", returnStdout: true).trim()
                                MASTER_EXTERNAL_IP = sh(script: "terraform output -raw master_external_ip", returnStdout: true).trim()
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
                    sh """
                        gcloud auth activate-service-account --key-file=\$GCLOUD_AUTH
                        gcloud config set project bachelors-project-461620
                        gcloud config set compute/zone europe-central2-a

                        # Ensure /etc/rancher/rke2 exists before writing config.yaml
                        gcloud compute ssh mlops-master --command="sudo mkdir -p /etc/rancher/rke2"
                        gcloud compute ssh mlops-master --command="echo -e 'tls-san:\\n  - ${MASTER_EXTERNAL_IP}' | sudo tee /etc/rancher/rke2/config.yaml"

                        # Master install and restart for cert regeneration
                        gcloud compute ssh mlops-master --command="curl -sfL https://get.rke2.io | sudo sh - && sudo systemctl enable rke2-server && sudo systemctl restart rke2-server"

                        sleep 180

                        NODE_TOKEN=\$(gcloud compute ssh mlops-master --command='sudo cat /var/lib/rancher/rke2/server/node-token' --quiet)

                        gcloud compute ssh mlops-worker-1 --command="curl -sfL https://get.rke2.io | sudo sh - && sudo mkdir -p /etc/rancher/rke2 && echo -e 'server: https://${MASTER_INTERNAL_IP}:9345\\ntoken: \$NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"
                        gcloud compute ssh mlops-worker-2 --command="curl -sfL https://get.rke2.io | sudo sh - && sudo mkdir -p /etc/rancher/rke2 && echo -e 'server: https://${MASTER_INTERNAL_IP}:9345\\ntoken: \$NODE_TOKEN' | sudo tee /etc/rancher/rke2/config.yaml && sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"
                    """
                }
            }
        }

        stage('Export kubeconfig for Local Use') {
            when {
                expression { !params.DO_DESTROY }
            }
            steps {
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    sh """
                        gcloud auth activate-service-account --key-file=\$GCLOUD_AUTH
                        gcloud config set project bachelors-project-461620
                        gcloud config set compute/zone europe-central2-a

                        # 1. Copy rke2.yaml from master to /tmp and chown to current user
                        gcloud compute ssh mlops-master --command='sudo cp /etc/rancher/rke2/rke2.yaml /tmp/rke2.yaml && sudo chown \$(whoami) /tmp/rke2.yaml'
                        gcloud compute scp mlops-master:/tmp/rke2.yaml ./rke2-raw.yaml

                        # 2. Replace loopback address with the master external IP
                        sed 's/127.0.0.1/${MASTER_EXTERNAL_IP}/' ./rke2-raw.yaml > rke2-for-local.yaml

                        # 3. Print the resulting config
                        echo '---------------------'
                        echo 'Here is your kubeconfig for .kube/config:'
                        cat rke2-for-local.yaml
                        echo '---------------------'
                    """

                    // 4. Archive as artifact so you can download from Jenkins UI
                    archiveArtifacts artifacts: 'rke2-for-local.yaml', onlyIfSuccessful: true
                }
            }
        }

        stage('Configure kubectl context') {
            when { expression { !params.DO_DESTROY } }
            steps {
                sh '''
                mkdir -p ~/.kube
                cp rke2-for-local.yaml ~/.kube/config
                kubectl version
                kubectl get nodes -o wide
                '''
            }
            }

        stage('Remove rke2-ingress-nginx') {
            when { expression { !params.DO_DESTROY } }
            steps {
                sh '''
                gcloud compute ssh mlops-master --command="sudo mv /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx.yaml ~ || true"
                kubectl delete pod -n kube-system -l app.kubernetes.io/name=ingress-nginx || true
                helm uninstall rke2-ingress-nginx -n kube-system || true
                '''
            }
        }

        /* ----------  TRAEFIK  ---------- */
        stage('Install Traefik Ingress (NodePort)') {
            when { expression { !params.DO_DESTROY } }
            steps {
                sh '''
                helm repo add traefik https://helm.traefik.io/traefik || true
                helm repo update

                # CRDs once
                helm upgrade --install traefik-crds traefik/traefik-crds \
                    --namespace traefik --create-namespace \
                    --wait --timeout 120s

                # Main chart (skip CRDs)
                helm upgrade --install traefik traefik/traefik \
                    --namespace traefik --create-namespace \
                    --skip-crds \
                    -f services/traefik/values.yaml \
                    --wait --timeout 120s
                '''
            }
        }

        /* ----------  STORAGE  ---------- */
        stage('Install local-path provisioner (v0.0.31)') {
            when { expression { !params.DO_DESTROY } }
            steps {
                sh '''
                # Always pull the authoritative manifest
                kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml

                # Wait until the pod is ready
                kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s
                '''
            }
            }


        /* ----------  MLOps STACK  ---------- */
        stage('Deploy MLOps') {
            when { expression { !params.DO_DESTROY } }
            steps {
                withCredentials([
                usernamePassword(
                    credentialsId: 'minio-root-creds',
                    usernameVariable: 'MINIO_ROOT_USER',
                    passwordVariable: 'MINIO_ROOT_PASSWORD'
                ),
                string(
                    credentialsId: 'postgres-password',
                    variable: 'POSTGRES_PASSWORD'
                )
                ]) {
                sh """
                    # namespace & secrets
                    kubectl create namespace mlops || true
                    kubectl -n mlops create secret generic minio-credentials \
                    --from-literal=rootUser=\${MINIO_ROOT_USER} \
                    --from-literal=rootPassword=\${MINIO_ROOT_PASSWORD} || true

                    # Repos
                    helm repo add bitnami https://charts.bitnami.com/bitnami
                    helm repo update

                    # MinIO
                    helm upgrade --install minio bitnami/minio \
                    --namespace mlops \
                    -f services/minio/values.yaml
                    kubectl apply -f services/minio/ingressroute-minio.yaml

                    # PostgreSQL - Use postgres superuser with Jenkins password
                    helm upgrade --install postgresql bitnami/postgresql \
                    --namespace mlops \
                    -f services/postgresql/values.yaml \
                    --set auth.postgresPassword=\${POSTGRES_PASSWORD} \
                    --set auth.database=mlflow

                    # MLflow
                    kubectl apply -f services/mlflow/mlflow.yaml
                    kubectl apply -f services/mlflow/ingressroute-mlflow.yaml
                """
                }
            }
        }



        
    }
}
