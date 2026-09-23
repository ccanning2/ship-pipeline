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
         docs/pipeline/CONTEXT.md docs/pipeline/TICKETS.md docs/pipeline/BRANCHING.md docs/pipeline/CLOUD.md docs/pipeline/README.md docs/pipeline/_templates/releases.md RELEASE_CHECKLIST.md .gitignore \
         scripts/pipeline/host.sh scripts/pipeline/tracker.sh scripts/pipeline/connect.sh scripts/pipeline/ci-gate.sh scripts/pipeline/ci-resolve.sh scripts/pipeline/hooks/allow-commands.sh; do
  [ -f "$P/$f" ] && ok "installs $f" || bad "installs $f"
done
[ -x "$P/scripts/pipeline/gate.sh" ] && ok "scripts executable" || bad "scripts executable"
assert_contains "placeholders filled: name" "$(cat "$P/scripts/pipeline/pipeline.env")" 'PROJECT_NAME="radio"'
assert_contains "placeholders filled: key" "$(cat "$P/scripts/pipeline/pipeline.env")" 'TRACKER_TEAM_KEY="RAD"'
assert_contains "context named" "$(cat "$P/docs/pipeline/CONTEXT.md")" "# radio — Pipeline context"
assert_contains "gitignore appended" "$(cat "$P/.gitignore")" ".claude/.pipeline-ticket"
assert_contains "item 7: gitignore entries sit under '# ship-pipeline'" "$(cat "$P/.gitignore")" "# ship-pipeline"
grep -q 'Append to' "$P/.gitignore" && bad "item 7: no instruction text copied into .gitignore" || ok "item 7: no instruction text copied into .gitignore"
[ -e "$P/.gitignore.pipeline" ] && bad "item 7: no stray .gitignore.pipeline" || ok "item 7: no stray .gitignore.pipeline"
for f in ticket-id base-ref enforcement doctor; do [ -x "$P/scripts/pipeline/$f.sh" ] && ok "installs $f.sh" || bad "installs $f.sh"; done
[ -f "$P/scripts/pipeline/tracker-schema.txt" ] && ok "installs tracker-schema.txt" || bad "installs tracker-schema.txt"
assert_contains "item 3: the ticket regex is the team key" "$(cat "$P/scripts/pipeline/pipeline.env")" 'PIPELINE_TICKET_REGEX="${TRACKER_TEAM_KEY:-}-[0-9]+"'
assert_eq "item 3: RAD-7 is a ticket" "RAD-7" "$(cd "$P" && bash scripts/pipeline/ticket-id.sh "feature/rad-7-x")"
for s in macos-14 UTF-8 v1.45.0-jammy; do
  (cd "$P" && bash scripts/pipeline/ticket-id.sh "$s" >/dev/null) && bad "item 3: $s is not a ticket" || ok "item 3: $s is not a ticket"
done
assert_contains "item 9: PIPELINE_REMOTE defaults to origin" "$(cat "$P/scripts/pipeline/pipeline.env")" 'PIPELINE_REMOTE="origin"'
[ -f "$P/.claude/commands/ship.md" ] && bad "commands stay in the plugin (not copied)" || ok "commands stay in the plugin (not copied)"

# the plugin's test suite stays in the plugin: an install is quick and ships no tests
[ -e "$P/tests" ] && bad "no test suite is installed into the project" || ok "no test suite is installed into the project"
grep -q 'tests/pipeline' "$P/scripts/pipeline/.install-manifest" && bad "the manifest records no test file" || ok "the manifest records no test file"
assert_contains "the answers are reported" "$out" "host: github  tracker: linear  deploy-mode: merge  start-at: analysis"
(cd "$P" && git add -A && git -c user.email=a@a -c user.name=a commit -qm install)

