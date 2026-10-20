#!/bin/bash
# Worker bootstrap. Log: /var/log/k8s-bootstrap.log
set -euxo pipefail
exec > >(tee /var/log/k8s-bootstrap.log) 2>&1

K8S_MINOR="${k8s_minor}"
CW_LOG_GROUP="${log_group}"
${common_setup}

# Pin the cluster CA: hash of its public key, computed from the cert Terraform generated.
cat > /root/cluster-ca.crt <<'EOF'
${ca_crt}
EOF
CA_HASH=$(openssl x509 -pubkey -noout -in /root/cluster-ca.crt \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -hex | sed 's/^.* //')

# Wait for the API server, then keep trying until the bootstrap token exists.
until nc -z "${master_ip}" 6443; do
  echo "waiting for control plane at ${master_ip}:6443"
  sleep 15
done

until kubeadm join "${master_ip}:6443" \
    --token "${bootstrap_token}" \
    --discovery-token-ca-cert-hash "sha256:$CA_HASH"; do
  echo "join failed, retrying in 20s"
  kubeadm reset -f
  sleep 20
done

echo "Worker joined"
