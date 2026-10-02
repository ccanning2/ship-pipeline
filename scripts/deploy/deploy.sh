#!/usr/bin/env bash
# Deploy an already-built image to a host with docker compose over SSH (starting template — engineer-owned).
# Usage: deploy.sh <dev|qa|staging|production> <sha>
# Env (from the CI environment's secrets/vars): IMAGE_REPO, DEPLOY_HOST, DEPLOY_PATH, DEPLOY_USER (default deploy),
#   DEPLOY_KNOWN_HOSTS: the host's known_hosts line(s), e.g. from `ssh-keyscan <host>` checked against the host's own
#   fingerprint. The host key is always verified: without DEPLOY_KNOWN_HOSTS only ~/.ssh/known_hosts is trusted.
#   DRY_RUN=1 prints the remote script instead of running it.
set -euo pipefail
env="${1:-}"; sha="${2:-}"
case "$env" in dev|qa|staging|production) ;; *) echo "usage: deploy.sh <dev|qa|staging|production> <sha>" >&2; exit 1;; esac
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "deploy: invalid sha '$sha'" >&2; exit 1; }
: "${IMAGE_REPO:?deploy: IMAGE_REPO not set (the image without its tag, e.g. ghcr.io/<owner>/<repo>)}"
: "${DEPLOY_PATH:?deploy: DEPLOY_PATH not set (the docker compose directory on the host for $env)}"

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
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes)
if [ -n "${DEPLOY_KNOWN_HOSTS:-}" ]; then
  kh="$(mktemp)"; trap 'rm -f "$kh"' EXIT; printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > "$kh"; ssh_opts+=(-o "UserKnownHostsFile=$kh")
fi
rc=0; ssh "${ssh_opts[@]}" "$DEPLOY_USER@$DEPLOY_HOST" "bash -s" <<<"$remote" || rc=$?
if [ "$rc" = 255 ] && [ -z "${DEPLOY_KNOWN_HOSTS:-}" ]; then
  echo "deploy: could not connect to $DEPLOY_HOST. If the host key was refused, set DEPLOY_KNOWN_HOSTS to its known_hosts line(s)" >&2
fi
[ "$rc" = 0 ] || exit "$rc"
echo "deploy: $env -> $IMAGE_REPO:$sha"