# project-owned files are never overwritten; tooling is refreshed
echo "MY CONTEXT" > "$P/docs/pipeline/CONTEXT.md"; echo "MY ENV" > "$P/scripts/pipeline/pipeline.env"; echo "MY DEPLOY" > "$P/scripts/deploy/deploy.sh"
[ -f "$P/scripts/pipeline/.install-manifest" ] && ok "install records a manifest" || bad "install records a manifest"
echo "# stale" > "$P/scripts/pipeline/gate.sh"; echo "# stale" > "$P/.claude/agents/qa-tester.md"
rm "$P/scripts/pipeline/promote.sh"
out=$(bash "$INIT" --project-dir "$P" 2>&1); assert_exit "re-run (update)" 0 $? "$out"
assert_eq "keeps CONTEXT.md" "MY CONTEXT" "$(cat "$P/docs/pipeline/CONTEXT.md")"
assert_eq "keeps pipeline.env" "MY ENV" "$(cat "$P/scripts/pipeline/pipeline.env")"
assert_eq "keeps deploy.sh" "MY DEPLOY" "$(cat "$P/scripts/deploy/deploy.sh")"
assert_eq "item 11: a hand-edited agent is kept" "# stale" "$(cat "$P/.claude/agents/qa-tester.md")"
assert_eq "item 11: a hand-edited script is kept" "# stale" "$(cat "$P/scripts/pipeline/gate.sh")"
cmp -s "$P/.claude/agents/qa-tester.md.new" "$REPO_SRC/agents/qa-tester.md" && ok "item 11: the new agent is written beside it (.new)" || bad "item 11: the new agent is written beside it (.new)"
assert_contains "item 11: reports customised files" "$out" "customised, kept .claude/agents/qa-tester.md"
cmp -s "$P/scripts/pipeline/promote.sh" "$REPO_SRC/scripts/pipeline/promote.sh" && ok "a deleted tooling file is restored" || bad "a deleted tooling file is restored"
cmp -s "$P/scripts/pipeline/status.sh" "$REPO_SRC/scripts/pipeline/status.sh" && ok "untouched tooling stays current" || bad "untouched tooling stays current"
assert_contains "reports kept files" "$out" "kept"
assert_eq "gitignore not duplicated" "1" "$(grep -c '.claude/.pipeline-ticket' "$P/.gitignore")"
out=$(bash "$INIT" --project-dir "$P" 2>&1); assert_eq "item 11: a second re-run still keeps the edit" "# stale" "$(cat "$P/.claude/agents/qa-tester.md")"
out=$(bash "$INIT" --project-dir "$P" --force-tooling 2>&1); cmp -s "$P/scripts/deploy/deploy.sh" "$REPO_SRC/scripts/deploy/deploy.sh" && ok "--force-tooling refreshes deploy scripts" || bad "--force-tooling refreshes deploy scripts"
cmp -s "$P/scripts/pipeline/gate.sh" "$REPO_SRC/scripts/pipeline/gate.sh" && ok "--force-tooling refreshes a hand-edited script" || bad "--force-tooling refreshes a hand-edited script"
cmp -s "$P/.claude/agents/qa-tester.md" "$REPO_SRC/agents/qa-tester.md" && ok "--force-tooling refreshes a hand-edited agent" || bad "--force-tooling refreshes a hand-edited agent"
[ -e "$P/.claude/agents/qa-tester.md.new" ] && bad "--force-tooling removes the .new copy" || ok "--force-tooling removes the .new copy"
out=$(bash "$INIT" --project-dir "$P" 2>&1); case "$out" in *customised*) bad "after --force-tooling nothing is customised" "$out";; *) ok "after --force-tooling nothing is customised";; esac

# ---- declaring the project's shape at install time ----
P3="$(mktemp -d)"; git -C "$P3" init -q -b master; git -C "$P3" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P3" --name solo --team-key SOL --no-deploy-envs 2>&1); assert_exit "AC-21: --no-deploy-envs install" 0 $? "$out"
for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml; do
  [ -e "$P3/$f" ] && bad "AC-21: does not create $f" || ok "AC-21: does not create $f"
done
[ -d "$P3/scripts/deploy" ] && bad "AC-21: does not create scripts/deploy/" || ok "AC-21: does not create scripts/deploy/"
for f in .github/workflows/pipeline-gate.yml scripts/pipeline/gate.sh scripts/pipeline/promote.sh docs/pipeline/CONTEXT.md RELEASE_CHECKLIST.md scripts/pipeline/tracker.sh; do
  [ -f "$P3/$f" ] && ok "AC-21: still installs $f" || bad "AC-21: still installs $f"
done
E3="$P3/scripts/pipeline/pipeline.env"
assert_contains "AC-22: declares no deployable environments" "$(cat "$E3")" 'PIPELINE_HAS_DEPLOY_ENVS="no"'
grep -q PIPELINE_HAS_MARKETING "$E3" && bad "3.0: pipeline.env has no marketing key" || ok "3.0: pipeline.env has no marketing key"
for k in DEPLOY_WORKFLOW HEALTH_PATH DEV_URL QA_URL STAGING_URL PRODUCTION_URL; do
  grep -q "^$k=\"\"$" "$E3" && ok "AC-23: $k present but empty" || bad "AC-23: $k present but empty"
done
grep -q '__' "$E3" && bad "AC-23: no placeholder survives" || ok "AC-23: no placeholder survives"
assert_contains "AC-21: reports the declared capabilities" "$out" "capabilities: deploy-envs=no"

P4="$(mktemp -d)"; git -C "$P4" init -q -b master; git -C "$P4" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P4" --name duo --team-key DUO 2>&1); assert_exit "AC-22: install with no flags" 0 $? "$out"
assert_contains "AC-22: deploy envs default to yes" "$(cat "$P4/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_DEPLOY_ENVS="yes"'
assert_contains "AC-22: default install has placeholder deploy URLs that never resolve" "$(cat "$P4/scripts/pipeline/pipeline.env")" 'DEV_URL="https://dev.duo.example.invalid"'

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
out=$(bash "$INIT" --project-dir "$P6" --name lean --team-key LEA --no-deploy-envs 2>&1); assert_exit "AC-27: opted-out install" 0 $? "$out"
before6=$(cd "$P6" && find . -path ./.git -prune -o -type f -exec cksum {} \; | sort)
out=$(bash "$INIT" --project-dir "$P6" --name lean --team-key LEA --no-deploy-envs 2>&1); assert_exit "AC-27: second identical run" 0 $? "$out"
after6=$(cd "$P6" && find . -path ./.git -prune -o -type f -exec cksum {} \; | sort)
assert_eq "AC-27: second run changes nothing" "$before6" "$after6"

