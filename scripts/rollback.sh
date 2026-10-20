#!/usr/bin/env bash
# Revert the GitOps commit made by promote.sh for one environment, so Git
# (desired state) goes back to the last good version. Argo CD then syncs it.
#
# Usage: scripts/rollback.sh <dev|staging|prod>
# Env:   GITOPS_REPO, GIT_USER, GIT_TOKEN
set -euo pipefail

ENV_NAME="${1:?usage: rollback.sh <env>}"
: "${GITOPS_REPO:?}" "${GIT_USER:?}" "${GIT_TOKEN:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHA_FILE="$ROOT/.promote/${ENV_NAME}.sha"

if [ ! -s "$SHA_FILE" ]; then
  echo "No promotion commit recorded for ${ENV_NAME} - nothing to revert"
  exit 0
fi
SHA="$(cat "$SHA_FILE")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --depth 50 "https://${GIT_USER}:${GIT_TOKEN}@${GITOPS_REPO}" "$WORK/gitops"
cd "$WORK/gitops"

git -c user.name="jenkins" -c user.email="jenkins@order-platform.local" \
  revert --no-edit "$SHA"
git -c user.name="jenkins" -c user.email="jenkins@order-platform.local" \
  commit --amend -qm "rollback(${ENV_NAME}): revert ${SHA:0:7} - failed post-deploy verification"

pushed=false
for attempt in 1 2 3; do
  if git push --quiet origin HEAD:main; then pushed=true; break; fi
  git pull --quiet --rebase origin main
done
$pushed || { echo "could not push rollback commit"; exit 1; }

echo "Rolled back ${ENV_NAME}: reverted ${SHA}"
