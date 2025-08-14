pipeline {
    agent any
    tools {
        terraform 'terraform'
    }

    parameters {
        choice(
            name: 'action',
            choices: ['apply', 'destroy'],
            description: 'Select action to perform'
        )
    }

    environment {
        SLACKCHANNEL = 'vaultops'
        DOMAIN_NAME = 'alasoasiko.co.uk'
        VAULT_ADDRESS = 'https://vault.alasoasiko.co.uk'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        credentialsId: 'github-cred',
                        url: 'https://github.com/your-org/your-repo.git'
                    ]]
                ])
            }
        }

        // Apply path: Phase 2 - Vault Init Config
        stage('Phase 2 - Vault Init Config Apply') {
            when { expression { params.action == 'apply' } }
            steps {
                withCredentials([
                    string(credentialsId: 'db-static-username', variable: 'DB_STATIC_USERNAME'),
                    string(credentialsId: 'db-static-password', variable: 'DB_STATIC_PASSWORD'),
                    string(credentialsId: 'newrelic-api-key', variable: 'NEWRELIC_API_KEY'),
                    string(credentialsId: 'newrelic-user-id', variable: 'NEWRELIC_USER_ID'),
                    string(credentialsId: 'vault-token', variable: 'VAULT_TOKEN'),
                    string(credentialsId: 'sonarqube-db-username', variable: 'SONARQUBE_DB_USERNAME'),
                    string(credentialsId: 'sonarqube-db-password', variable: 'SONARQUBE_DB_PASSWORD'),
                ]) {
                    dir('vault-initial-config') {
                        sh """
                            terraform init
                            terraform apply \\
                              -var="db_static_password=${DB_STATIC_PASSWORD}" \\
                              -var="db_static_username=${DB_STATIC_USERNAME}" \\
                              -var="domain_name=${DOMAIN_NAME}" \\
                              -var="newrelic_api_key=${NEWRELIC_API_KEY}" \\
                              -var="newrelic_user_id=${NEWRELIC_USER_ID}" \\
                              -var="vault_address=${VAULT_ADDRESS}" \\
                              -var="vault_token=${VAULT_TOKEN}" \\
                              -var="sonarqube_db_username=${SONARQUBE_DB_USERNAME}" \\
                              -var="sonarqube_db_password=${SONARQUBE_DB_PASSWORD}" \\
                              -auto-approve
                        """
                    }
                }
            }
        }

        // Apply path: Phase 3 - Module Deployment
        stage('Phase 3 - Module Deployment') {
            when { expression { params.action == 'apply' } }
            steps {
                script {
                    env.SONARQUBE_ROLE_ID = sh(script: 'cd vault-initial-config && terraform output -raw sonarqube_role_id', returnStdout: true).trim()
                    env.SONARQUBE_SECRET_ID = sh(script: 'cd vault-initial-config && terraform output -raw sonarqube_secret_id', returnStdout: true).trim()
                    // env.VAULT_SERVER_PRIVATE_IP = sh(script: 'cd vault-initial-config && terraform output -raw vault_server_private_ip', returnStdout: true).trim()
                }
                withCredentials([
                    string(credentialsId: 'db-admin-username', variable: 'DB_ADMIN_USERNAME'),
                    string(credentialsId: 'db-admin-password', variable: 'DB_ADMIN_PASSWORD'),
                    string(credentialsId: 'vault_server_private_ip', variable: 'VAULT_SERVER_PRIVATE_IP')
                ]) {
                    dir('module') {
                        sh """
                            terraform init
                            terraform apply \\
                              -var="db_admin_username=${DB_ADMIN_USERNAME}" \\
                              -var="db_admin_password=${DB_ADMIN_PASSWORD}" \\
                              -var="vault_server_private_ip=${VAULT_SERVER_PRIVATE_IP}" \\
                              -var="sonarqube_role_id=${SONARQUBE_ROLE_ID}" \\
                              -var="sonarqube_secret_id=${SONARQUBE_SECRET_ID}" \\
                              -auto-approve
                        """
                    }
                }
            }
        }

        // Destroy path: Destroy Phase 3 first
        stage('Destroy - Phase 3 Modules') {
            when { expression { params.action == 'destroy' } }
            steps {
                script {
                    env.SONARQUBE_ROLE_ID = sh(script: 'cd vault-initial-config && terraform output -raw sonarqube_role_id', returnStdout: true).trim()
                    env.SONARQUBE_SECRET_ID = sh(script: 'cd vault-initial-config && terraform output -raw sonarqube_secret_id', returnStdout: true).trim()
                    env.VAULT_SERVER_PRIVATE_IP = sh(script: 'cd vault-initial-config && terraform output -raw vault_server_private_ip', returnStdout: true).trim()
                }
                withCredentials([
                    string(credentialsId: 'db-admin-username', variable: 'DB_ADMIN_USERNAME'),
                    string(credentialsId: 'db-admin-password', variable: 'DB_ADMIN_PASSWORD'),
                ]) {
                    dir('module') {
                        sh """
                            terraform init
                            terraform destroy \\
                              -var="db_admin_username=${DB_ADMIN_USERNAME}" \\
                              -var="db_admin_password=${DB_ADMIN_PASSWORD}" \\
                              -var="vault_server_private_ip=${VAULT_SERVER_PRIVATE_IP}" \\
                              -var="sonarqube_role_id=${SONARQUBE_ROLE_ID}" \\
                              -var="sonarqube_secret_id=${SONARQUBE_SECRET_ID}" \\
                              -auto-approve
                        """
                    }
                }
            }
        }

        // Then destroy Phase 2
        stage('Destroy - Phase 2 - Vault Init Config Infrastructure') {
            when { expression { params.action == 'destroy' } }
            steps {
                withCredentials([
                    string(credentialsId: 'db-static-username', variable: 'DB_STATIC_USERNAME'),
                    string(credentialsId: 'db-static-password', variable: 'DB_STATIC_PASSWORD'),
                    string(credentialsId: 'newrelic-api-key', variable: 'NEWRELIC_API_KEY'),
                    string(credentialsId: 'newrelic-user-id', variable: 'NEWRELIC_USER_ID'),
                    string(credentialsId: 'vault-token', variable: 'VAULT_TOKEN'),
                    string(credentialsId: 'sonarqube-db-username', variable: 'SONARQUBE_DB_USERNAME'),
                    string(credentialsId: 'sonarqube-db-password', variable: 'SONARQUBE_DB_PASSWORD'),
                ]) {
                    dir('vault-initial-config') {
                        sh """
                            terraform init
                            terraform destroy \\
                              -var="db_static_password=${DB_STATIC_PASSWORD}" \\
                              -var="db_static_username=${DB_STATIC_USERNAME}" \\
                              -var="domain_name=${DOMAIN_NAME}" \\
                              -var="newrelic_api_key=${NEWRELIC_API_KEY}" \\
                              -var="newrelic_user_id=${NEWRELIC_USER_ID}" \\
                              -var="vault_address=${VAULT_ADDRESS}" \\
                              -var="vault_token=${VAULT_TOKEN}" \\
                              -var="sonarqube_db_username=${SONARQUBE_DB_USERNAME}" \\
                              -var="sonarqube_db_password=${SONARQUBE_DB_PASSWORD}" \\
                              -auto-approve
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            slackSend(
                channel: SLACKCHANNEL,
                color: 'good',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' completed successfully. Check console output at ${env.BUILD_URL}."
            )
        }
        failure {
            slackSend(
                channel: SLACKCHANNEL,
                color: 'danger',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed. Check console output at ${env.BUILD_URL}."
            )
        }
    }
}