# AC-28: /pipeline-init asks the two capability questions
I="$REPO_SRC/commands/pipeline-init.md"
for s in "--no-deploy-envs" "deployable environments" "CONTEXT.md" \
         "AskUserQuestion" "Start level" "--start-at" "Git platform" "Branching strategy" "Ticketing platform" "ticket prefix" "Deployment strategy" \
         "--git-host" "--git-url" "--tracker" "--tracker-url" "--deploy-mode" "--create-branches" "connect.sh login" "tracker.sh setup"; do
  grep -qF -e "$s" "$I" && ok "AC-28: /pipeline-init mentions $s" || bad "AC-28: /pipeline-init mentions $s"
done
grep -qi 'marketing' "$I" && bad "3.0: /pipeline-init no longer asks about marketing" || ok "3.0: /pipeline-init no longer asks about marketing"
grep -q 'run-all.sh' "$I" && bad "/pipeline-init never runs the plugin's test suite" || ok "/pipeline-init never runs the plugin's test suite"

# ---- QA (SHI-5): arguments are validated before anything is written (FR-15) ----
mkp() { local d; d="$(mktemp -d)"; git -C "$d" init -q -b master; git -C "$d" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init; echo "$d"; }
for badargs in "--no-deploy-envs=no" "-no-deploy-envs" "--no-deploy-envs --bogus" "--no-marketing" "--no-deploy-envs --name x --wat" "--no-deploy-envs --no-marketing --force-toolin"; do
  Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" $badargs 2>&1); assert_exit "QA: '$badargs' is rejected" 1 $? "$out"
  assert_eq "QA: '$badargs' creates nothing" "" "$(ls -A "$Pq" | grep -v '^\.git$' || true)"
done
# a duplicated flag, or a flag given before --project-dir, is harmless
Pq="$(mkp)"; out=$(bash "$INIT" --no-deploy-envs --no-deploy-envs --project-dir "$Pq" 2>&1); assert_exit "QA: duplicate flags, flags before --project-dir" 0 $? "$out"
assert_contains "QA: duplicate flags still declare deploy-envs no" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'PIPELINE_HAS_DEPLOY_ENVS="no"'
# the opted-out pipeline.env sources cleanly under set -u and leaves every deploy key empty
Pq="$(mkp)"; bash "$INIT" --project-dir "$Pq" --name lean --no-deploy-envs >/dev/null 2>&1
assert_eq "QA: opted-out pipeline.env sources under set -u with empty deploy keys" "no||||||" \
  "$( (set -euo pipefail; source "$Pq/scripts/pipeline/pipeline.env"; echo "$PIPELINE_HAS_DEPLOY_ENVS|$DEPLOY_WORKFLOW|$HEALTH_PATH|$DEV_URL|$QA_URL|$STAGING_URL|$PRODUCTION_URL") 2>&1 )"

# BR-13, every flag combination: a re-run over an existing install never touches a project-owned file
for flags in "" "--no-deploy-envs" "--no-deploy-envs --force-tooling" "--deploy-mode explicit" "--start-at qa"; do
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

