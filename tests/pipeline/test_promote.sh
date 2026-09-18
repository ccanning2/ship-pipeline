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

# ---- a project with no deployable environments ----
# AC-38 as well: an opted-out project walks an honestly user-facing feature to a version tag, no overrides
new_repo; branch feature/REP-83-x
set_capability PIPELINE_HAS_DEPLOY_ENVS '"no"'; set_capability PIPELINE_HAS_MARKETING '"no"'
blank_deploy_keys   # AC-18: the shape init.sh writes when opted out
ready_build REP-83 feature yes; built REP-83; head=$(g rev-parse HEAD)
: > "$LOG"
out=$(promote REP-83 dev); assert_exit "no-deploy: dev promote succeeds" 0 $? "$out"
assert_contains "AC-20: says no deploy was performed and why" "$out" "no deploy: project has no deployable environments"
if echo "$out" | grep -q "unbound variable"; then bad "AC-18: empty deploy keys are tolerated"; else ok "AC-18: empty deploy keys are tolerated"; fi
assert_eq "AC-16: the build sha still reaches master" "0" "$(g merge-base --is-ancestor "$head" master; echo $?)"
dev_check REP-83 pass "$head"
out=$(promote REP-83 qa); assert_exit "no-deploy: qa promote succeeds" 0 $? "$out"
assert_eq "AC-16: the staging branch still points at the build" "$head" "$(g rev-parse staging)"
qa_report REP-83 pass "$head"
out=$(promote REP-83 staging); assert_exit "no-deploy: staging promote succeeds" 0 $? "$out"
assert_contains "AC-14: no workflow dispatch at staging" "$out" "no deploy: project has no deployable environments"
signoff REP-83 approved "$head"; golive REP-83
out=$(PIPELINE_SMOKE_CMD=false promote REP-83 production); assert_exit "AC-38/AC-15: an opted-out user-facing feature reaches production with no marketing evidence and no smoke" 0 $? "$out"
assert_eq "AC-14: nothing was deployed at any stage" "" "$(cat "$LOG")"
assert_eq "AC-16: the version tag is still created on the build" "$head" "$(g rev-parse v1.0.0^{commit})"
assert_contains "AC-16: releases.md still records Production" "$(cat "$(tdir REP-83)/releases.md")" "Production: $head"
assert_contains "AC-16: deploy-history.md still gains a line" "$(cat "$(tdir REP-83)/deploy-history.md")" "production <- $head"
assert_eq "AC-16: the records are still committed" "" "$(g status --porcelain)"
assert_eq "AC-16: the records are still synced to master" "$(g rev-parse HEAD)" "$(g rev-parse master)"

new_repo; branch feature/REP-84-x; set_capability PIPELINE_HAS_DEPLOY_ENVS '"no"'
ready_build REP-84 chore no; before=$(g rev-parse master); : > "$LOG"
out=$(promote REP-84 dev); assert_exit "AC-17: the gate still blocks with deploy envs off" 1 $? "$out"
assert_eq "AC-17: a blocked promote performs no git operation" "$before" "$(g rev-parse master)"
assert_eq "AC-17: a blocked promote deploys nothing" "" "$(cat "$LOG")"

new_repo; branch feature/REP-85-x; unset_capability PIPELINE_HAS_DEPLOY_ENVS
ready_build REP-85 chore no; built REP-85; head=$(g rev-parse HEAD); : > "$LOG"
out=$(promote REP-85 dev); assert_exit "AC-19: key absent still promotes" 0 $? "$out"
assert_contains "AC-19: key absent still deploys (fail closed)" "$(cat "$LOG")" "deploy dev $head REP-85"
assert_contains "AC-19: key absent reports a real deploy" "$out" "(dev deploy)"

new_repo; branch feature/REP-87-x; set_capability PIPELINE_HAS_DEPLOY_ENVS '"maybe"'
ready_build REP-87 chore no; built REP-87; head=$(g rev-parse HEAD); : > "$LOG"
out=$(promote REP-87 dev); assert_exit "AC-19: unrecognised value still promotes" 0 $? "$out"
assert_contains "AC-19: unrecognised value still deploys (fail closed)" "$(cat "$LOG")" "deploy dev $head REP-87"

# AC-13: a pre-1.1.0 pipeline.env deploys and smokes exactly as today
new_repo; branch feature/REP-86-x; legacy_env
ready_build REP-86 chore no; built REP-86; head=$(g rev-parse HEAD); : > "$LOG"
out=$(promote REP-86 dev); assert_exit "AC-13: legacy env, dev promote" 0 $? "$out"
assert_contains "AC-13: legacy env deploys dev" "$(cat "$LOG")" "deploy dev $head REP-86"
dev_check REP-86 pass "$head"
out=$(promote REP-86 qa); assert_exit "AC-13: legacy env, qa promote" 0 $? "$out"
assert_contains "AC-13: legacy env deploys qa" "$(tail -1 "$LOG")" "deploy qa $head REP-86"
qa_report REP-86 pass "$head"
out=$(promote REP-86 staging); assert_exit "AC-13: legacy env, staging promote" 0 $? "$out"
assert_contains "AC-13: legacy env deploys staging" "$(tail -1 "$LOG")" "deploy staging $head REP-86"
signoff REP-86 approved "$head"; golive REP-86
out=$(PIPELINE_SMOKE_CMD=false promote REP-86 production); assert_exit "AC-13: legacy env still runs smoke (failing smoke blocks)" 1 $? "$out"
out=$(promote REP-86 production); assert_exit "AC-13: legacy env, production promote" 0 $? "$out"
assert_contains "AC-13: legacy env deploys production" "$(tail -1 "$LOG")" "deploy production $head REP-86"

