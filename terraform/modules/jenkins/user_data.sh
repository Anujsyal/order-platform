#!/bin/bash
# Installs everything the Jenkins pipelines need. This is the automated version
# of Part A (A5-A8) of MANUAL-SETUP-GUIDE.md. Log: /var/log/user-data.log
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

KUSTOMIZE_VERSION=5.4.3
CONFTEST_VERSION=0.56.0

# 2 GB swap - Maven builds on a 4 GB box otherwise get OOM-killed.
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

apt-get update -y
apt-get install -y ca-certificates curl gnupg unzip git jq fontconfig openjdk-21-jdk maven
install -d -m 0755 /etc/apt/keyrings

# --- Jenkins (LTS) ---
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /etc/apt/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

# --- Docker CE ---
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

# --- Terraform ---
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
  > /etc/apt/sources.list.d/hashicorp.list

# --- Trivy ---
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /etc/apt/keyrings/trivy.gpg
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  > /etc/apt/sources.list.d/trivy.list

apt-get update -y
apt-get install -y jenkins docker-ce docker-ce-cli containerd.io docker-buildx-plugin terraform trivy

# --- kustomize + conftest (single binaries) ---
curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin kustomize
curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" \
  | tar -xz -C /usr/local/bin conftest

# --- Let Jenkins (and the ubuntu login user) talk to the Docker daemon ---
# /var/run/docker.sock is root:docker 660, so the user must be in the docker group.
# Group membership is read when a process starts, hence the Jenkins restart.
usermod -aG docker jenkins
usermod -aG docker ubuntu

systemctl enable --now docker
systemctl enable jenkins
systemctl restart jenkins

# --- CloudWatch agent: memory/disk metrics + logs (Jenkins logs land in syslog via journald) ---
curl -fsSL -o /tmp/amazon-cloudwatch-agent.deb \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWEOF'
{
  "agent": { "metrics_collection_interval": 60, "run_as_user": "root" },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "metrics_collected": {
      "mem":  { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"], "drop_device": true }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/user-data.log", "log_group_name": "__LOG_GROUP__", "log_stream_name": "{instance_id}/user-data" },
          { "file_path": "/var/log/syslog", "log_group_name": "__LOG_GROUP__", "log_stream_name": "{instance_id}/syslog" }
        ]
      }
    }
  }
}
CWEOF
sed -i "s|__LOG_GROUP__|${CW_LOG_GROUP:-/order-platform-shared/jenkins}|g" /opt/aws/amazon-cloudwatch-agent/etc/config.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "Bootstrap complete. Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || true
