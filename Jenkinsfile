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
        // (No need to set GOOGLE_APPLICATION_CREDENTIALS here; Terraform will read the JSON path directly)
    }

    stages {
        stage('Checkout') {
            steps {
                // Let Jenkins do the normal SCM checkout (credentials already set under job config)
                echo "Repository checked out"
            }
        }

        // Bind the GCP JSON key into a workspace file. 
        // “gcp-terraform-key” must match the credential ID you configured in Jenkins.
        stage('Terraform Init & Plan & Apply/Destroy') {
            steps {
                withCredentials([file(credentialsId: 'gcp-terraform-key', variable: 'GCLOUD_AUTH')]) {
                    dir('terraform') {
                        // Initialize Terraform
                        sh 'terraform init'

                        // Plan, passing the path to the key file
                        sh "terraform plan -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""

                        // Either Apply or Destroy, based on the boolean parameter
                        script {
                            if (params.DO_DESTROY) {
                                input message: "Are you REALLY sure you want to destroy ALL infra?", ok: "Yes, destroy!"
                                sh "terraform destroy -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                            } else {
                                input message: "Deploy new/updated cluster? (This creates/destroys cloud resources!)", ok: "Yes, apply!"
                                sh "terraform apply -auto-approve -var=\"credentials_file=${GCLOUD_AUTH}\" -var=\"project=bachelors-project-461620\""
                            }
                        }
                    }
                }
            }
        }
    }
}