# QA round 2 (SHI-21 fix): the flagless re-run reads PIPELINE_HAS_DEPLOY_ENVS with its OWN parser (init.sh never sources
# pipeline.env), so it must agree with gate.sh/promote.sh, which do. "recreated=no" = the opt-out was honoured.
# Expected "yes" (recreated) = the value is not an explicit no, so today's stricter behaviour applies. Byte-identity of
# pipeline.env and CONTEXT.md is checked in every case: init only ever reads them.
Pbase="$(mkp)"; bash "$INIT" --project-dir "$Pbase" --name lean --no-deploy-envs >/dev/null 2>&1
rerun_with() { # label expected-recreated printf-format [args...]  (the lines replace the PIPELINE_HAS_DEPLOY_ENVS line)
  local label="$1" expect="$2"; shift 2
  [ -f "$Pbase/scripts/pipeline/pipeline.env" ] || { bad "$label (the base install is missing)"; return; }
  local d; d="$(mktemp -d)"; cp -R "$Pbase/." "$d/"
  { grep -v '^PIPELINE_HAS_DEPLOY_ENVS=' "$d/scripts/pipeline/pipeline.env"; printf "$@"; } > "$d/pe.new" && mv "$d/pe.new" "$d/scripts/pipeline/pipeline.env"
  local pe ctx got o; pe="$(cksum < "$d/scripts/pipeline/pipeline.env")"; ctx="$(cksum < "$d/docs/pipeline/CONTEXT.md")"
  o=$(bash "$INIT" --project-dir "$d" 2>&1); local rc=$?
  got=no; { [ -e "$d/scripts/deploy/deploy.sh" ] || [ -e "$d/.github/workflows/deploy.yml" ]; } && got=yes
  local same=same; [ "$pe" = "$(cksum < "$d/scripts/pipeline/pipeline.env")" ] && [ "$ctx" = "$(cksum < "$d/docs/pipeline/CONTEXT.md")" ] || same=CHANGED
  assert_eq "$label" "$expect|same|0" "$got|$same|$rc"
}
rerun_with 'QA2: flagless re-run honours PIPELINE_HAS_DEPLOY_ENVS=No' no '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=No'
rerun_with "QA2: flagless re-run honours PIPELINE_HAS_DEPLOY_ENVS='no'" no '%s\n' "PIPELINE_HAS_DEPLOY_ENVS='no'"
rerun_with 'QA2: flagless re-run honours a padded " NO "' no '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=" NO "'
rerun_with 'QA2: flagless re-run honours no # comment' no '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=no # comment'
rerun_with 'QA2: flagless re-run honours "no"  # comment' no '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS="no"  # comment'
rerun_with 'QA2: flagless re-run honours a CRLF line ("no" + CR)' no '%s\r\n' 'PIPELINE_HAS_DEPLOY_ENVS="no"'
rerun_with 'QA2: flagless re-run honours export PIPELINE_HAS_DEPLOY_ENVS=no' no '%s\n' 'export PIPELINE_HAS_DEPLOY_ENVS=no'
rerun_with 'QA2: duplicate key, the last one (no) wins, as in gate.sh' no '%s\n%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=yes' 'PIPELINE_HAS_DEPLOY_ENVS=no'
rerun_with 'QA2: duplicate key, the last one (yes) wins, as in gate.sh' yes '%s\n%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=no' 'PIPELINE_HAS_DEPLOY_ENVS=yes'
rerun_with 'QA2: a commented-out no is not a declaration' yes '%s\n' '# PIPELINE_HAS_DEPLOY_ENVS="no"'
rerun_with 'QA2: a key that merely starts the same is not the key' yes '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS_OLD="no"'
rerun_with 'QA2: a quoted "no # c" is not a no (gate.sh agrees)' yes '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS="no # c"'
rerun_with 'QA2: false / nope / empty are not an explicit no' yes '%s\n%s\n%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=nope' 'PIPELINE_HAS_DEPLOY_ENVS=false' 'PIPELINE_HAS_DEPLOY_ENVS='
rerun_with 'QA2: unbalanced quote is unrecognised (strict)' yes '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS="no'
# environment only: a shell variable must never relax init (project-level settings live in pipeline.env)
Pq="$(mktemp -d)"; git -C "$Pq" init -q -b master; PIPELINE_HAS_DEPLOY_ENVS=no bash "$INIT" --project-dir "$Pq" >/dev/null 2>&1
assert_eq "QA2: PIPELINE_HAS_DEPLOY_ENVS in the process environment does not relax a fresh install" "yes" "$([ -e "$Pq/scripts/deploy/deploy.sh" ] && echo yes || echo no)"
# QA-DEF (SHI-25): an apostrophe or a lone double quote in the TRAILING COMMENT defeats the "no" although gate.sh reads it as no
rerun_with "QA-DEF: a no whose trailing comment contains an apostrophe (we don't deploy) is still honoured" no '%s\n' "PIPELINE_HAS_DEPLOY_ENVS=\"no\"  # we don't deploy"
rerun_with 'QA-DEF: a no whose trailing comment contains a lone double quote is still honoured' no '%s\n' 'PIPELINE_HAS_DEPLOY_ENVS=no # a " mark'

# ---- item 2: the trunk is not always master (acceptance test 1) ----
Pm="$(mkp)"; git -C "$Pm" branch -m master main
out=$(bash "$INIT" --project-dir "$Pm" --name pc --team-key PRI 2>&1); assert_exit "item 2: install on a main trunk" 0 $? "$out"
assert_contains "item 2: detects main" "$out" "base=main"
assert_contains "item 2: pipeline.env says main" "$(cat "$Pm/scripts/pipeline/pipeline.env")" 'BASE_BRANCH="main"'
stale="$(cd "$Pm" && grep -rlw master .claude docs .github scripts/pipeline RELEASE_CHECKLIST.md | grep -vE '/(base-ref|doctor)\.sh$' || true)"
assert_eq "item 2: no 'master' left in installed agents, docs, workflows or scripts" "" "$stale"
grep -rl '__BASE_BRANCH__\|__STAGING_BRANCH__' "$Pm" --exclude-dir=.git --exclude-dir=tests >/dev/null && bad "item 2: no branch placeholder survives" || ok "item 2: no branch placeholder survives"
$PY - "$Pm/.github/workflows/pipeline-gate.yml" "$Pm/.github/workflows/deploy.yml" <<'PY' && ok "item 2: both workflows target main and staging" || bad "item 2: both workflows target main and staging"
import yaml,sys
g=yaml.safe_load(open(sys.argv[1])); d=yaml.safe_load(open(sys.argv[2]))
sys.exit(0 if (g.get("on") or g[True])["pull_request"]["branches"]==["main","staging"] and (d.get("on") or d[True])["push"]["branches"]==["main","staging"] else 1)
PY
cmp -s "$Pm/scripts/pipeline/tracker.sh" "$REPO_SRC/scripts/pipeline/tracker.sh" && cmp -s "$Pm/scripts/pipeline/gate.sh" "$REPO_SRC/scripts/pipeline/gate.sh" \
  && ok "item 2: scripts are copied verbatim (only docs, workflows and pipeline.env are rendered)" || bad "item 2: scripts are copied verbatim (only docs, workflows and pipeline.env are rendered)"
