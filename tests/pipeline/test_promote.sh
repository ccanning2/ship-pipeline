#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "promote.sh"

export PIPELINE_NO_PUSH=1
LOG="$(mktemp)"
fake_deploy() { printf 'deploy %s %s %s\n' "$@" >> "$LOG"; }
export -f fake_deploy; export LOG
export PIPELINE_DEPLOY_CMD="fake_deploy" PIPELINE_SMOKE_CMD="true"
promote() { (cd "$R" && bash scripts/pipeline/promote.sh "$@" 2>&1); }
rel() { cat "$(tdir REP-80)/releases.md"; }

new_repo
out=$(promote); assert_exit "no args fails" 1 $? "$out"
out=$(promote REP-1 prod); assert_exit "unknown env fails" 1 $? "$out"

branch feature/REP-80-x; ready_build REP-80 feature yes
out=$(promote REP-80 dev); assert_exit "dev blocked before build done" 1 $? "$out"
assert_eq "blocked promote does not deploy" "" "$(cat "$LOG")"
out=$(promote REP-80 qa); assert_exit "qa blocked before dev" 1 $? "$out"

built REP-80; head=$(g rev-parse HEAD)
echo dirty >> "$R/src/App.java"
out=$(promote REP-80 dev); assert_exit "uncommitted code blocks promote" 1 $? "$out"; assert_contains "explains dirty tree" "$out" "not clean"
g checkout -q -- src/App.java

out=$(promote rep-80 dev); assert_exit "dev promote succeeds" 0 $? "$out"
assert_contains "deploys HEAD to dev" "$(cat "$LOG")" "deploy dev $head REP-80"
assert_contains "records Dev line" "$(rel)" "Dev: $head"
assert_contains "records history" "$(cat "$(tdir REP-80)/deploy-history.md")" "dev <- $head"
assert_eq "commits the record" "" "$(g status --porcelain)"
assert_contains "commit message" "$(g log -1 --format=%s)" "deployed $head to dev"
assert_eq "dev: docs record synced to master" "$(g rev-parse HEAD)" "$(g rev-parse master)"
assert_eq "dev: build sha is on master" "0" "$(g merge-base --is-ancestor "$head" master; echo $?)"

out=$(promote REP-80 qa); assert_exit "qa blocked without dev self-check" 1 $? "$out"
dev_check REP-80 pass "$head"
out=$(promote REP-80 qa); assert_exit "qa promote succeeds" 0 $? "$out"
assert_contains "qa gets the dev build" "$(tail -1 "$LOG")" "deploy qa $head REP-80"
assert_eq "qa: staging branch points at the build" "$head" "$(g rev-parse staging)"
assert_eq "qa: docs record synced to master" "$(g rev-parse HEAD)" "$(g rev-parse master)"
out=$(cd "$R" && PIPELINE_DOCS_REF=master bash scripts/pipeline/gate.sh REP-80 qa staging 2>&1); assert_exit "qa: CI-shape gate on staging branch passes" 0 $? "$out"

out=$(promote REP-80 staging); assert_exit "staging blocked without QA pass" 1 $? "$out"
qa_report REP-80 pass "$head"
add_ticket REP-80 REP-8002 defect qa Low fixed; commit_all x
out=$(promote REP-80 staging); assert_exit "staging blocked by unverified QA defect" 1 $? "$out"
set_ticket REP-80 REP-8002 verified; commit_all x
out=$(promote REP-80 staging); assert_exit "staging promote succeeds" 0 $? "$out"
assert_contains "staging gets the same build" "$(tail -1 "$LOG")" "deploy staging $head REP-80"

out=$(promote REP-80 production); assert_exit "production blocked before sign-off" 1 $? "$out"
signoff REP-80 approved "$head"; marketing REP-80 ready; add_ticket REP-80 REP-8090 marketing - - done; commit_all x
out=$(promote REP-80 production); assert_exit "production blocked without go-live" 1 $? "$out"
golive REP-80
: > "$LOG"
out=$(PIPELINE_SMOKE_CMD=false promote REP-80 production); assert_exit "failed prod smoke fails promote" 1 $? "$out"
assert_contains "advises rollback" "$out" "rollback.sh production"
if rel | grep -q '^Production:'; then bad "failed smoke does not record production"; else ok "failed smoke does not record production"; fi
out=$(PIPELINE_DEPLOY_CMD=false promote REP-80 production); assert_exit "failed deploy fails promote" 1 $? "$out"
out=$(promote REP-80 production); assert_exit "production promote succeeds" 0 $? "$out"
assert_contains "production gets the same build" "$(tail -1 "$LOG")" "deploy production $head REP-80"
assert_eq "production: tag v1.0.0 on the build" "$head" "$(g rev-parse v1.0.0^{commit})"
assert_contains "production: version recorded" "$(rel)" "Production: $head"
assert_contains "production: version in line" "$(rel | grep '^Production:')" "v1.0.0"
out=$(promote REP-80 production); assert_exit "production promote is idempotent (tag exists on same sha)" 0 $? "$out"

