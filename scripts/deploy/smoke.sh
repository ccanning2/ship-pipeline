#!/usr/bin/env bash
# Smoke test an environment. Usage: smoke.sh <base-url>
# Healthy: <base-url><HEALTH_PATH> answers 2xx and, when SMOKE_EXPECT is set, its body contains that text.
# HEALTH_PATH (default /) and SMOKE_EXPECT come from the environment, else from scripts/pipeline/pipeline.env, read
# as data (never run). SMOKE_RETRIES (10) and SMOKE_DELAY (6s) set the patience.
set -euo pipefail
url="${1:?usage: smoke.sh <base-url>}"; url="${url%/}"
cfg() { local b; b="$(dirname "$0")/../pipeline/base-ref.sh"; [ -f "$b" ] && bash "$b" --value "$1" 2>/dev/null || true; }
path="${HEALTH_PATH:-$(cfg HEALTH_PATH)}"; path="/${path#/}"
expect="${SMOKE_EXPECT:-$(cfg SMOKE_EXPECT)}"
for i in $(seq 1 "${SMOKE_RETRIES:-10}"); do
  if body="$(curl -fsS --max-time 5 "$url$path" 2>/dev/null)"; then
    case "$body" in *"$expect"*) echo "smoke: $url healthy"; exit 0;; esac
  fi
  [ "$i" = "${SMOKE_RETRIES:-10}" ] || sleep "${SMOKE_DELAY:-6}"
done
echo "smoke: $url$path not healthy${expect:+ (expected the response to contain: $expect)}" >&2
exit 1