assert_eq "item 2: base-ref.sh" "origin/main" "$(cd "$Pm" && bash scripts/pipeline/base-ref.sh)"
out=$(bash "$INIT" --project-dir "$Pm" 2>&1); assert_contains "item 2: a re-run reads the base branch from pipeline.env" "$out" "base=main (from pipeline.env)"
Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" --base-branch trunk --staging-branch pre 2>&1); assert_exit "item 2: --base-branch/--staging-branch" 0 $? "$out"
assert_contains "item 2: --base-branch written" "$(cat "$Pq/scripts/pipeline/pipeline.env")" 'BASE_BRANCH="trunk"'
assert_contains "item 2: --staging-branch in the docs" "$(cat "$Pq/docs/pipeline/BRANCHING.md")" '`pre`'
for badb in "--base-branch bad..name" "--base-branch x --staging-branch x"; do
  Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" $badb 2>&1); assert_exit "item 2: '$badb' rejected" 1 $? "$out"
  assert_eq "item 2: '$badb' creates nothing" "" "$(ls -A "$Pq" | grep -v '^\.git$' || true)"
done

# ---- item 7: an older install's leftovers are cleaned, and appending is idempotent (acceptance test 5) ----
Pg="$(mkp)"; printf 'node_modules\n\n# Append to .gitignore\n.claude/.pipeline-ticket\n.claude/settings.local.json\n' > "$Pg/.gitignore"
printf '# Append to .gitignore\n.claude/.pipeline-ticket\n.claude/settings.local.json\n' > "$Pg/.gitignore.pipeline"
bash "$INIT" --project-dir "$Pg" >/dev/null 2>&1; out=$(bash "$INIT" --project-dir "$Pg" 2>&1)
assert_eq "item 7: legacy instruction line replaced" "0|1" "$(grep -c 'Append to' "$Pg/.gitignore")|$(grep -c '^# ship-pipeline$' "$Pg/.gitignore")"
assert_eq "item 7: each entry exactly once after two runs" "1|1" "$(grep -cx '.claude/.pipeline-ticket' "$Pg/.gitignore")|$(grep -cx '.claude/settings.local.json' "$Pg/.gitignore")"
[ -e "$Pg/.gitignore.pipeline" ] && bad "item 7: the old .gitignore.pipeline is removed" || ok "item 7: the old .gitignore.pipeline is removed"
assert_contains "item 7: user entries untouched" "$(cat "$Pg/.gitignore")" "node_modules"
Pg="$(mkp)"; echo "my own notes" > "$Pg/.gitignore.pipeline"; bash "$INIT" --project-dir "$Pg" >/dev/null 2>&1
assert_eq "item 7: a .gitignore.pipeline the owner wrote is never deleted" "my own notes" "$(cat "$Pg/.gitignore.pipeline")"

# ---- upgrading a v1.0.0 install ----
Pu="$(mkp)"; bash "$INIT" --project-dir "$Pu" --name up --team-key UP >/dev/null 2>&1
sed -i.bak '/^PIPELINE_REMOTE=/d' "$Pu/scripts/pipeline/pipeline.env" && rm -f "$Pu/scripts/pipeline/pipeline.env.bak"; rm -f "$Pu/scripts/pipeline/.install-manifest"
before_env="$(cksum < "$Pu/scripts/pipeline/pipeline.env")"
out=$(bash "$INIT" --project-dir "$Pu" 2>&1); assert_exit "upgrade: re-run over a v1.0.0-shaped install" 0 $? "$out"
assert_contains "upgrade: says the install predates v1.1.0" "$out" "predates v1.1.0"
assert_contains "upgrade: points at the doctor" "$out" "/pipeline-doctor"
assert_eq "upgrade: pipeline.env is still not touched" "$before_env" "$(cksum < "$Pu/scripts/pipeline/pipeline.env")"
out=$(bash "$INIT" --project-dir "$Pm" 2>&1); case "$out" in *"predates v1.1.0"*) bad "upgrade: a current install gets no upgrade note" "$out";; *) ok "upgrade: a current install gets no upgrade note";; esac

# ---- item 8: deploy.yml ships switched off ----
assert_contains "item 8: installed deploy.yml is gated on PIPELINE_DEPLOY_ENABLED" "$(cat "$Pm/.github/workflows/deploy.yml")" "vars.PIPELINE_DEPLOY_ENABLED == 'true'"

# ---- 2.0.0: every init question has a flag, and each answer lands where the tooling reads it ----
for badargs in "--git-host svn" "--tracker trello" "--deploy-mode sometimes" "--dev-url dev.example.com" "--tracker-url ftp://x" "--health-path health" "--git-url https://x.com/a#b"; do
  Pq="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pq" $badargs 2>&1); assert_exit "2.0: '$badargs' is rejected" 1 $? "$out"
  assert_eq "2.0: '$badargs' creates nothing" "" "$(ls -A "$Pq" | grep -v '^\.git$' || true)"
done
Pj="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pj" --name shop --team-key SHP --tracker jira --tracker-url 'https://acme.atlassian.net' --tracker-cloud-id 1a2b-3c \
  --dev-url https://dev.shop.io --qa-url https://qa.shop.io --staging-url 'https://stg.shop.io/?a=1&b=2' --production-url https://shop.io --health-path /healthz 2>&1)
assert_exit "2.0: a Jira install with every URL" 0 $? "$out"
Ej="$(cat "$Pj/scripts/pipeline/pipeline.env")"
for kv in 'TRACKER="jira"' 'TRACKER_URL="https://acme.atlassian.net"' 'TRACKER_CLOUD_ID="1a2b-3c"' 'TRACKER_TEAM_KEY="SHP"' 'DEV_URL="https://dev.shop.io"' \
          'STAGING_URL="https://stg.shop.io/?a=1&b=2"' 'HEALTH_PATH="/healthz"' 'GIT_HOST="github"' 'GIT_HOST_URL=""' 'DEPLOY_MODE="merge"'; do
  assert_contains "2.0: pipeline.env has $kv" "$Ej" "$kv"
