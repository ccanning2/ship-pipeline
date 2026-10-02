#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "deploy / rollback / smoke"
D="$REPO_SRC/scripts/deploy"
# A project installed with --no-deploy-envs has no deploy scripts to test.
[ -d "$D" ] || { echo "  (skipped: project has no deployable environments)"; summary; exit 0; }
sha=0123456789abcdef0123456789abcdef01234567
export IMAGE_REPO=ghcr.io/acme/app DEPLOY_PATH=/srv/app

out=$(bash "$D/deploy.sh" 2>&1); assert_exit "deploy: no args fails" 1 $? "$out"
out=$(bash "$D/deploy.sh" prod "$sha" 2>&1); assert_exit "deploy: unknown env fails" 1 $? "$out"
out=$(bash "$D/deploy.sh" qa 'abc;rm -rf /' 2>&1); assert_exit "deploy: rejects non-sha tag" 1 $? "$out"
out=$(DRY_RUN=1 bash "$D/deploy.sh" staging "$sha" 2>&1); assert_exit "deploy: dry run" 0 $? "$out"
assert_contains "deploy: uses exact image tag" "$out" "IMAGE=\"ghcr.io/acme/app:$sha\""
assert_contains "deploy: uses DEPLOY_PATH" "$out" 'cd "/srv/app"'
assert_contains "deploy: records previous tag" "$out" ".previous_tag"
out=$(env -u DEPLOY_HOST bash "$D/deploy.sh" qa "$sha" 2>&1); assert_exit "deploy: requires DEPLOY_HOST" 1 $? "$out"
# no project-specific defaults: the image and the path must be given
out=$(env -u IMAGE_REPO DRY_RUN=1 bash "$D/deploy.sh" dev "$sha" 2>&1); assert_exit "deploy: requires IMAGE_REPO" 1 $? "$out"
assert_contains "deploy: names IMAGE_REPO" "$out" "IMAGE_REPO not set"
out=$(env -u DEPLOY_PATH DRY_RUN=1 bash "$D/deploy.sh" dev "$sha" 2>&1); assert_exit "deploy: requires DEPLOY_PATH" 1 $? "$out"
assert_contains "deploy: names DEPLOY_PATH" "$out" "DEPLOY_PATH not set"
for f in deploy rollback smoke; do
  if grep -qiwE 'reputabill|curate|actuator' "$D/$f.sh"; then bad "$f.sh: project-agnostic"; else ok "$f.sh: project-agnostic"; fi
done

out=$(bash "$D/rollback.sh" 2>&1); assert_exit "rollback: no args fails" 1 $? "$out"
out=$(DRY_RUN=1 DEPLOY_PATH=/srv/app/production bash "$D/rollback.sh" production 2>&1); assert_exit "rollback: dry run" 0 $? "$out"
assert_contains "rollback: uses previous tag" "$out" ".previous_tag"
assert_contains "rollback: uses DEPLOY_PATH" "$out" "/srv/app/production"
out=$(env -u DEPLOY_PATH DRY_RUN=1 bash "$D/rollback.sh" production 2>&1); assert_exit "rollback: requires DEPLOY_PATH" 1 $? "$out"

