#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "init.sh (install into a project)"
[ "$INIT_MODE" = init ] || { echo "  (skipped: not running from the plugin repo)"; summary; exit 0; }
INIT="$REPO_SRC/scripts/init.sh"

P="$(mktemp -d)"; out=$(bash "$INIT" --project-dir "$P" 2>&1); assert_exit "refuses non-git dir" 1 $? "$out"

P="$(mktemp -d)"; git -C "$P" init -q -b master; git -C "$P" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P" --name radio --team-key RAD 2>&1); assert_exit "fresh install" 0 $? "$out"
for f in scripts/pipeline/gate.sh scripts/pipeline/promote.sh scripts/pipeline/hooks/allow-paths.sh scripts/pipeline/hooks/guard-merge.sh scripts/pipeline/pipeline.env scripts/deploy/deploy.sh \
         .claude/agents/senior-engineer.md .claude/agents/qa-tester.md .claude/settings.json .github/workflows/deploy.yml .github/workflows/pipeline-gate.yml \
         docs/pipeline/CONTEXT.md docs/pipeline/TICKETS.md docs/pipeline/BRANCHING.md docs/pipeline/CLOUD.md docs/pipeline/README.md docs/pipeline/_templates/releases.md RELEASE_CHECKLIST.md tests/pipeline/run-all.sh .gitignore; do
  [ -f "$P/$f" ] && ok "installs $f" || bad "installs $f"
done
[ -x "$P/scripts/pipeline/gate.sh" ] && ok "scripts executable" || bad "scripts executable"
assert_contains "placeholders filled: name" "$(cat "$P/scripts/pipeline/pipeline.env")" 'PROJECT_NAME="radio"'
assert_contains "placeholders filled: key" "$(cat "$P/scripts/pipeline/pipeline.env")" 'TRACKER_TEAM_KEY="RAD"'
assert_contains "context named" "$(cat "$P/docs/pipeline/CONTEXT.md")" "# radio — Pipeline context"
assert_contains "gitignore appended" "$(cat "$P/.gitignore")" ".claude/.pipeline-ticket"
[ -f "$P/.claude/commands/ship.md" ] && bad "commands stay in the plugin (not copied)" || ok "commands stay in the plugin (not copied)"

# the installed project's own test suite runs green (copy mode)
out=$(cd "$P" && git add -A && git -c user.email=a@a -c user.name=a commit -qm install && bash tests/pipeline/run-all.sh 2>&1 | tail -1); assert_eq "installed project self-test passes" "ALL PIPELINE TESTS PASSED" "$out"

# project-owned files are never overwritten; tooling is refreshed
echo "MY CONTEXT" > "$P/docs/pipeline/CONTEXT.md"; echo "MY ENV" > "$P/scripts/pipeline/pipeline.env"; echo "MY DEPLOY" > "$P/scripts/deploy/deploy.sh"
echo "# stale" > "$P/scripts/pipeline/gate.sh"; echo "# stale" > "$P/.claude/agents/qa-tester.md"
out=$(bash "$INIT" --project-dir "$P" 2>&1); assert_exit "re-run (update)" 0 $? "$out"
assert_eq "keeps CONTEXT.md" "MY CONTEXT" "$(cat "$P/docs/pipeline/CONTEXT.md")"
assert_eq "keeps pipeline.env" "MY ENV" "$(cat "$P/scripts/pipeline/pipeline.env")"
assert_eq "keeps deploy.sh" "MY DEPLOY" "$(cat "$P/scripts/deploy/deploy.sh")"
cmp -s "$P/scripts/pipeline/gate.sh" "$REPO_SRC/scripts/pipeline/gate.sh" && ok "refreshes gate.sh" || bad "refreshes gate.sh"
cmp -s "$P/.claude/agents/qa-tester.md" "$REPO_SRC/agents/qa-tester.md" && ok "refreshes agents" || bad "refreshes agents"
assert_contains "reports kept files" "$out" "kept"
assert_eq "gitignore not duplicated" "1" "$(grep -c '.claude/.pipeline-ticket' "$P/.gitignore")"
out=$(bash "$INIT" --project-dir "$P" --force-tooling 2>&1); cmp -s "$P/scripts/deploy/deploy.sh" "$REPO_SRC/scripts/deploy/deploy.sh" && ok "--force-tooling refreshes deploy scripts" || bad "--force-tooling refreshes deploy scripts"