done
grep -q '__' "$Pj/scripts/pipeline/pipeline.env" && bad "2.0: no placeholder survives in pipeline.env" || ok "2.0: no placeholder survives in pipeline.env"
out=$(bash "$INIT" --project-dir "$Pj" 2>&1); assert_contains "2.0: a re-run reads the tracker from pipeline.env" "$out" "tracker: jira"
# explicit deploys: no push or tag trigger survives in the CI files, and the dispatch path is still there
Px="$(mkp)"; out=$(bash "$INIT" --project-dir "$Px" --deploy-mode explicit 2>&1); assert_exit "2.0: --deploy-mode explicit" 0 $? "$out"
$PY - "$Px/.github/workflows/deploy.yml" <<'PY' && ok "2.0: explicit deploy.yml has only workflow_dispatch" || bad "2.0: explicit deploy.yml has only workflow_dispatch"
import yaml,sys
on=(lambda w: w.get("on") or w.get(True))(yaml.safe_load(open(sys.argv[1])))
sys.exit(0 if list(on)==["workflow_dispatch"] else 1)
PY
grep -q '#@on-merge' "$Px/.github/workflows/deploy.yml" "$Pm/.github/workflows/deploy.yml" && bad "2.0: no #@on-merge marker is installed" || ok "2.0: no #@on-merge marker is installed"
assert_contains "2.0: explicit is recorded" "$(cat "$Px/scripts/pipeline/pipeline.env")" 'DEPLOY_MODE="explicit"'
# GitLab: the CI files are included from .gitlab-ci.yml, and a self-hosted URL is recorded
Pl="$(mkp)"; git -C "$Pl" remote add origin https://git.acme.com/team/app.git
out=$(bash "$INIT" --project-dir "$Pl" --git-host gitlab --git-url https://git.acme.com --tracker gitlab 2>&1); assert_exit "2.0: GitLab install" 0 $? "$out"
assert_contains "2.0: GitLab and its self-hosted URL are reported" "$out" "host: gitlab (https://git.acme.com)"
for f in .gitlab/pipeline-gate.yml .gitlab/pipeline-deploy.yml .gitlab-ci.yml; do [ -f "$Pl/$f" ] && ok "2.0: GitLab gets $f" || bad "2.0: GitLab gets $f"; done
[ -e "$Pl/.github" ] && bad "2.0: GitLab gets no .github workflows" || ok "2.0: GitLab gets no .github workflows"
$PY - "$Pl" <<'PY' && ok "2.0: the GitLab CI files parse and the gate targets both branches" || bad "2.0: the GitLab CI files parse and the gate targets both branches"
import yaml,sys,os
d=sys.argv[1]; c=yaml.safe_load(open(os.path.join(d,".gitlab-ci.yml")))
g=yaml.safe_load(open(os.path.join(d,".gitlab/pipeline-gate.yml"))); p=yaml.safe_load(open(os.path.join(d,".gitlab/pipeline-deploy.yml")))
inc=[i["local"] for i in c["include"]]
rule=g["pipeline-gate"]["rules"][0]["if"]
ok = inc==["/.gitlab/pipeline-gate.yml","/.gitlab/pipeline-deploy.yml"] and '"master"' in rule and '"staging"' in rule \
  and all(k in p for k in ["ship-resolve","ship-build","ship-deploy-dev","ship-deploy-qa","ship-deploy-staging","ship-deploy-production"])
sys.exit(0 if ok else 1)
PY
assert_contains "2.0: GIT_HOST_URL is recorded" "$(cat "$Pl/scripts/pipeline/pipeline.env")" 'GIT_HOST_URL="https://git.acme.com"'
# an existing .gitlab-ci.yml gains the include once; one with its own include: list is left for /pipeline-init to merge
Pl2="$(mkp)"; printf 'stages: [test]
unit:
  script: [make test]
' > "$Pl2/.gitlab-ci.yml"
bash "$INIT" --project-dir "$Pl2" --git-host gitlab >/dev/null 2>&1; bash "$INIT" --project-dir "$Pl2" >/dev/null 2>&1
assert_eq "2.0: an existing .gitlab-ci.yml gains the include exactly once" "1|1" "$(grep -c '^include:' "$Pl2/.gitlab-ci.yml")|$(grep -c 'pipeline-gate.yml' "$Pl2/.gitlab-ci.yml")"
assert_contains "2.0: and keeps its own jobs" "$(cat "$Pl2/.gitlab-ci.yml")" "make test"
Pl3="$(mkp)"; printf 'include:
  - template: Security/SAST.gitlab-ci.yml
' > "$Pl3/.gitlab-ci.yml"; before="$(cat "$Pl3/.gitlab-ci.yml")"
out=$(bash "$INIT" --project-dir "$Pl3" --git-host gitlab 2>&1)
assert_eq "2.0: a .gitlab-ci.yml with its own include: list is not edited" "$before" "$(cat "$Pl3/.gitlab-ci.yml")"
assert_contains "2.0: and the merge is handed to /pipeline-init" "$out" "ACTION: add to the include: list"
# Bitbucket: one pipelines file; an existing one is never overwritten
Pb="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pb" --git-host bitbucket 2>&1); assert_exit "2.0: Bitbucket install" 0 $? "$out"
$PY - "$Pb/bitbucket-pipelines.yml" <<'PY' && ok "2.0: bitbucket-pipelines.yml parses, gates PRs, deploys on push and via custom: deploy" || bad "2.0: bitbucket-pipelines.yml parses, gates PRs, deploys on push and via custom: deploy"
import yaml,sys
p=yaml.safe_load(open(sys.argv[1]))["pipelines"]
sys.exit(0 if "pull-requests" in p and list(p["branches"])==["master","staging"] and "deploy" in p["custom"] and p["tags"] else 1)
PY
Pb2="$(mkp)"; printf 'pipelines:
  default:
    - step: {script: [make]}
