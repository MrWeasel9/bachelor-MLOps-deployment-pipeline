/**
 * Jenkinsfile – GCP bare-metal cluster
 * DO_DESTROY=true ⇒ only the Terraform-destroy stage runs
 */

properties([
  parameters([
    booleanParam(name: 'DO_DESTROY', defaultValue: false,
      description: 'Destroy ALL infrastructure (DANGER!)')
  ])
])

pipeline {
  agent any

  environment {
    PROJECT = 'bachelors-project-461620'
    ZONE    = 'europe-central2-a'
  }

  /**********************************************************/
  stages {

    /*────────────────────*/
    stage('Checkout') {
      steps { checkout scm }
    }

    /*────────────────────*/
    stage('Terraform init / plan / apply | destroy') {
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {

          dir('terraform') {

            sh 'terraform init -no-color'
            sh """
              terraform plan -no-color \
                -var="credentials_file=$GCLOUD_AUTH" \
                -var="project=${PROJECT}"
            """

            script {
              if (params.DO_DESTROY) {
                input message: 'REALLY destroy ALL resources?', ok: 'Yes, destroy!'
                sh """
                  terraform destroy -auto-approve -no-color \
                    -var="credentials_file=$GCLOUD_AUTH" \
                    -var="project=${PROJECT}"
                """
                return      // nothing else should run
              }

              /* ── apply ───────────────────────────*/
              input message: 'Apply infrastructure changes?', ok: 'Apply!'
              sh """
                terraform apply -auto-approve -no-color \
                  -var="credentials_file=$GCLOUD_AUTH" \
                  -var="project=${PROJECT}"
              """

              sleep 5   // give VMs a moment to be reachable

              /* capture outputs for later stages */
              env.MASTER_INTERNAL_IP = sh(
                script: "terraform output -raw master_internal_ip",
                returnStdout: true
              ).trim()
              env.MASTER_EXTERNAL_IP = sh(
                script: "terraform output -raw master_external_ip",
                returnStdout: true
              ).trim()
            }
          }
        }
      }
    }

        /*────────────────────*/
    /*────────────────────*/
    stage('Wait for master SSH') {
      when { expression { !params.DO_DESTROY } }   // skip on destroy
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {
          sh """
            set -e
            gcloud auth activate-service-account --key-file=$GCLOUD_AUTH
            gcloud config set project ${PROJECT}
            gcloud config set compute/zone ${ZONE}

            echo '⏳ Waiting up to 5 minutes for mlops-master (SSH:22) …'
            for i in {1..15}; do
              if gcloud compute ssh mlops-master --quiet --command='echo ok' >/dev/null 2>&1; then
                echo '✔ SSH is up'
                exit 0
              fi
              echo "Attempt \$i/15 failed — retrying in 20 s"
              sleep 20
            done
            echo '❌ Timeout: mlops-master still not accepting SSH after 5 minutes'
            exit 1
          """
        }
      }
    }



    /*────────────────────*/
    stage('Install / configure RKE2') {
      when { expression { !params.DO_DESTROY } }
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {
          sh """
            set -e
            gcloud auth activate-service-account --key-file=$GCLOUD_AUTH
            gcloud config set project ${PROJECT}
            gcloud config set compute/zone ${ZONE}

            # ── master ────────────────────────────────
            gcloud compute ssh mlops-master --command="\
              sudo mkdir -p /etc/rancher/rke2 && \
              echo -e 'tls-san:\\n  - ${env.MASTER_EXTERNAL_IP}' | \
              sudo tee /etc/rancher/rke2/config.yaml"

            gcloud compute ssh mlops-master --command="\
              curl -sfL https://get.rke2.io | sudo sh - && \
              sudo systemctl enable rke2-server && \
              sudo systemctl restart rke2-server"

            echo '⏳ Waiting 3 min for RKE2 control-plane…'
            sleep 180

            NODE_TOKEN=\$(gcloud compute ssh mlops-master \
              --command='sudo cat /var/lib/rancher/rke2/server/node-token' --quiet)

            # ── workers ───────────────────────────────
            for n in 1 2; do
              gcloud compute ssh mlops-worker-\${n} --command="\
                curl -sfL https://get.rke2.io | sudo sh - && \
                sudo mkdir -p /etc/rancher/rke2 && \
                echo -e 'server: https://${env.MASTER_INTERNAL_IP}:9345\\ntoken: \${NODE_TOKEN}' \
                  | sudo tee /etc/rancher/rke2/config.yaml && \
                sudo systemctl enable rke2-agent && \
                sudo systemctl start rke2-agent"
            done
          """
        }
      }
    }

    /*────────────────────*/
    stage('Fetch kubeconfig for Jenkins + artifact') {
      when { expression { !params.DO_DESTROY } }
      steps {
        withCredentials([file(credentialsId: 'gcp-terraform-key',
                              variable: 'GCLOUD_AUTH')]) {
          sh """
            gcloud auth activate-service-account --key-file=$GCLOUD_AUTH
            gcloud config set project ${PROJECT}
            gcloud config set compute/zone ${ZONE}

            gcloud compute ssh mlops-master --command='\
              sudo cp /etc/rancher/rke2/rke2.yaml /tmp/rke2.yaml && \
              sudo chown \$(whoami) /tmp/rke2.yaml'
            gcloud compute scp mlops-master:/tmp/rke2.yaml ./rke2-raw.yaml

            sed 's/127.0.0.1/${env.MASTER_EXTERNAL_IP}/' rke2-raw.yaml \
              > rke2-for-local.yaml
          """
          archiveArtifacts artifacts: 'rke2-for-local.yaml', fingerprint: true
        }
      }
    }

    /*────────────────────*/
    stage('Disable bundled nginx-ingress') {
      when { expression { !params.DO_DESTROY } }
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

    /*────────────────────*/
    stage('Install MetalLB + Traefik LoadBalancer') {
      when { expression { !params.DO_DESTROY } }
      steps {
        sh """
          # ── patch manifests with reserved static IP ───────────────
          sed 's/__MASTER_EXTERNAL_IP__/${env.MASTER_EXTERNAL_IP}/g' \
            services/metallb/ipaddresspool.yaml > ipaddresspool-patched.yaml

          sed 's/__MASTER_EXTERNAL_IP__/${env.MASTER_EXTERNAL_IP}/g' \
            services/traefik/values.yaml        > services/traefik/values.patched.yaml

          # ── MetalLB ───────────────────────────────────────────────
          helm repo add metallb https://metallb.github.io/metallb
          helm repo update
          helm upgrade --install metallb metallb/metallb \
            --namespace metallb-system --create-namespace \
            --wait --timeout 5m

          kubectl apply -f ipaddresspool-patched.yaml

          # ── Traefik – real LoadBalancer ──────────────────────────
          helm repo add traefik https://traefik.github.io/charts
          helm repo update
          helm upgrade --install traefik traefik/traefik \
            --namespace traefik --create-namespace \
            -f services/traefik/values.patched.yaml \
            --wait --timeout 5m
        """
      }
    }

  } // stages

  /**********************************************************/
  post {
    success {
      script {
        if (params.DO_DESTROY) {
          echo '✅ Infrastructure destroyed – nothing else to do.'
        } else {
          echo "✅ Cluster ready – Traefik dashboard: http://${env.MASTER_EXTERNAL_IP}"
        }
      }
    }
    failure { echo '❌ Build failed – check stage logs.' }
  }
}
