#!/usr/bin/env bash
# Roll an environment back to its previous image tag. Usage: rollback.sh <dev|qa|staging|production>
# Same env vars as deploy.sh (the host key is verified the same way). DRY_RUN=1 prints the remote script.
set -euo pipefail
env="${1:-}"
case "$env" in dev|qa|staging|production) ;; *) echo "usage: rollback.sh <dev|qa|staging|production>" >&2; exit 1;; esac
: "${IMAGE_REPO:?rollback: IMAGE_REPO not set (the image without its tag, e.g. ghcr.io/<owner>/<repo>)}"
: "${DEPLOY_PATH:?rollback: DEPLOY_PATH not set (the docker compose directory on the host for $env)}"
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
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes)
if [ -n "${DEPLOY_KNOWN_HOSTS:-}" ]; then
  kh="$(mktemp)"; trap 'rm -f "$kh"' EXIT; printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > "$kh"; ssh_opts+=(-o "UserKnownHostsFile=$kh")
fi
rc=0; ssh "${ssh_opts[@]}" "$DEPLOY_USER@$DEPLOY_HOST" "bash -s" <<<"$remote" || rc=$?
if [ "$rc" = 255 ] && [ -z "${DEPLOY_KNOWN_HOSTS:-}" ]; then
  echo "rollback: could not connect to $DEPLOY_HOST. If the host key was refused, set DEPLOY_KNOWN_HOSTS to its known_hosts line(s)" >&2
fi
exit "$rc"
