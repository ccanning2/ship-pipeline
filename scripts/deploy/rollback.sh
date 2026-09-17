#!/usr/bin/env bash
# Roll an environment back to its previous image tag. Usage: rollback.sh <dev|qa|staging|production>
# Same env vars as deploy.sh. DRY_RUN=1 prints the remote script.
set -euo pipefail
env="${1:-}"
case "$env" in dev|qa|staging|production) ;; *) echo "usage: rollback.sh <dev|qa|staging|production>" >&2; exit 1;; esac
: "${IMAGE_REPO:=ghcr.io/OWNER/reputabill}"
: "${DEPLOY_PATH:=/opt/curate/$env}"
remote=$(cat <<REMOTE
set -euo pipefail
cd "$DEPLOY_PATH"
prev="\$(cat .previous_tag 2>/dev/null || true)"
[ -n "\$prev" ] || { echo "rollback: no previous tag recorded" >&2; exit 1; }
export IMAGE="$IMAGE_REPO:\$prev"
docker compose pull && docker compose up -d --remove-orphans
cp .current_tag .rolled_back_from 2>/dev/null || true
echo "\$prev" > .current_tag
echo "rollback: now on \$prev"
REMOTE
)
if [ "${DRY_RUN:-0}" = "1" ]; then printf '%s\n' "$remote"; exit 0; fi
: "${DEPLOY_HOST:?DEPLOY_HOST not set}"; : "${DEPLOY_USER:=deploy}"
ssh -o StrictHostKeyChecking=accept-new "$DEPLOY_USER@$DEPLOY_HOST" "bash -s" <<<"$remote"