' > "$Pb2/bitbucket-pipelines.yml"; before="$(cat "$Pb2/bitbucket-pipelines.yml")"
out=$(bash "$INIT" --project-dir "$Pb2" --git-host bitbucket --no-deploy-envs 2>&1)
assert_eq "2.0: an existing bitbucket-pipelines.yml is not edited" "$before" "$(cat "$Pb2/bitbucket-pipelines.yml")"
[ -f "$Pb2/bitbucket-pipelines.ship.yml" ] && grep -q 'ci-gate.sh' "$Pb2/bitbucket-pipelines.ship.yml" && ! grep -q 'Deploy' "$Pb2/bitbucket-pipelines.ship.yml" \
  && ok "2.0: the gate-only steps are written beside it" || bad "2.0: the gate-only steps are written beside it"
# --create-branches: pushes a missing base branch, creates staging from it, never moves an existing branch
Pc="$(mkp)"; Bc="$(mktemp -d)"; git init -q --bare "$Bc"; git -C "$Pc" remote add origin "$Bc"
out=$(bash "$INIT" --project-dir "$Pc" --create-branches 2>&1); assert_exit "2.0: --create-branches" 0 $? "$out"
assert_contains "2.0: reports what it created" "$out" "pushed master to origin; created staging on origin from master"
assert_eq "2.0: staging starts at the base sha" "$(git -C "$Bc" rev-parse master)" "$(git -C "$Bc" rev-parse staging)"
git -C "$Pc" -c user.email=a@a -c user.name=a commit -q --allow-empty -m later
out=$(bash "$INIT" --project-dir "$Pc" --create-branches 2>&1)
assert_contains "2.0: existing branches are left alone" "$out" "master and staging already exist on origin"
[ "$(git -C "$Bc" rev-parse master)" != "$(git -C "$Pc" rev-parse master)" ] && ok "2.0: an existing remote branch is never moved" || bad "2.0: an existing remote branch is never moved"
# an older install's copy of the test suite is removed when untouched, and kept when the owner changed it
Po="$(mkp)"; bash "$INIT" --project-dir "$Po" >/dev/null 2>&1; mkdir -p "$Po/tests/pipeline"
printf 'a\n' > "$Po/tests/pipeline/run-all.sh"; printf 'b\n' > "$Po/tests/pipeline/lib.sh"
{ cat "$Po/scripts/pipeline/.install-manifest"; (cd "$Po" && cksum tests/pipeline/run-all.sh tests/pipeline/lib.sh); } > "$Po/m" && mv "$Po/m" "$Po/scripts/pipeline/.install-manifest"
echo "# mine" >> "$Po/tests/pipeline/lib.sh"
out=$(bash "$INIT" --project-dir "$Po" 2>&1)
[ -e "$Po/tests/pipeline/run-all.sh" ] && bad "2.0: an untouched old test copy is removed" || ok "2.0: an untouched old test copy is removed"
[ -f "$Po/tests/pipeline/lib.sh" ] && ok "2.0: an old test file the owner changed is kept" || bad "2.0: an old test file the owner changed is kept"
assert_contains "2.0: the removal is reported" "$out" "removed tests/pipeline/run-all.sh"
# a checkout with core.autocrlf rewrites every line ending: that is not a hand edit
sed -i 's/$/\r/' "$Po/docs/pipeline/TICKETS.md" "$Po/scripts/pipeline/status.sh"
out=$(bash "$INIT" --project-dir "$Po" 2>&1)
case "$out" in *customised*) bad "2.0: CRLF-only differences are not reported as hand edits" "$out";; *) ok "2.0: CRLF-only differences are not reported as hand edits";; esac
echo "# a real edit" >> "$Po/scripts/pipeline/status.sh"
out=$(bash "$INIT" --project-dir "$Po" 2>&1); assert_contains "2.0: a real edit on a CRLF copy is still kept" "$out" "customised, kept scripts/pipeline/status.sh"

