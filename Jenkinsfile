/**
 * One-click build for your bare-metal GCP MLOps cluster
 * ◇ Terraform → VMs + /32 static route
 * ◇ RKE2      → master + 2 workers
 * ◇ MetalLB   → advertises the static IP
 * ◇ Traefik   → LoadBalancer Service bound to that IP
 */

properties([
  parameters([
    booleanParam(name: 'DO_DESTROY', defaultValue: false,
      description: 'Destroy ALL infrastructure (DANGER!)')
  ])
])

pipeline {
  agent any

  /***************************************************
   *  STAGES
   **************************************************/
  stages {

    /*───────────────────────────────*/
    stage('Checkout') {
      steps { checkout scm }
    }

    /*───────────────────────────────*/
    stage('Terraform init / plan / apply | destroy') {
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {
          dir('terraform') {

            sh 'terraform init -no-color'
            sh '''
              terraform plan -no-color \
                -var="credentials_file=${GCLOUD_AUTH}" \
                -var="project=bachelors-project-461620"
            '''

            script {
              if (params.DO_DESTROY) {
                input message: 'Really destroy ALL resources?', ok: 'Yes, nuke!'
                sh '''
                  terraform destroy -auto-approve -no-color \
                    -var="credentials_file=${GCLOUD_AUTH}" \
                    -var="project=bachelors-project-461620"
                '''
                currentBuild.result = 'SUCCESS'
                return          // nothing left to do
              }
            }

            input message: 'Apply infrastructure changes?', ok: 'Apply!'
            sh '''
              terraform apply -auto-approve -no-color \
                -var="credentials_file=${GCLOUD_AUTH}" \
                -var="project=bachelors-project-461620"
            '''

            /* save outputs for later stages */
            MASTER_INTERNAL_IP = sh(
              script: "terraform output -raw master_internal_ip",
              returnStdout: true
            ).trim()
            MASTER_EXTERNAL_IP = sh(
              script: "terraform output -raw master_external_ip",
              returnStdout: true
            ).trim()
          }
        }
      }
    }

    /*───────────────────────────────*/
    stage('Install / configure RKE2') {
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {

          sh """
            set -e
            gcloud auth activate-service-account --key-file=${GCLOUD_AUTH}
            gcloud config set project bachelors-project-461620
            gcloud config set compute/zone europe-central2-a

            # ── master ───────────────────────────────
            gcloud compute ssh mlops-master --command="\
              sudo mkdir -p /etc/rancher/rke2 && \
              echo -e 'tls-san:\\n  - ${MASTER_EXTERNAL_IP}' | \
              sudo tee /etc/rancher/rke2/config.yaml"

            gcloud compute ssh mlops-master --command="\
              curl -sfL https://get.rke2.io | sudo sh - && \
              sudo systemctl enable rke2-server && \
              sudo systemctl restart rke2-server"

            echo '⏳ waiting 3 minutes for RKE2 control-plane …'
            sleep 180

            NODE_TOKEN=\$(gcloud compute ssh mlops-master \
              --command='sudo cat /var/lib/rancher/rke2/server/node-token' --quiet)

            # ── workers ──────────────────────────────
            for n in 1 2; do
              gcloud compute ssh mlops-worker-\${n} --command="\
                curl -sfL https://get.rke2.io | sudo sh - && \
                sudo mkdir -p /etc/rancher/rke2 && \
                echo -e 'server: https://${MASTER_INTERNAL_IP}:9345\\ntoken: \${NODE_TOKEN}' \
                  | sudo tee /etc/rancher/rke2/config.yaml && \
                sudo systemctl enable rke2-agent && \
                sudo systemctl start rke2-agent"
            done
          """
        }
      }
    }

    /*───────────────────────────────*/
    stage('Fetch kubeconfig for Jenkins + artifact') {
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {
          sh """
            gcloud auth activate-service-account --key-file=${GCLOUD_AUTH}
            gcloud config set project bachelors-project-461620
            gcloud config set compute/zone europe-central2-a

            gcloud compute ssh mlops-master --command='\
              sudo cp /etc/rancher/rke2/rke2.yaml /tmp/rke2.yaml && \
              sudo chown \$(whoami) /tmp/rke2.yaml'
            gcloud compute scp mlops-master:/tmp/rke2.yaml ./rke2-raw.yaml

            sed 's/127.0.0.1/${MASTER_EXTERNAL_IP}/' rke2-raw.yaml \
              > rke2-for-local.yaml
          """

          archiveArtifacts artifacts: 'rke2-for-local.yaml', fingerprint: true

          sh '''
            mkdir -p ~/.kube
            cp rke2-for-local.yaml ~/.kube/config
            kubectl version --short
            kubectl get nodes -o wide
          '''
        }
      }
    }

    /*───────────────────────────────*/
    stage('Disable bundled nginx-ingress') {
      steps {
        sh '''
          set +e
          gcloud compute ssh mlops-master \
            --command="sudo mv /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx.yaml ~" \
            || true
          kubectl delete pod -n kube-system \
            -l app.kubernetes.io/name=ingress-nginx || true
          helm uninstall rke2-ingress-nginx -n kube-system || true
        '''
      }
    }

    /*───────────────────────────────*/
    stage('Install MetalLB + Traefik LoadBalancer') {
      steps {
        sh """
          # ── patch templates with the static external IP ─────────────
          sed 's/__MASTER_EXTERNAL_IP__/${MASTER_EXTERNAL_IP}/g' \
            services/metallb/ipaddresspool.yaml > ipaddresspool-patched.yaml

          sed 's/__MASTER_EXTERNAL_IP__/${MASTER_EXTERNAL_IP}/g' \
            services/traefik/values.yaml     > services/traefik/values.patched.yaml

          # ── MetalLB (CRDs + controller) ────────────────────────────
          helm repo add metallb https://metallb.github.io/metallb
          helm repo update
          helm upgrade --install metallb metallb/metallb \\
            --namespace metallb-system --create-namespace \\
            --wait --timeout 5m

          # ── IPAddressPool /32 for the VIP ──────────────────────────
          kubectl apply -f ipaddresspool-patched.yaml

          # ── Traefik – true LoadBalancer on the same VIP ────────────
          helm repo add traefik https://traefik.github.io/charts
          helm repo update
          helm upgrade --install traefik traefik/traefik \\
            --namespace traefik --create-namespace \\
            -f services/traefik/values.patched.yaml \\
            --wait --timeout 5m
        """
      }
    }

  } // stages

  /***************************************************
   *  POST
   **************************************************/
  post {
    success {
      echo "✅ Cluster ready – Traefik dashboard: http://${MASTER_EXTERNAL_IP}"
    }
    failure {
      echo "❌ Build failed – check stage logs."
    }
  }
}