# ---- declaring the project's shape at install time ----
P3="$(mktemp -d)"; git -C "$P3" init -q -b master; git -C "$P3" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P3" --name solo --team-key SOL --no-deploy-envs 2>&1); assert_exit "AC-21: --no-deploy-envs install" 0 $? "$out"
for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml; do
  [ -e "$P3/$f" ] && bad "AC-21: does not create $f" || ok "AC-21: does not create $f"
done
[ -d "$P3/scripts/deploy" ] && bad "AC-21: does not create scripts/deploy/" || ok "AC-21: does not create scripts/deploy/"
for f in .github/workflows/pipeline-gate.yml scripts/pipeline/gate.sh scripts/pipeline/promote.sh docs/pipeline/CONTEXT.md RELEASE_CHECKLIST.md tests/pipeline/run-all.sh; do
  [ -f "$P3/$f" ] && ok "AC-21: still installs $f" || bad "AC-21: still installs $f"
done
E3="$P3/scripts/pipeline/pipeline.env"
assert_contains "AC-22: declares no deployable environments" "$(cat "$E3")" 'PIPELINE_HAS_DEPLOY_ENVS="no"'
assert_contains "AC-22: marketing stays on when not opted out" "$(cat "$E3")" 'PIPELINE_HAS_MARKETING="yes"'
for k in DEPLOY_WORKFLOW HEALTH_PATH DEV_URL QA_URL STAGING_URL PRODUCTION_URL; do
  grep -q "^$k=\"\"$" "$E3" && ok "AC-23: $k present but empty" || bad "AC-23: $k present but empty"
done
grep -q '__' "$E3" && bad "AC-23: no placeholder survives" || ok "AC-23: no placeholder survives"
assert_contains "AC-21: reports the declared capabilities" "$out" "capabilities: deploy-envs=no marketing=yes"

P4="$(mktemp -d)"; git -C "$P4" init -q -b master; git -C "$P4" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P4" --name duo --team-key DUO 2>&1); assert_exit "AC-22: install with no flags" 0 $? "$out"
assert_contains "AC-22: deploy envs default to yes" "$(cat "$P4/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_DEPLOY_ENVS="yes"'
assert_contains "AC-22: marketing defaults to yes" "$(cat "$P4/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_MARKETING="yes"'
assert_contains "AC-22: default install still has the deploy URLs" "$(cat "$P4/scripts/pipeline/pipeline.env")" 'DEV_URL="https://dev.duo.example"'

P5="$(mktemp -d)"; git -C "$P5" init -q -b master; git -C "$P5" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P5" --no-deploy-env 2>&1); assert_exit "AC-24: unknown flag fails" 1 $? "$out"
assert_eq "AC-24: unknown flag creates nothing" "" "$(ls -A "$P5" | grep -v '^.git$' || true)"

