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

# profile install
P2="$(mktemp -d)"; git -C "$P2" init -q -b master; git -C "$P2" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
out=$(bash "$INIT" --project-dir "$P2" --profile reputabill 2>&1); assert_exit "profile install" 0 $? "$out"
assert_contains "profile context used" "$(cat "$P2/docs/pipeline/CONTEXT.md")" "Curate"
out=$(bash "$INIT" --project-dir "$P2" --profile nope 2>&1); assert_exit "unknown profile fails" 1 $? "$out"

summary
