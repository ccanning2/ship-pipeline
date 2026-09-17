#!/usr/bin/env bash
# Deploy an already-built image to a Hetzner host with docker compose (starting template — engineer-owned).
# Usage: deploy.sh <dev|qa|staging|production> <sha>
# Env (from GitHub environment secrets/vars): DEPLOY_HOST, DEPLOY_USER, DEPLOY_PATH, IMAGE_REPO
#   DRY_RUN=1 prints the remote script instead of running it.
set -euo pipefail
env="${1:-}"; sha="${2:-}"
case "$env" in dev|qa|staging|production) ;; *) echo "usage: deploy.sh <dev|qa|staging|production> <sha>" >&2; exit 1;; esac
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "deploy: invalid sha '$sha'" >&2; exit 1; }
: "${IMAGE_REPO:=ghcr.io/OWNER/reputabill}"
: "${DEPLOY_PATH:=/opt/curate/$env}"

remote=$(cat <<REMOTE
set -euo pipefail
cd "$DEPLOY_PATH"
current="\$(cat .current_tag 2>/dev/null || true)"
[ -n "\$current" ] && echo "\$current" > .previous_tag
export IMAGE="$IMAGE_REPO:$sha"
docker compose pull
docker compose up -d --remove-orphans
echo "$sha" > .current_tag
docker image prune -f >/dev/null
REMOTE
)

if [ "${DRY_RUN:-0}" = "1" ]; then printf '%s\n' "$remote"; exit 0; fi
: "${DEPLOY_HOST:?DEPLOY_HOST not set}"; : "${DEPLOY_USER:=deploy}"
ssh -o StrictHostKeyChecking=accept-new "$DEPLOY_USER@$DEPLOY_HOST" "bash -s" <<<"$remote"
echo "deploy: $env -> $IMAGE_REPO:$sha"