out=$(promote REP-80 dev); assert_exit "re-promote to dev replaces Dev line" 0 $? "$out"
assert_eq "single Dev line" "1" "$(rel | grep -c '^Dev:')"

# rework loop: code change after dev -> must go through dev again
new_repo; branch feature/REP-81-x; full_through REP-81 chore no qa
g update-ref refs/heads/master "$(dev_sha_of REP-81)"
: > "$LOG"
echo "class Fix {}" > "$R/src/Fix.java"; commit_all fix
out=$(promote REP-81 qa); assert_exit "rework: qa refused after code change" 1 $? "$out"
out=$(promote REP-81 dev); assert_exit "rework: redeploy to dev allowed" 0 $? "$out"
newsha=$(g rev-parse HEAD~1)
assert_eq "rework: fixed build is on master" "0" "$(g merge-base --is-ancestor "$newsha" master; echo $?)"
assert_contains "rework: dev gets fixed build" "$(tail -1 "$LOG")" "deploy dev $newsha REP-81"
out=$(promote REP-81 qa); assert_exit "rework: qa still needs fresh dev-check" 1 $? "$out"
dev_check REP-81 pass "$newsha"
out=$(promote REP-81 qa); assert_exit "rework: qa after fresh dev-check" 0 $? "$out"

# cloud: dev promote merges via PR API
new_repo; branch claude/session-abc; ready_build REP-82 chore no; built REP-82
BARE="$(mktemp -d)"; git init -q --bare "$BARE"; g remote add origin "$BARE"; g push -q origin master claude/session-abc
GHLOG="$(mktemp)"; export GHLOG
cat > "$R/fake-gh.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$GHLOG"
case "$*" in
  "repo view"*) echo "chris/demo";;
  "api repos/chris/demo/pulls?head="*) echo "null";;
  "api -X POST repos/chris/demo/pulls"*) echo 7;;
  "api -X PUT repos/chris/demo/pulls/7/merge"*) git push -q origin HEAD:master; echo '{"merged":true}';;
  "api -X PATCH repos/chris/demo/git/refs/"*) ref=$(printf '%s' "$*" | sed -E 's#.*git/(refs/[^ ]+).*#\1#'); sha=$(printf '%s' "$*" | sed -E 's/.*-f sha=([0-9a-f]+).*/\1/'); git update-ref "$ref" "$sha";;
  *) exit 1;;
esac
FAKE
chmod +x "$R/fake-gh.sh"; echo "fake-gh.sh" >> "$R/.git/info/exclude"
g update-ref refs/remotes/origin/master "$(g rev-parse master)"
: > "$LOG"
out=$(PIPELINE_NO_PUSH=0 CLAUDE_CODE_REMOTE=true PIPELINE_GH_CMD="$R/fake-gh.sh" promote REP-82 dev); assert_exit "cloud: dev promote via PR merge" 0 $? "$out"
assert_contains "cloud: PR created against master" "$(cat "$GHLOG")" "-f head=claude/session-abc -f base=master"
assert_contains "cloud: PR merged" "$(cat "$GHLOG")" "pulls/7/merge"
assert_contains "cloud: dev deployed" "$(cat "$LOG")" "deploy dev"
dev_check REP-82 pass "$(dev_sha_of REP-82)"
out=$(PIPELINE_NO_PUSH=0 CLAUDE_CODE_REMOTE=true PIPELINE_GH_CMD="$R/fake-gh.sh" promote REP-82 qa); assert_exit "cloud: qa promote updates staging ref via API" 0 $? "$out"
assert_contains "cloud: staging ref PATCHed" "$(cat "$GHLOG")" "git/refs/heads/staging -f sha=$(dev_sha_of REP-82)"

summary
