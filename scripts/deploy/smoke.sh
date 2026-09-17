#!/usr/bin/env bash
# Smoke test an environment. Usage: smoke.sh <base-url>
set -euo pipefail
url="${1:?usage: smoke.sh <base-url>}"
path="${HEALTH_PATH:-/actuator/health}"
for i in $(seq 1 "${SMOKE_RETRIES:-10}"); do
  body="$(curl -fsS --max-time 5 "$url$path" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"status":"UP"'; then echo "smoke: $url healthy"; exit 0; fi
  sleep "${SMOKE_DELAY:-6}"
done
echo "smoke: $url$path not healthy" >&2
exit 1
