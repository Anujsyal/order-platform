#!/usr/bin/env bash
# Copy an environment's admin kubeconfig to your laptop and point it at the
# master's public IP (6443 is open only to your admin CIDR).
#
# Usage: scripts/get-kubeconfig.sh <dev|staging|prod> <path-to-key.pem>
# Then:  export KUBECONFIG=~/.kube/order-platform-<env>
set -euo pipefail

ENV_NAME="${1:?usage: get-kubeconfig.sh <env> <key.pem>}"
KEY="${2:?usage: get-kubeconfig.sh <env> <key.pem>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/terraform/stacks/cluster"
terraform init -input=false -reconfigure \
  -backend-config=../../backend.hcl \
  -backend-config="key=cluster/${ENV_NAME}/terraform.tfstate" > /dev/null
IP="$(terraform output -raw master_public_ip)"

OUT="$HOME/.kube/order-platform-${ENV_NAME}"
mkdir -p "$HOME/.kube"
scp -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@${IP}:/home/ubuntu/.kube/config" "$OUT"
sed -i "s|server: https://.*:6443|server: https://${IP}:6443|" "$OUT"

echo "Saved $OUT"
echo "Run: export KUBECONFIG=$OUT && kubectl get nodes"
