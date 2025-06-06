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
    }
}
