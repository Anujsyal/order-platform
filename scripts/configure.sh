#!/usr/bin/env bash
# One-time: replace the YOUR_* placeholders in code/config with your values.
# Run from Git Bash on Windows (or any bash):
#
#   scripts/configure.sh --github-user anuj --dockerhub-user anuj \
#       --state-bucket anuj-order-platform-tfstate --key-name order-platform-key \
#       --alert-email you@example.com
#
# --admin-cidr is optional; defaults to your current public IP /32.
set -euo pipefail

usage() { sed -n '2,10p' "$0"; exit 1; }

GITHUB_USER="" DOCKERHUB_USER="" STATE_BUCKET="" KEY_NAME="" ADMIN_CIDR="" ALERT_EMAIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --github-user)    GITHUB_USER="$2"; shift 2 ;;
    --dockerhub-user) DOCKERHUB_USER="$2"; shift 2 ;;
    --state-bucket)   STATE_BUCKET="$2"; shift 2 ;;
    --key-name)       KEY_NAME="$2"; shift 2 ;;
    --admin-cidr)     ADMIN_CIDR="$2"; shift 2 ;;
    --alert-email)    ALERT_EMAIL="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$GITHUB_USER" ] && [ -n "$DOCKERHUB_USER" ] && [ -n "$STATE_BUCKET" ] && [ -n "$KEY_NAME" ] && [ -n "$ALERT_EMAIL" ] || usage

if [ -z "$ADMIN_CIDR" ]; then
  ADMIN_CIDR="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32"
  echo "Detected admin CIDR: $ADMIN_CIDR"
fi

DOCKERHUB_USER="$(echo "$DOCKERHUB_USER" | tr '[:upper:]' '[:lower:]')"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

files=$(grep -rlE 'YOUR_(GITHUB_USER|DOCKERHUB_USER|TF_STATE_BUCKET|KEY_PAIR_NAME|ADMIN_CIDR|ALERT_EMAIL)' "$ROOT" \
  --exclude-dir=.git --exclude-dir=target --exclude-dir=.terraform \
  --exclude=configure.sh --exclude='*.md' || true)

for f in $files; do
  sed -i \
    -e "s|YOUR_GITHUB_USER|${GITHUB_USER}|g" \
    -e "s|YOUR_DOCKERHUB_USER|${DOCKERHUB_USER}|g" \
    -e "s|YOUR_TF_STATE_BUCKET|${STATE_BUCKET}|g" \
    -e "s|YOUR_KEY_PAIR_NAME|${KEY_NAME}|g" \
    -e "s|YOUR_ADMIN_CIDR|${ADMIN_CIDR}|g" \
    -e "s|YOUR_ALERT_EMAIL|${ALERT_EMAIL}|g" \
    "$f"
  echo "updated ${f#"$ROOT"/}"
done

echo "Done. Review with: git diff"
