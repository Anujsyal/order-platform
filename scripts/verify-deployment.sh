#!/usr/bin/env bash
# Wait until an environment serves the expected version, healthily.
# Passes only after REQUIRED_STREAK consecutive good responses, so a canary
# that's only partly rolled out (or was aborted) never counts as success.
#
# Usage: scripts/verify-deployment.sh <base-url> <expected-tag> [timeout-seconds]
set -uo pipefail

BASE_URL="${1:?usage: verify-deployment.sh <url> <tag> [timeout]}"
EXPECTED="${2:?usage: verify-deployment.sh <url> <tag> [timeout]}"
TIMEOUT="${3:-900}"
REQUIRED_STREAK=10

deadline=$(( $(date +%s) + TIMEOUT ))
streak=0
last=""

echo "Waiting up to ${TIMEOUT}s for ${BASE_URL} to serve ${EXPECTED}"
while [ "$(date +%s)" -lt "$deadline" ]; do
  version=$(curl -fsS --max-time 5 "${BASE_URL}/api/version" 2>/dev/null | jq -r '.version' 2>/dev/null)
  orders=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/api/orders" 2>/dev/null)

  if [ "$version" = "$EXPECTED" ] && [ "$orders" = "200" ]; then
    streak=$((streak + 1))
    if [ "$streak" -ge "$REQUIRED_STREAK" ]; then
      echo "OK: ${EXPECTED} healthy (${REQUIRED_STREAK} consecutive checks)"
      exit 0
    fi
    sleep 1
  else
    streak=0
    status="version=${version:-unreachable} orders=${orders:-000}"
    if [ "$status" != "$last" ]; then
      echo "$(date +%T) not ready: ${status}"
      last="$status"
    fi
    sleep 5
  fi
done

echo "FAILED: ${EXPECTED} did not become healthy within ${TIMEOUT}s"
exit 1