# ---- QA (SHI-5): promote.sh reads capabilities from pipeline.env only, fails closed, tolerates a sparse env ----
# FR-3: an environment variable cannot switch deploys off; and a key that is absent still smokes (fail closed)
new_repo; branch feature/REP-88-x; unset_capability PIPELINE_HAS_DEPLOY_ENVS
ready_build REP-88 chore no; built REP-88; head=$(g rev-parse HEAD); : > "$LOG"
out=$(PIPELINE_SMOKE_CMD=false promote REP-88 dev); assert_exit "QA: key absent, a failing smoke still blocks dev" 1 $? "$out"
assert_contains "QA: key absent, smoke ran and reported" "$out" "smoke test failed on dev"
: > "$LOG"
out=$(PIPELINE_HAS_DEPLOY_ENVS=no promote REP-88 dev); assert_exit "FR-3: PIPELINE_HAS_DEPLOY_ENVS=no in the environment does not stop the deploy" 0 $? "$out"
assert_contains "FR-3: the deploy still ran" "$(cat "$LOG")" "deploy dev $head REP-88"
assert_contains "FR-3: and is reported as a real deploy" "$out" "(dev deploy)"
new_repo; branch feature/REP-89-x; set_capability PIPELINE_HAS_DEPLOY_ENVS '"maybe"'
ready_build REP-89 chore no; built REP-89
out=$(PIPELINE_SMOKE_CMD=false promote REP-89 dev); assert_exit "QA: unrecognised value, a failing smoke still blocks (fail closed)" 1 $? "$out"
# the value is trimmed, lowercased and CR-tolerant, and a project that leaves the deploy keys out altogether still promotes
new_repo; branch feature/REP-90-x; set_capability_crlf PIPELINE_HAS_DEPLOY_ENVS "  No "
for k in DEPLOY_WORKFLOW HEALTH_PATH DEV_URL QA_URL STAGING_URL PRODUCTION_URL; do drop_env_key "$k"; done
ready_build REP-90 chore no; built REP-90; head=$(g rev-parse HEAD); : > "$LOG"
out=$(PIPELINE_SMOKE_CMD=false promote REP-90 dev); assert_exit "QA: '  No ' + CR resolves off; missing deploy keys do not trip set -u" 0 $? "$out"
assert_contains "QA: says no deploy was performed" "$out" "no deploy: project has no deployable environments"
if echo "$out" | grep -q "unbound variable"; then bad "QA: missing *_URL / DEPLOY_WORKFLOW keys are tolerated"; else ok "QA: missing *_URL / DEPLOY_WORKFLOW keys are tolerated"; fi
assert_eq "QA: nothing deployed" "" "$(cat "$LOG")"
dev_check REP-90 pass "$head"
out=$(PIPELINE_SMOKE_CMD=false promote REP-90 qa); assert_exit "QA: qa with missing deploy keys" 0 $? "$out"
qa_report REP-90 pass "$head"
out=$(PIPELINE_SMOKE_CMD=false promote REP-90 staging); assert_exit "QA: staging with missing deploy keys" 0 $? "$out"
assert_eq "QA: still nothing deployed" "" "$(cat "$LOG")"

# AC-38 for real: install with both flags (no fixture patching, no deploy or smoke override), then walk one ticket to a tag
if [ "$INIT_MODE" = init ]; then
  R="$(mktemp -d)"; git -C "$R" init -q -b master; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  mkdir -p "$R/src"; echo "class App {}" > "$R/src/App.java"; g add -A; g commit -qm init
  out=$(bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name lean --team-key REP --no-deploy-envs --no-marketing 2>&1); assert_exit "AC-38: opted-out install" 0 $? "$out"
  assert_eq "AC-38: no scripts/deploy in the installed project" "no" "$([ -e "$R/scripts/deploy" ] && echo yes || echo no)"
  commit_all "install pipeline"; branch feature/REP-91-x
  ready_build REP-91 feature yes; built REP-91; head=$(g rev-parse HEAD)
  instp() { (cd "$R" && env -u PIPELINE_DEPLOY_CMD -u PIPELINE_SMOKE_CMD PIPELINE_GH_CMD=/nonexistent/gh bash scripts/pipeline/promote.sh "$@" 2>&1); }
  out=$(instp REP-91 dev); assert_exit "AC-38: dev, no overrides" 0 $? "$out"; assert_contains "AC-38: dev reports the skipped deploy" "$out" "no deploy: project has no deployable environments"
  dev_check REP-91 pass "$head"
  out=$(instp REP-91 qa); assert_exit "AC-38: qa, no overrides" 0 $? "$out"
  qa_report REP-91 pass "$head"
  out=$(instp REP-91 staging); assert_exit "AC-38: staging, no overrides (no gh dispatch)" 0 $? "$out"
  signoff REP-91 approved "$head"; golive REP-91
  out=$(instp REP-91 production); assert_exit "AC-38: production, user-facing, no marketing evidence, no overrides" 0 $? "$out"
  assert_eq "AC-38: the version tag exists on the built sha" "$head" "$(g rev-parse v1.0.0^{commit})"
  assert_contains "AC-38: the gate said marketing was off" "$out" "marketing=off"
fi

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
