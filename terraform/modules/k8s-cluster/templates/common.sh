# ---- Common node setup: kernel prereqs, containerd, kubeadm/kubelet/kubectl ----
# Inserted verbatim into master/worker user-data (not template-rendered).
# Expects K8S_MINOR to be set (e.g. v1.31). Manual equivalent: guide section A13.
export DEBIAN_FRONTEND=noninteractive

# kubelet refuses to run with swap on
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg containerd netcat-openbsd

# containerd must use the systemd cgroup driver, same as kubelet
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# IMDSv2 lookups
IMDS_TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 || true)
# ---- end common setup ----

# ---- CloudWatch agent: memory/disk metrics + logs shipped off-host ----
# Expects CW_LOG_GROUP (e.g. /order-platform-dev). Needs the node IAM role.
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
          { "file_path": "/var/log/k8s-bootstrap.log", "log_group_name": "__LOG_GROUP__/nodes", "log_stream_name": "{instance_id}/bootstrap" },
          { "file_path": "/var/log/syslog", "log_group_name": "__LOG_GROUP__/nodes", "log_stream_name": "{instance_id}/syslog" },
          { "file_path": "/var/log/kubernetes/audit/audit.log", "log_group_name": "__LOG_GROUP__/k8s-audit", "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
CWEOF
sed -i "s|__LOG_GROUP__|${CW_LOG_GROUP}|g" /opt/aws/amazon-cloudwatch-agent/etc/config.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
# ---- end CloudWatch agent ----
