#!/usr/bin/env bash
# Promote an image tag to one environment by committing to the GitOps repo.
# Argo CD in that environment's cluster notices the commit and rolls it out.
#
# Usage: scripts/promote.sh <dev|staging|prod> <image-tag>
# Env:   GITOPS_REPO (github.com/<user>/<repo>.git), IMAGE_REPO, GIT_USER, GIT_TOKEN
set -euo pipefail

ENV_NAME="${1:?usage: promote.sh <env> <tag>}"
TAG="${2:?usage: promote.sh <env> <tag>}"
: "${GITOPS_REPO:?}" "${IMAGE_REPO:?}" "${GIT_USER:?}" "${GIT_TOKEN:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --depth 20 "https://${GIT_USER}:${GIT_TOKEN}@${GITOPS_REPO}" "$WORK/gitops"
cd "$WORK/gitops"

OVERLAY="apps/order-service/overlays/${ENV_NAME}"
(cd "$OVERLAY" && kustomize edit set image "order-service=${IMAGE_REPO}:${TAG}")

# Policy gate: render exactly what Argo CD will apply and test it first.
kustomize build "$OVERLAY" > "$WORK/rendered.yaml"
conftest test "$WORK/rendered.yaml" --policy "$ROOT/policies/kubernetes"

mkdir -p "$ROOT/.promote"
if git diff --quiet; then
  echo "${ENV_NAME} is already at ${TAG} - nothing to commit"
  : > "$ROOT/.promote/${ENV_NAME}.sha"
  exit 0
fi

git -c user.name="jenkins" -c user.email="jenkins@order-platform.local" \
  commit -qam "promote(${ENV_NAME}): order-service ${TAG}"

pushed=false
for attempt in 1 2 3; do
  if git push --quiet origin HEAD:main; then pushed=true; break; fi
  echo "push rejected (attempt ${attempt}), rebasing on latest main"
  git pull --quiet --rebase origin main
done
$pushed || { echo "could not push to GitOps repo"; exit 1; }

# Remembered so rollback.sh can revert exactly this commit.
git rev-parse HEAD > "$ROOT/.promote/${ENV_NAME}.sha"
echo "Promoted ${ENV_NAME} -> ${TAG} ($(cat "$ROOT/.promote/${ENV_NAME}.sha"))"