# BR-13 / AC-25: a re-run never deletes or edits what an earlier install created
echo "MY DEPLOY" > "$P/scripts/deploy/deploy.sh"; echo "MY WORKFLOW" > "$P/.github/workflows/deploy.yml"; echo "MY ENV2" > "$P/scripts/pipeline/pipeline.env"
out=$(bash "$INIT" --project-dir "$P" --no-deploy-envs 2>&1); assert_exit "AC-25: re-run with --no-deploy-envs" 0 $? "$out"
assert_eq "AC-25: keeps deploy.sh byte-identical" "MY DEPLOY" "$(cat "$P/scripts/deploy/deploy.sh")"
assert_eq "AC-25: keeps deploy.yml byte-identical" "MY WORKFLOW" "$(cat "$P/.github/workflows/deploy.yml")"
assert_eq "AC-25: keeps pipeline.env byte-identical" "MY ENV2" "$(cat "$P/scripts/pipeline/pipeline.env")"
assert_contains "AC-25: reports the deploy files as kept" "$out" "kept    scripts/deploy/deploy.sh"
assert_contains "AC-25: reports deploy.yml as kept" "$out" ".github/workflows/deploy.yml"
assert_contains "AC-25: tells the owner to set the key by hand" "$out" 'set PIPELINE_HAS_DEPLOY_ENVS="no" in scripts/pipeline/pipeline.env yourself'
assert_contains "AC-25: tells the owner the deploy files were left" "$out" "delete scripts/deploy/* and .github/workflows/deploy.yml if you no longer want them"
out=$(bash "$INIT" --project-dir "$P" --no-deploy-envs --force-tooling 2>&1); assert_exit "AC-26: --force-tooling with --no-deploy-envs" 0 $? "$out"
assert_eq "AC-26: --force-tooling does not resurrect deploy.sh" "MY DEPLOY" "$(cat "$P/scripts/deploy/deploy.sh")"

# AC-27: idempotent, and the installed project's own suite is green with both capabilities off
P6="$(mktemp -d)"; git -C "$P6" init -q -b master; git -C "$P6" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P6" --name lean --team-key LEA --no-deploy-envs --no-marketing 2>&1); assert_exit "AC-27: opted-out install" 0 $? "$out"
assert_contains "AC-27: declares no marketing function" "$(cat "$P6/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_MARKETING="no"'
before6=$(cd "$P6" && find . -path ./.git -prune -o -type f -exec cksum {} \; | sort)
out=$(bash "$INIT" --project-dir "$P6" --name lean --team-key LEA --no-deploy-envs --no-marketing 2>&1); assert_exit "AC-27: second identical run" 0 $? "$out"
after6=$(cd "$P6" && find . -path ./.git -prune -o -type f -exec cksum {} \; | sort)
assert_eq "AC-27: second run changes nothing" "$before6" "$after6"
out=$(cd "$P6" && git add -A && git -c user.email=a@a -c user.name=a commit -qm install && bash tests/pipeline/run-all.sh 2>&1 | tail -1)
assert_eq "AC-27: opted-out project self-test passes" "ALL PIPELINE TESTS PASSED" "$out"

# AC-28: /pipeline-init asks the two capability questions
I="$REPO_SRC/commands/pipeline-init.md"
for s in "--no-deploy-envs" "--no-marketing" "deployable environments" "marketing function" "CONTEXT.md"; do
  grep -qF -e "$s" "$I" && ok "AC-28: /pipeline-init mentions $s" || bad "AC-28: /pipeline-init mentions $s"
done

# ---- QA (SHI-5): arguments are validated before anything is written (FR-15) ----
mkp() { local d; d="$(mktemp -d)"; git -C "$d" init -q -b master; git -C "$d" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init; echo "$d"; }
for badargs in "--no-deploy-envs=no" "-no-deploy-envs" "--no-deploy-envs --bogus" "--no-marketing extra" "--no-marketing --name x --wat" "--no-deploy-envs --no-marketing --force-toolin"; do
  Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" $badargs 2>&1); assert_exit "QA: '$badargs' is rejected" 1 $? "$out"
  assert_eq "QA: '$badargs' creates nothing" "" "$(ls -A "$Pq" | grep -v '^\.git$' || true)"
