#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "deploy / rollback / smoke"
D="$REPO_SRC/scripts/deploy"
sha=0123456789abcdef0123456789abcdef01234567

out=$(bash "$D/deploy.sh" 2>&1); assert_exit "deploy: no args fails" 1 $? "$out"
out=$(bash "$D/deploy.sh" prod "$sha" 2>&1); assert_exit "deploy: unknown env fails" 1 $? "$out"
out=$(bash "$D/deploy.sh" qa 'abc;rm -rf /' 2>&1); assert_exit "deploy: rejects non-sha tag" 1 $? "$out"
out=$(DRY_RUN=1 IMAGE_REPO=ghcr.io/chris/reputabill bash "$D/deploy.sh" staging "$sha" 2>&1); assert_exit "deploy: dry run" 0 $? "$out"
assert_contains "deploy: uses exact image tag" "$out" "IMAGE=\"ghcr.io/chris/reputabill:$sha\""
assert_contains "deploy: env-specific path" "$out" "/opt/curate/staging"
assert_contains "deploy: records previous tag" "$out" ".previous_tag"
out=$(env -u DEPLOY_HOST bash "$D/deploy.sh" qa "$sha" 2>&1); assert_exit "deploy: requires DEPLOY_HOST" 1 $? "$out"

out=$(DRY_RUN=1 bash "$D/deploy.sh" dev "$sha" 2>&1); assert_exit "deploy: dev env accepted" 0 $? "$out"
assert_contains "deploy: dev path" "$out" "/opt/curate/dev"
out=$(bash "$D/rollback.sh" 2>&1); assert_exit "rollback: no args fails" 1 $? "$out"
out=$(DRY_RUN=1 bash "$D/rollback.sh" production 2>&1); assert_exit "rollback: dry run" 0 $? "$out"
assert_contains "rollback: uses previous tag" "$out" ".previous_tag"
assert_contains "rollback: production path" "$out" "/opt/curate/production"

# smoke against a local server
port=$((20000 + RANDOM % 20000)); tmp=$(mktemp -d); mkdir -p "$tmp/actuator"
printf '{"status":"UP"}' > "$tmp/actuator/health"
(cd "$tmp" && exec $PY -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) & srv=$!
sleep 1
out=$(SMOKE_RETRIES=3 SMOKE_DELAY=0 bash "$D/smoke.sh" "http://127.0.0.1:$port" 2>&1); assert_exit "smoke: healthy passes" 0 $? "$out"
printf '{"status":"DOWN"}' > "$tmp/actuator/health"
out=$(SMOKE_RETRIES=2 SMOKE_DELAY=0 bash "$D/smoke.sh" "http://127.0.0.1:$port" 2>&1); assert_exit "smoke: DOWN fails" 1 $? "$out"
kill $srv 2>/dev/null; wait $srv 2>/dev/null
out=$(SMOKE_RETRIES=1 SMOKE_DELAY=0 bash "$D/smoke.sh" "http://127.0.0.1:$port" 2>&1); assert_exit "smoke: unreachable fails" 1 $? "$out"
out=$(bash "$D/smoke.sh" 2>&1); assert_exit "smoke: no url fails" 1 $? "$out"

summary
