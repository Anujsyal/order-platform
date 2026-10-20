#!/bin/bash
# Control-plane bootstrap. Log: /var/log/k8s-bootstrap.log
set -euxo pipefail
exec > >(tee /var/log/k8s-bootstrap.log) 2>&1

K8S_MINOR="${k8s_minor}"
CW_LOG_GROUP="${log_group}"
${common_setup}

# ---- Pre-seed the cluster CA (kubeadm reuses an existing CA) ----
mkdir -p /etc/kubernetes/pki
cat > /etc/kubernetes/pki/ca.crt <<'EOF'
${ca_crt}
EOF
cat > /etc/kubernetes/pki/ca.key <<'EOF'
${ca_key}
EOF
chmod 600 /etc/kubernetes/pki/ca.key

# ---- API server audit policy (hardening) ----
mkdir -p /var/log/kubernetes/audit
cat > /etc/kubernetes/audit-policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: ["RequestReceived"]
rules:
  - level: None
    nonResourceURLs: ["/healthz*", "/readyz*", "/livez*", "/version", "/metrics"]
  - level: None
    resources:
      - group: ""
        resources: ["events"]
  - level: Metadata
EOF

cat > /root/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
bootstrapTokens:
  - token: "${bootstrap_token}"
    ttl: "24h0m0s"
localAPIEndpoint:
  advertiseAddress: "$PRIVATE_IP"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: "${environment}"
networking:
  podSubnet: "${pod_cidr}"
apiServer:
  certSANs: ["$PRIVATE_IP", "$PUBLIC_IP"]
  extraArgs:
    - name: audit-policy-file
      value: /etc/kubernetes/audit-policy.yaml
    - name: audit-log-path
      value: /var/log/kubernetes/audit/audit.log
    - name: audit-log-maxage
      value: "7"
    - name: audit-log-maxbackup
      value: "5"
    - name: audit-log-maxsize
      value: "100"
    - name: profiling
      value: "false"
  extraVolumes:
    - name: audit-policy
      hostPath: /etc/kubernetes/audit-policy.yaml
      mountPath: /etc/kubernetes/audit-policy.yaml
      readOnly: true
      pathType: File
    - name: audit-logs
      hostPath: /var/log/kubernetes/audit
      mountPath: /var/log/kubernetes/audit
      readOnly: false
      pathType: DirectoryOrCreate
controllerManager:
  extraArgs:
    - name: profiling
      value: "false"
scheduler:
  extraArgs:
    - name: profiling
      value: "false"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
readOnlyPort: 0
rotateCertificates: true
EOF

kubeadm init --config /root/kubeadm-config.yaml

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# ---- Pod network (Calico supports NetworkPolicy) ----
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/calico.yaml"
kubectl wait --for=condition=Ready "node/$(hostname)" --timeout=600s

# ---- Monitoring secrets (kept out of Git) ----
# Grafana gets a random admin password; Alertmanager gets a placeholder Slack
# webhook. Replace it with the real one (MANUAL-SETUP-GUIDE.md section G2).
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1 || \
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl -n monitoring get secret alertmanager-slack >/dev/null 2>&1 || \
  kubectl -n monitoring create secret generic alertmanager-slack \
    --from-literal=webhook-url="https://hooks.slack.com/services/REPLACE/ME/PLEASE"

%{ if gitops_repo_url != "" ~}
# ---- Argo CD + root "app of apps" for this environment ----
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=300s

# Argo CD UI on https://<any-node-ip>:30443
kubectl -n argocd patch svc argocd-server \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30443,"protocol":"TCP"}]}}'

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "${gitops_repo_url}"
    targetRevision: main
    path: "clusters/${environment}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 10m
EOF
%{ endif ~}

echo "Control plane bootstrap complete"