done
# a duplicated flag, or a flag given before --project-dir, is harmless
Pq="$(mkp)"; out=$(bash "$INIT" --no-deploy-envs --no-marketing --no-deploy-envs --project-dir "$Pq" --no-marketing 2>&1); assert_exit "QA: duplicate flags, flags before --project-dir" 0 $? "$out"
assert_contains "QA: duplicate flags still declare deploy-envs no" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_DEPLOY_ENVS="no"'
assert_contains "QA: duplicate flags still declare marketing no" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_MARKETING="no"'
# --no-marketing on its own scaffolds the deploy machinery and keeps the deploy URLs
Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" --name mkt --no-marketing 2>&1); assert_exit "QA: --no-marketing only" 0 $? "$out"
assert_contains "QA: --no-marketing declares marketing no" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_MARKETING="no"'
assert_contains "QA: --no-marketing leaves deploy-envs yes" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_DEPLOY_ENVS="yes"'
[ -f "$Pq/scripts/deploy/smoke.sh" ] && [ -f "$Pq/.github/workflows/deploy.yml" ] && ok "QA: --no-marketing still scaffolds the deploy machinery" || bad "QA: --no-marketing still scaffolds the deploy machinery"
# the opted-out pipeline.env sources cleanly under set -u and leaves every deploy key empty
Pq="$(mkp)"; bash "$INIT" --project-dir "$Pq" --name lean --no-deploy-envs >/dev/null 2>&1
assert_eq "QA: opted-out pipeline.env sources under set -u with empty deploy keys" "no||||||" \
  "$( (set -euo pipefail; source "$Pq/scripts/pipeline/pipeline.env"; echo "$PIPELINE_HAS_DEPLOY_ENVS|$DEPLOY_WORKFLOW|$HEALTH_PATH|$DEV_URL|$QA_URL|$STAGING_URL|$PRODUCTION_URL") 2>&1 )"

# BR-13, every flag combination: a re-run over an existing install never touches a project-owned file
for flags in "" "--no-marketing" "--no-deploy-envs" "--no-deploy-envs --no-marketing" "--no-deploy-envs --force-tooling" "--no-deploy-envs --no-marketing --force-tooling"; do
  Pq="$(mkp)"; bash "$INIT" --project-dir "$Pq" --name ex --team-key EX >/dev/null 2>&1
  for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml .github/workflows/pipeline-gate.yml \
           scripts/pipeline/pipeline.env docs/pipeline/CONTEXT.md RELEASE_CHECKLIST.md .claude/settings.json; do echo "MINE $f" > "$Pq/$f"; done
  bash "$INIT" --project-dir "$Pq" $flags >/dev/null 2>&1; rc=$?; changed=""
  for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml .github/workflows/pipeline-gate.yml \
           scripts/pipeline/pipeline.env docs/pipeline/CONTEXT.md RELEASE_CHECKLIST.md .claude/settings.json; do
    [ "$(cat "$Pq/$f" 2>/dev/null)" = "MINE $f" ] || changed="$changed $f"
  done
  assert_eq "QA: re-run [$flags] exits 0 and leaves every project-owned file byte-identical" "0|" "$rc|$changed"
done

# QA-DEF (FR-15): an unknown --profile must fail before anything is written, like every other bad argument
Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" --profile nope 2>&1); assert_exit "QA-DEF: unknown profile is rejected" 1 $? "$out"
assert_eq "QA-DEF: an unknown profile creates nothing (no half-applied install)" "" "$(ls -A "$Pq" | grep -v '^\.git$' || true)"
# QA-DEF (BR-13/FR-21): a project that opted out must not get the deploy machinery back on a flagless re-run
Pq="$(mkp)"; bash "$INIT" --project-dir "$Pq" --name lean --no-deploy-envs >/dev/null 2>&1
out=$(bash "$INIT" --project-dir "$Pq" 2>&1); assert_exit "QA-DEF: flagless re-run over an opted-out install" 0 $? "$out"
assert_eq "QA-DEF: pipeline.env says no deployable environments, so scripts/deploy is not recreated" "no" "$([ -e "$Pq/scripts/deploy" ] && echo yes || echo no)"
assert_eq "QA-DEF: and neither is .github/workflows/deploy.yml" "no" "$([ -e "$Pq/.github/workflows/deploy.yml" ] && echo yes || echo no)"

# profile install
P2="$(mktemp -d)"; git -C "$P2" init -q -b master; git -C "$P2" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P2" --profile reputabill 2>&1); assert_exit "profile install" 0 $? "$out"
assert_contains "profile context used" "$(cat "$P2/docs/pipeline/CONTEXT.md")" "Curate"
out=$(bash "$INIT" --project-dir "$P2" --profile nope 2>&1); assert_exit "unknown profile fails" 1 $? "$out"

summary