# ssh: the host key is always verified. A fake ssh records its arguments and the known_hosts file it was given.
fb="$(mktemp -d)"; log="$fb/log"
cat > "$fb/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$SSH_LOG"
for a in "$@"; do case "$a" in UserKnownHostsFile=*) cat "${a#UserKnownHostsFile=}" > "$SSH_LOG.kh";; esac; done
cat >/dev/null; exit "${SSH_RC:-0}"
SSH
chmod +x "$fb/ssh"
for s in deploy rollback; do
  args=(qa); [ "$s" = deploy ] && args=(qa "$sha")
  rm -f "$log" "$log.kh"
  out=$(PATH="$fb:$PATH" SSH_LOG="$log" DEPLOY_HOST=h.example DEPLOY_KNOWN_HOSTS='h.example ssh-ed25519 AAAAkey' bash "$D/$s.sh" "${args[@]}" 2>&1)
  assert_exit "$s: deploys over ssh" 0 $? "$out"
  assert_contains "$s: strict host key checking" "$(cat "$log")" "StrictHostKeyChecking=yes"
  case "$(cat "$log")" in *accept-new*) bad "$s: never accepts a new host key";; *) ok "$s: never accepts a new host key";; esac
  assert_eq "$s: DEPLOY_KNOWN_HOSTS is the known_hosts file" "h.example ssh-ed25519 AAAAkey" "$(cat "$log.kh" 2>/dev/null)"
  rm -f "$log" "$log.kh"
  out=$(PATH="$fb:$PATH" SSH_LOG="$log" SSH_RC=255 DEPLOY_HOST=h.example bash "$D/$s.sh" "${args[@]}" 2>&1)
  assert_exit "$s: an unknown host is refused" 255 $? "$out"
  assert_contains "$s: StrictHostKeyChecking without DEPLOY_KNOWN_HOSTS" "$(cat "$log")" "StrictHostKeyChecking=yes"
  [ -e "$log.kh" ] && bad "$s: no known_hosts override without DEPLOY_KNOWN_HOSTS" || ok "$s: no known_hosts override without DEPLOY_KNOWN_HOSTS"
  assert_contains "$s: says how to trust the host" "$out" "set DEPLOY_KNOWN_HOSTS"
done

# smoke against a local server
port=$((20000 + RANDOM % 20000)); tmp=$(mktemp -d); mkdir -p "$tmp/health"
printf 'ok' > "$tmp/index.html"; printf '{"status":"UP"}' > "$tmp/health/index.html"
(cd "$tmp" && exec $PY -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) & srv=$!
sleep 1
u="http://127.0.0.1:$port"
out=$(SMOKE_RETRIES=3 SMOKE_DELAY=0 bash "$D/smoke.sh" "$u/" 2>&1); assert_exit "smoke: any 2xx at / passes by default" 0 $? "$out"
out=$(HEALTH_PATH=health/ SMOKE_EXPECT='"status":"UP"' SMOKE_RETRIES=3 SMOKE_DELAY=0 bash "$D/smoke.sh" "$u" 2>&1); assert_exit "smoke: HEALTH_PATH and SMOKE_EXPECT" 0 $? "$out"
out=$(HEALTH_PATH=/missing SMOKE_RETRIES=2 SMOKE_DELAY=0 bash "$D/smoke.sh" "$u" 2>&1); assert_exit "smoke: 404 fails" 1 $? "$out"
printf '{"status":"DOWN"}' > "$tmp/health/index.html"
out=$(HEALTH_PATH=/health/ SMOKE_EXPECT='"status":"UP"' SMOKE_RETRIES=2 SMOKE_DELAY=0 bash "$D/smoke.sh" "$u" 2>&1); assert_exit "smoke: unexpected body fails" 1 $? "$out"
assert_contains "smoke: names the expected text" "$out" 'expected the response to contain: "status":"UP"'
# HEALTH_PATH and SMOKE_EXPECT from pipeline.env, read as data
pj="$(mktemp -d)"; mkdir -p "$pj/scripts/deploy" "$pj/scripts/pipeline"
cp "$D/smoke.sh" "$pj/scripts/deploy/"; cp "$REPO_SRC/scripts/pipeline/base-ref.sh" "$pj/scripts/pipeline/"
printf 'HEALTH_PATH="/health/"   # comment\nSMOKE_EXPECT="DOWN"\nSMOKE_RETRIES=$(touch %s/ran)\n' "$pj" > "$pj/scripts/pipeline/pipeline.env"
out=$(env -u HEALTH_PATH -u SMOKE_EXPECT SMOKE_RETRIES=2 SMOKE_DELAY=0 bash "$pj/scripts/deploy/smoke.sh" "$u" 2>&1); assert_exit "smoke: reads HEALTH_PATH and SMOKE_EXPECT from pipeline.env" 0 $? "$out"
[ -e "$pj/ran" ] && bad "smoke: pipeline.env is never run" || ok "smoke: pipeline.env is never run"
kill $srv 2>/dev/null; wait $srv 2>/dev/null
out=$(SMOKE_RETRIES=1 SMOKE_DELAY=0 bash "$D/smoke.sh" "$u" 2>&1); assert_exit "smoke: unreachable fails" 1 $? "$out"
out=$(bash "$D/smoke.sh" 2>&1); assert_exit "smoke: no url fails" 1 $? "$out"

summary
