#!/usr/bin/env bash
# Propose the next semver tag from the latest vX.Y.Z tag and the ticket type.
# Usage: next-version.sh <TICKET> [major|minor|patch]   (default: feature→minor, else patch)
set -euo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"; bump="${2:-}"
root="$(git rev-parse --show-toplevel)"
if [ -z "$bump" ]; then
  type="$(grep -m1 -E '^Type:' "$root/docs/pipeline/$ticket/product.md" 2>/dev/null | sed -E 's/^Type:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)"
  case "$type" in feature) bump=minor;; *) bump=patch;; esac
fi
latest="$(git -C "$root" tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
[ -n "$latest" ] || latest="0.0.0"
IFS=. read -r M m p <<<"$latest"
case "$bump" in major) M=$((M+1)); m=0; p=0;; minor) m=$((m+1)); p=0;; patch) p=$((p+1));; *) echo "bump must be major|minor|patch" >&2; exit 1;; esac
echo "v$M.$m.$p"
