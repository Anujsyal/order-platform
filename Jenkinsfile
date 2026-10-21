// Application pipeline: build once, promote the same image dev -> staging -> prod.
//
// Jenkins never touches a cluster. It only (1) pushes an image and (2) commits
// the new tag to the GitOps repo. Argo CD in each cluster pulls the change.
//
// Required Jenkins setup (MANUAL-SETUP-GUIDE.md, A10-A11):
//   credentials : dockerhub-creds, github-creds (username + token)
//   global env  : DEV_APP_URL, STAGING_APP_URL, PROD_APP_URL
//   optional    : slack-webhook (Secret text) - pipeline notifications

// Best-effort: a missing webhook or Slack outage must never fail a deployment.
def notifySlack(String text) {
    try {
        withCredentials([string(credentialsId: 'slack-webhook', variable: 'SLACK_WEBHOOK')]) {
            writeFile file: '.slack.json', text: groovy.json.JsonOutput.toJson([text: text])
            sh 'curl -fsS -X POST -H "Content-Type: application/json" --data @.slack.json "$SLACK_WEBHOOK" > /dev/null'
        }
    } catch (err) {
        echo "Slack notification skipped: ${err.getMessage()}"
    }
}

def promoteAndVerify(String envName, String appUrl, int timeoutSeconds) {
    if (!appUrl) {
        error("${envName.toUpperCase()}_APP_URL is not set in Jenkins global properties")
    }
    withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
        sh "bash scripts/promote.sh ${envName} ${env.IMAGE_TAG}"
    }
    try {
        sh "bash scripts/verify-deployment.sh '${appUrl}' '${env.IMAGE_TAG}' ${timeoutSeconds}"
    } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException aborted) {
        // A person (or a timeout) aborted the build mid-verification. That says nothing
        // about the release, so don't revert it or report it as a failed verification.
        throw aborted
    } catch (err) {
        // Argo Rollouts has most likely already aborted the canary in-cluster.
        // Revert the Git commit too, so desired state == what is actually running.
        withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
            sh "bash scripts/rollback.sh ${envName}"
        }
        notifySlack(":rewind: *${envName}* rejected `${env.IMAGE_TAG}` - failed post-deploy verification, GitOps commit reverted. <${env.BUILD_URL}console|Logs>")
        error("${envName}: ${env.IMAGE_TAG} failed verification - GitOps change reverted")
    }
}

pipeline {
    agent any

    parameters {
        booleanParam(name: 'SIMULATE_BAD_RELEASE', defaultValue: false,
                description: 'Bake a 50% error rate into the image to watch the canary analysis roll it back')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        IMAGE_REPO  = 'docker.io/maverick8826/order-service'
        GITOPS_REPO = 'github.com/Anujsyal/order-platform-gitops.git'
        // Jenkins user IDs / groups allowed to approve promotions (comma separated)
        APPROVERS   = 'admin'
    }

    stages {
        stage('Init') {
            steps {
                script {
                    env.IMAGE_TAG  = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    env.FAULT_RATE = params.SIMULATE_BAD_RELEASE ? '0.5' : '0.0'
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
                    if (params.SIMULATE_BAD_RELEASE) {
                        currentBuild.description = 'SIMULATED BAD RELEASE'
                    }
                }
            }
        }

        stage('Build & Unit Test') {
            steps {
                dir('app') {
                    sh 'mvn -B -ntp clean verify'
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'app/target/surefire-reports/*.xml'
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                      --build-arg APP_VERSION="$IMAGE_TAG" \
                      --build-arg FAULT_ERROR_RATE="$FAULT_RATE" \
                      -t "$IMAGE_REPO:$IMAGE_TAG" app
                '''
            }
        }

        stage('Image Scan (Trivy)') {
            steps {
                // Report everything, fail only on fixable CRITICAL vulnerabilities.
                sh '''
                    trivy image --no-progress --severity HIGH,CRITICAL "$IMAGE_REPO:$IMAGE_TAG"
                    trivy image --no-progress --exit-code 1 --ignore-unfixed --severity CRITICAL "$IMAGE_REPO:$IMAGE_TAG"
                '''
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    // Throwaway DOCKER_CONFIG: the login never lands in ~jenkins/.docker, so a
                    // failed push can't leave stale credentials that break later base-image pulls.
                    sh '''
                        export DOCKER_CONFIG="$(mktemp -d)"
                        trap 'rm -rf "$DOCKER_CONFIG"' EXIT
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push "$IMAGE_REPO:$IMAGE_TAG"
                    '''
                }
            }
        }

        stage('Deploy: dev') {
            steps {
                script { promoteAndVerify('dev', env.DEV_APP_URL, 900) }
            }
        }

        stage('Approval: staging') {
            options { timeout(time: 4, unit: 'HOURS') }
            steps {
                script { notifySlack(":hourglass: `${env.IMAGE_TAG}` is healthy in dev and waiting for *staging* approval: <${env.BUILD_URL}input|Approve / Abort>") }
                input message: "Promote ${env.IMAGE_TAG} to STAGING?", ok: 'Promote', submitter: env.APPROVERS
            }
        }

        stage('Deploy: staging') {
            steps {
                script { promoteAndVerify('staging', env.STAGING_APP_URL, 900) }
            }
        }

        stage('Approval: prod') {
            options { timeout(time: 24, unit: 'HOURS') }
            steps {
                script { notifySlack(":hourglass: `${env.IMAGE_TAG}` is healthy in staging and waiting for *PRODUCTION* approval: <${env.BUILD_URL}input|Approve / Abort>") }
                input message: "Promote ${env.IMAGE_TAG} to PRODUCTION?", ok: 'Ship it', submitter: env.APPROVERS
            }
        }

        stage('Deploy: prod') {
            steps {
                script { promoteAndVerify('prod', env.PROD_APP_URL, 1800) }
            }
        }
    }

    post {
        success {
            script { notifySlack(":rocket: `${env.IMAGE_TAG}` is live in *prod* (canary passed). <${env.BUILD_URL}|Build #${env.BUILD_NUMBER}>") }
        }
        failure {
            script { notifySlack(":x: order-service build <${env.BUILD_URL}|#${env.BUILD_NUMBER}> failed (`${env.IMAGE_TAG ?: 'no tag'}`) - see the red stage.") }
        }
        aborted {
            script { notifySlack(":no_entry_sign: order-service build <${env.BUILD_URL}|#${env.BUILD_NUMBER}> was aborted / approval rejected.") }
        }
        always {
            sh 'docker rmi "$IMAGE_REPO:$IMAGE_TAG" || true'
            cleanWs()
        }
    }
}
