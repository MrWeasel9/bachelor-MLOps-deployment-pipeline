def MASTER_EXTERNAL_IP

properties([
    parameters([
        booleanParam(
            name: 'DO_DESTROY',
            defaultValue: false,
            description: 'Set to true to destroy all infrastructure (DANGER!)'
        ),
        booleanParam(
            name: 'SKIP_INFRA_INSTALL',
            defaultValue: false,
            description: 'Set to true to skip Terraform and RKE2 installation and go straight to Helm deployments.'
        ),
        booleanParam(
            name: 'DEPLOY_NEW_MODEL',
            defaultValue: false,
            description: 'Set to true to train, build, and deploy a new model.'
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
            when {
                expression { !params.SKIP_INFRA_INSTALL }
            }
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
                expression { !params.DO_DESTROY && !params.SKIP_INFRA_INSTALL }
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
                expression { !params.DO_DESTROY && !params.SKIP_INFRA_INSTALL }
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
            when { expression { !params.DO_DESTROY && !params.SKIP_INFRA_INSTALL } }
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
                # This removes RKE2's default NGINX ingress if it exists.
                gcloud compute ssh mlops-master --command="sudo mv /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx.yaml ~ || true"
                kubectl delete pod -n kube-system -l app.kubernetes.io/name=ingress-nginx || true
                helm uninstall rke2-ingress-nginx -n kube-system || true

                # These iptables rules seem specific to an RKE2 network setup, keep them.
                gcloud compute ssh mlops-master --command="sudo iptables -I INPUT -p udp --dport 8472 -j ACCEPT && sudo iptables -I FORWARD -p udp --dport 8472 -j ACCEPT"
                gcloud compute ssh mlops-worker-1 --command="sudo iptables -I INPUT -p udp --dport 8472 -j ACCEPT && sudo iptables -I FORWARD -p udp --dport 8472 -j ACCEPT"
                gcloud compute ssh mlops-worker-2 --command="sudo iptables -I INPUT -p udp --dport 8472 -j ACCEPT && sudo iptables -I FORWARD -p udp --dport 8472 -j ACCEPT"
                '''
            }
        }

        /* ----------  NGINX INGRESS  ---------- */
        // In your Jenkinsfile
        stage('Install NGINX Ingress Controller (NodePort)') {
            when { expression { !params.DO_DESTROY } }
            steps {
                sh '''
                helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
                helm repo update

                helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \\
                --namespace ingress-nginx --create-namespace \\
                --set controller.service.type=NodePort \\
                --set controller.service.nodePorts.http=32255 \\
                --set controller.service.nodePorts.https=30594 \\
                --set controller.metrics.enabled=true \\
                --wait
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

        
                /* ----------  MLOps STACK  ---------- */
        stage('Deploy MLOps') {
            when { expression { !params.DO_DESTROY } }
            steps {
                script {
                    // This ensures MASTER_EXTERNAL_IP is populated even if the Terraform stage was skipped
                    if (!MASTER_EXTERNAL_IP) {
                        echo "MASTER_EXTERNAL_IP not set, fetching from Terraform state..."
                        withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                            dir('terraform') {
                                MASTER_EXTERNAL_IP = sh(script: "terraform output -raw master_external_ip", returnStdout: true).trim()
                            }
                        }
                    }

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
                            set -e
                            set -x

                            # Namespace & Secrets
                            kubectl create namespace mlops || true
                            kubectl -n mlops create secret generic aws-s3-credentials \\
                            --from-literal=AWS_ACCESS_KEY_ID=\${MINIO_ROOT_USER} \\
                            --from-literal=AWS_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD} \\
                            --dry-run=client -o yaml | kubectl apply -f -

                            # Repos
                            helm repo add bitnami https://charts.bitnami.com/bitnami
                            helm repo update

                            # MinIO
                            helm upgrade --install minio bitnami/minio \\
                            --namespace mlops \\
                            --set auth.rootUser=\${MINIO_ROOT_USER} \\
                            --set auth.rootPassword=\${MINIO_ROOT_PASSWORD} \\
                            -f services/minio/values.yaml

                            # --- BLOCK FOR AUTOMATIC MINIO BUCKET CREATION ---
                            # Wait for MinIO pods to be ready before trying to configure it
                            echo "--- Waiting for MinIO to be ready ---"
                            kubectl -n mlops rollout status deployment/minio --timeout=300s
                            
                            # Clean up any previous failed job before applying.
                            echo "--- Deleting old setup job if it exists ---"
                            kubectl delete job minio-bucket-setup -n mlops --ignore-not-found=true

                            # Apply the setup job manifest from the file
                            echo "--- Applying MinIO bucket setup job ---"
                            kubectl apply -f services/minio/minio-bucket-setup.yaml

                            # Wait for the setup job to complete its job
                            echo "--- Waiting for MinIO bucket setup to complete ---"
                            kubectl wait --for=condition=complete job/minio-bucket-setup -n mlops --timeout=120s

                            # Clean up the setup job
                            echo "--- Cleaning up MinIO setup job ---"
                            kubectl delete job minio-bucket-setup -n mlops
                            # --- END OF BLOCK ---

                            # PostgreSQL
                            helm upgrade --install postgresql bitnami/postgresql \\
                            --namespace mlops \\
                            --set auth.postgresPassword=\${POSTGRES_PASSWORD} \\
                            --set auth.username=mlflow \\
                            --set auth.password=\${POSTGRES_PASSWORD} \\
                            --set auth.database=mlflow \\
                            -f services/postgresql/values.yaml

                            # MLflow Deployment & Service
                            kubectl apply -f services/mlflow/mlflow.yaml

                            # === APPLY ALL INGRESS CONFIGS ===
                            # Apply MLflow Ingress
                            kubectl apply -f services/mlflow/mlflow-ingress.yaml

                            # Apply MinIO Console Ingress
                            kubectl apply -f services/minio/minio-ingress.yaml
                        """
                    }
                }
            }
        }


        // --- THIS STAGE IS UPDATED WITH THE FIX ---
        stage('Install KServe and Dependencies') {
            when { expression { !params.DO_DESTROY && !params.SKIP_INFRA_DEPLOY } }
            steps {
                sh '''
                    set -e
                    set -x

                    echo "--- 1. Installing Istio ---"
                    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.22.1 TARGET_ARCH=x86_64 sh -
                    ./istio-1.22.1/bin/istioctl install --set profile=minimal -y
                    kubectl label namespace mlops istio-injection=enabled --overwrite=true

                    echo "--- 2. Installing Knative Serving ---"
                    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-crds.yaml
                    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-core.yaml
                    echo "--- Waiting for Knative Serving webhooks to be ready ---"
                    kubectl wait --for=condition=Available deployment --all --namespace=knative-serving --timeout=300s
                    kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.14.0/net-istio.yaml

                    echo "--- 3. Installing Cert-Manager ---"
                    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
                    echo "--- Waiting for Cert-Manager webhook to be ready ---"
                    kubectl wait --for=condition=Available deployment --all --namespace=cert-manager --timeout=300s

                    echo "--- 4. Installing KServe ---"
                    # Apply the core KServe manifest
                    kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml
                    
                    # THIS IS THE FIX: Wait for the KServe webhook to be ready before applying cluster resources.
                    echo "--- Waiting for KServe webhook to be ready ---"
                    kubectl wait --for=condition=Available deployment --all --namespace=kserve --timeout=300s

                    # Apply the cluster-wide resources
                    kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-cluster-resources.yaml

                    echo "--- KServe installation complete! ---"
                '''
            }
        }
        

        // --- THIS IS THE NEW AUTOMATED CI/CD STAGE FOR MODELS ---
        // --- THIS IS THE NEW AUTOMATED CI/CD STAGE FOR MODELS ---
        stage('Train, Build, and Deploy Model') {
            when { expression { params.DEPLOY_NEW_MODEL } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')
                ]) {
                    script {
                        def DOCKER_IMAGE_NAME = "${DOCKER_USERNAME}/mlflow-wine-classifier:v${env.BUILD_NUMBER}"
                        
                        // --- 1. Train Model ---
                        echo "--- Creating ConfigMap for training scripts ---"
                        sh "kubectl create configmap training-scripts --from-file=ml-models/wine-quality/hyperparameter_tuning.py -n mlops --dry-run=client -o yaml | kubectl apply -f -"
                        
                        echo "--- Starting model training job ---"
                        sh "kubectl delete job model-training-job -n mlops --ignore-not-found=true"
                        sh "kubectl apply -f services/training/trainer-job.yaml"
                        
                        // THIS IS THE FIX: This block now reliably catches failures and prints logs.
                        try {
                            // Use returnStatus: true to prevent the pipeline halting on a non-zero exit code.
                            def status = sh(script: "kubectl wait --for=condition=complete job/model-training-job -n mlops --timeout=300s", returnStatus: true)
                            if (status != 0) {
                                // If status is not 0, the wait command failed or timed out.
                                // We manually throw an error to trigger the catch block.
                                error "Training job failed to complete or timed out."
                            }
                        } catch (any) {
                            // This block will now reliably execute on failure.
                            echo "!!! Training job failed. Fetching logs for debugging. !!!"
                            def podName = sh(script: "kubectl get pods -n mlops -l job-name=model-training-job -o jsonpath='{.items[0].metadata.name}'", returnStdout: true).trim()
                            if (podName) {
                                // Print the logs from the failed pod.
                                sh "echo '--- LOGS FROM FAILED POD ${podName} ---'; kubectl logs ${podName} -n mlops -c trainer; echo '--- END OF LOGS ---'"
                            }
                            // Re-throw the error to ensure the build is marked as failed.
                            error "Training job failed to complete. See logs above for details."
                        }
                        
                        echo "--- Fetching new run ID from result file ---"
                        def trainingPodName = sh(script: "kubectl get pods -n mlops -l job-name=model-training-job -o jsonpath='{.items[0].metadata.name}'", returnStdout: true).trim()
                        sh "kubectl cp -n mlops ${trainingPodName}:/tmp/run_id.txt ./run_id.txt"
                        def newRunId = readFile('run_id.txt').trim()

                        if (!newRunId) {
                            error "Could not retrieve a valid Run ID from the training job's result file."
                        }
                        echo "Found new Run ID: ${newRunId}"

                        // --- 2. Build Image ---
                        // (The rest of the stage remains the same)
                        echo "--- Starting model builder job for Run ID: ${newRunId} ---"
                        def builderManifest = readFile('services/training/builder-job.yaml')
                        builderManifest = builderManifest.replace('<RUN_ID_PLACEHOLDER>', newRunId) 
                        builderManifest = builderManifest.replace('<DOCKER_IMAGE_NAME_PLACEHOLDER>', DOCKER_IMAGE_NAME)
                        builderManifest = builderManifest.replace('<DOCKER_USERNAME_PLACEHOLDER>', DOCKER_USERNAME)
                        builderManifest = builderManifest.replace('<DOCKER_PASSWORD_PLACEHOLDER>', DOCKER_PASSWORD)
                        
                        sh "kubectl delete job model-builder-job -n mlops --ignore-not-found=true"
                        writeFile(file: 'temp-builder-job.yaml', text: builderManifest)
                        sh "kubectl apply -f temp-builder-job.yaml"
                        sh "kubectl wait --for=condition=complete job/model-builder-job -n mlops --timeout=600s"
                        
                        // --- 3. Deploy to KServe ---
                        echo "--- Deploying image ${DOCKER_IMAGE_NAME} to KServe ---"
                        def inferenceManifest = readFile('services/kserve/inference-service.yaml')
                        inferenceManifest = inferenceManifest.replace('<DOCKER_IMAGE_NAME>', DOCKER_IMAGE_.replace('/', '\\/'))
                        
                        writeFile(file: 'temp-inference-service.yaml', text: inferenceManifest)
                        sh "kubectl apply -f temp-inference-service.yaml"

                        // --- 4. Cleanup ---
                        echo "--- Cleaning up temporary files and jobs ---"
                        sh "rm temp-builder-job.yaml temp-inference-service.yaml run_id.txt"
                        sh "kubectl delete configmap training-scripts -n mlops"
                        sh "kubectl delete job model-training-job -n mlops"
                        sh "kubectl delete job model-builder-job -n mlops"
                    }
                }
            }
        }
    }
}