# ---- 3.0: one adapter per platform, chosen at install; retired tooling is cleaned up ----
Pa="$(mkp)"; out=$(bash "$INIT" --project-dir "$Pa" --git-host gitlab --tracker jira --tracker-url https://acme.atlassian.net 2>&1); assert_exit "3.0: gitlab + jira install" 0 $? "$out"
assert_eq "3.0: host.sh is the gitlab adapter" "# adapter: host=gitlab" "$(grep '^# adapter:' "$Pa/scripts/pipeline/host.sh")"
assert_eq "3.0: tracker.sh is the jira adapter" "# adapter: tracker=jira" "$(grep '^# adapter:' "$Pa/scripts/pipeline/tracker.sh")"
for f in lib/host-common.sh lib/tracker-common.sh; do [ -f "$Pa/scripts/pipeline/$f" ] && ok "3.0: installs $f" || bad "3.0: installs $f"; done
[ -e "$Pa/scripts/pipeline/adapters" ] && bad "3.0: the other platforms' adapters are not installed" || ok "3.0: the other platforms' adapters are not installed"
for a in market-researcher marketing-specialist; do [ -e "$Pa/.claude/agents/$a.md" ] && bad "3.0: no $a persona" || ok "3.0: no $a persona"; done
for t in research marketing; do [ -e "$Pa/docs/pipeline/_templates/$t.md" ] && bad "3.0: no $t.md template" || ok "3.0: no $t.md template"; done
# a platform flag that disagrees with the kept pipeline.env installs that adapter and says which line to change
out=$(bash "$INIT" --project-dir "$Pa" --tracker github 2>&1)
assert_eq "3.0: the adapter follows the flag" "# adapter: tracker=github" "$(grep '^# adapter:' "$Pa/scripts/pipeline/tracker.sh")"
assert_contains "3.0: and names the pipeline.env line to change" "$out" 'ACTION: set TRACKER="github" in scripts/pipeline/pipeline.env (it says jira)'
out=$(bash "$INIT" --project-dir "$Pa" 2>&1)
assert_eq "3.0: without a flag the adapter follows pipeline.env" "# adapter: tracker=jira" "$(grep '^# adapter:' "$Pa/scripts/pipeline/tracker.sh")"
Pc2="$(mkp)"; bash "$INIT" --project-dir "$Pc2" --tracker connector >/dev/null 2>&1
out=$(cd "$Pc2" && bash scripts/pipeline/tracker.sh view REP-1 2>&1); assert_exit "3.0: the connector adapter exits 3" 3 $? "$out"
[ -e "$Pc2/scripts/pipeline/lib/tracker-common.sh" ] && bad "3.0: the connector needs no tracker library" || ok "3.0: the connector needs no tracker library"
# an install from before 3.0: its removed personas and templates go, unless the owner edited them
Pr="$(mkp)"; bash "$INIT" --project-dir "$Pr" >/dev/null 2>&1
for f in .claude/agents/market-researcher.md .claude/agents/marketing-specialist.md docs/pipeline/_templates/research.md; do printf 'old %s\n' "$f" > "$Pr/$f"; done
(cd "$Pr" && cksum .claude/agents/market-researcher.md .claude/agents/marketing-specialist.md docs/pipeline/_templates/research.md) >> "$Pr/scripts/pipeline/.install-manifest"
echo "# my notes" >> "$Pr/.claude/agents/marketing-specialist.md"
out=$(bash "$INIT" --project-dir "$Pr" 2>&1)
for f in .claude/agents/market-researcher.md docs/pipeline/_templates/research.md; do
  [ -e "$Pr/$f" ] && bad "3.0: an untouched retired $f is removed" || ok "3.0: an untouched retired $f is removed"
done
[ -f "$Pr/.claude/agents/marketing-specialist.md" ] && ok "3.0: a retired file the owner edited is kept" || bad "3.0: a retired file the owner edited is kept"
assert_contains "3.0: and reported" "$out" "kept    .claude/agents/marketing-specialist.md (no longer part of the pipeline, but edited by hand"
grep -q 'market-researcher' "$Pr/scripts/pipeline/.install-manifest" && bad "3.0: retired files leave the manifest" || ok "3.0: retired files leave the manifest"
out=$(bash "$INIT" --project-dir "$Pr" --no-marketing 2>&1); assert_exit "3.0: --no-marketing is no longer a flag" 1 $? "$out"
[ -f "$Pr/.claude/agents/devops.md" ] && ok "3.0: installs the devops persona" || bad "3.0: installs the devops persona"
[ -x "$Pr/scripts/pipeline/handover.sh" ] && ok "3.0: installs handover.sh" || bad "3.0: installs handover.sh"
assert_contains "3.0: the start level defaults to analysis" "$(cat "$Pr/scripts/pipeline/pipeline.env")" 'PIPELINE_START_LEVEL="analysis"'
Ps="$(mkp)"; out=$(bash "$INIT" --project-dir "$Ps" --start-at Engineering 2>&1); assert_exit "3.0: --start-at engineering" 0 $? "$out"
assert_contains "3.0: the start level is recorded" "$(cat "$Ps/scripts/pipeline/pipeline.env")" 'PIPELINE_START_LEVEL="engineering"'
Ps2="$(mkp)"; out=$(bash "$INIT" --project-dir "$Ps2" --start-at marketing 2>&1); assert_exit "3.0: an unknown start level is refused" 1 $? "$out"
assert_eq "3.0: and creates nothing" "" "$(ls -A "$Ps2" | grep -v '^\.git$' || true)"

# profile install
P2="$(mktemp -d)"; git -C "$P2" init -q -b master; git -C "$P2" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P2" --profile reputabill 2>&1); assert_exit "profile install" 0 $? "$out"
assert_contains "profile context used" "$(cat "$P2/docs/pipeline/CONTEXT.md")" "Curate"
out=$(bash "$INIT" --project-dir "$P2" --profile nope 2>&1); assert_exit "unknown profile fails" 1 $? "$out"

summary
