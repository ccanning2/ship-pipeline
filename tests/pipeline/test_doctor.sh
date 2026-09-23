#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "ticket-id.sh, base-ref.sh, enforcement.sh, doctor.sh"
new_repo
# the tracker is reached through its CLI (test_adapters.sh); here it is left to a connector, so the doctor lists it
use_tracker connector
tid() { (cd "$R" && bash scripts/pipeline/ticket-id.sh "$@" 2>&1); }
doc() { (cd "$R" && bash scripts/pipeline/doctor.sh "$@" 2>&1); }

# ---- ticket-id.sh: the one definition (acceptance test 2) ----
assert_eq "ticket-id: the regex is the fixture's" "REP-[0-9]+" "$(tid --regex)"
assert_eq "ticket-id: finds and uppercases" "REP-12" "$(tid "feature/rep-12-badge")"
assert_eq "ticket-id: first of several" "REP-3" "$(tid "REP-3 then REP-4")"
assert_eq "ticket-id: reads stdin" "REP-9" "$(cd "$R" && printf 'merge\nREP-9: x\n' | bash scripts/pipeline/ticket-id.sh)"
for s in macos-14 UTF-8 fix/utf-8-bug v1.45.0-jammy xREP-1 REP-1x; do
  tid "$s" >/dev/null; assert_exit "ticket-id: '$s' is not a ticket" 1 $?
done
unset_capability PIPELINE_TICKET_REGEX
assert_eq "ticket-id: no regex -> the team key" "REP-[0-9]+" "$(tid --regex)"
unset_capability TRACKER_TEAM_KEY
assert_eq "ticket-id: no key either -> the broad fallback" "[A-Z][A-Z0-9]+-[0-9]+" "$(tid --regex)"
set_capability TRACKER_TEAM_KEY '""'; set_capability PIPELINE_TICKET_REGEX '"${TRACKER_TEAM_KEY:-}-[0-9]+"'
assert_eq "ticket-id: an empty key never yields a bare -[0-9]+" "[A-Z][A-Z0-9]+-[0-9]+" "$(tid --regex)"
set_capability TRACKER_TEAM_KEY '"ABC"'; set_capability PIPELINE_TICKET_REGEX '"${TRACKER_TEAM_KEY:-}-[0-9]+"'
assert_eq "ticket-id: the template form follows the key" "ABC-12" "$(tid "feature/ABC-12-x macos-14")"
(cd "$R" && bash scripts/pipeline/ticket-id.sh "REP-1" >/dev/null); assert_exit "ticket-id: another team's id is not ours" 1 $?
set_capability TRACKER_TEAM_KEY '"REP"'; set_capability PIPELINE_TICKET_REGEX '"REP-[0-9]+"'
# a key defined AFTER the regex line must not crash anything that sources pipeline.env under set -u
set_capability PIPELINE_TICKET_REGEX '"${TRACKER_TEAM_KEY:-}-[0-9]+"'; set_capability TRACKER_TEAM_KEY '"REP"'
out=$(cd "$R" && bash -c 'set -euo pipefail; source scripts/pipeline/pipeline.env; echo sourced'); assert_eq "pipeline.env sources under set -u in any order" "sourced" "$out"
set_capability PIPELINE_TICKET_REGEX '"REP-[0-9]+"'

# ---- base-ref.sh ----
assert_eq "base-ref: default form" "origin/master" "$(cd "$R" && bash scripts/pipeline/base-ref.sh)"
assert_eq "base-ref: --branch" "master" "$(cd "$R" && bash scripts/pipeline/base-ref.sh --branch)"
assert_eq "base-ref: --staging" "staging" "$(cd "$R" && bash scripts/pipeline/base-ref.sh --staging)"
set_capability PIPELINE_REMOTE '"github"'; set_capability BASE_BRANCH '"trunk"'
assert_eq "base-ref: follows PIPELINE_REMOTE and BASE_BRANCH" "github/trunk" "$(cd "$R" && bash scripts/pipeline/base-ref.sh)"
unset_capability BASE_BRANCH
assert_eq "base-ref: no BASE_BRANCH -> a local trunk, never a guess" "master" "$(cd "$R" && bash scripts/pipeline/base-ref.sh --branch)"
set_capability PIPELINE_REMOTE '"origin"'; set_capability BASE_BRANCH '"master"'

# ---- enforcement.sh with a fake gh ----
FAKE="$(mktemp -d)"; cat > "$FAKE/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  "auth status") exit 0;;
  "repo view"*) echo "o/r";;
  "api repos/o/r/branches/"*"/protection"*) [ "${GH_MODE:-}" = pro ] && { echo "Pipeline Gate"; exit 0; }; echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1;;
  "api repos/o/r/rules/branches/"*) [ "${GH_MODE:-}" = pro ] && { echo ""; exit 0; }; echo 'gh: Upgrade to GitHub Pro (HTTP 403)' >&2; exit 1;;
  "variable get PIPELINE_DEPLOY_ENABLED") [ "${GH_MODE:-}" = pro ] && echo true; exit 0;;
esac
exit 1
GH
chmod +x "$FAKE/gh"
enf() { (cd "$R" && PIPELINE_GH_CMD="$FAKE/gh" bash scripts/pipeline/enforcement.sh 2>&1); }
out=$(enf); assert_contains "item 6: a 403 means local hook only" "$out" "ENFORCEMENT=local"
assert_contains "item 6: and says what that costs" "$out" "a human or another tool can push past it"
out=$(GH_MODE=pro enf); assert_contains "item 6: a required gate check means host enforcement" "$out" "ENFORCEMENT=host"
out=$(cd "$R" && PIPELINE_GH_CMD="/nonexistent/gh" bash scripts/pipeline/enforcement.sh 2>&1); assert_contains "item 6: no gh -> unknown" "$out" "ENFORCEMENT=unknown"

# ---- doctor.sh ----
before="$(cd "$R" && git status --porcelain; git for-each-ref)"
out=$(doc --offline); assert_contains "doctor: summary line" "$out" "doctor:"
assert_eq "doctor: read-only (no file or ref changed)" "$before" "$(cd "$R" && git status --porcelain; git for-each-ref)"
assert_contains "doctor: no remote is a FAIL" "$out" "FAIL  git: no remote named 'origin'"
assert_contains "doctor: team key checked" "$out" "PASS  pipeline.env: TRACKER_TEAM_KEY=REP"
assert_contains "doctor: narrow regex passes" "$out" "ticket ids match"
# acceptance test 6: every tracker item is listed for the connector step
for item in "label group 'Stage'" "label group 'Owner'" "labels (Kind): story,eng,defect,follow-up" "workflow status 'In Review'" "workflow status 'Canceled'"; do
  assert_contains "acceptance 6: doctor lists $item" "$out" "$item"
done

# a remote with shared history
BARE="$(mktemp -d)"; git init -q --bare "$BARE"; g remote add origin "$BARE"; g push -q origin master; g push -q origin master:staging
out=$(doc --offline); g fetch -q origin; out=$(doc --offline)
assert_contains "doctor: shared history passes" "$out" "PASS  git: origin/master shares history"
assert_contains "doctor: staging on base passes" "$out" "PASS  git: staging is on master"
assert_contains "item 9: a remote that is not the configured host is flagged" "$out" "which is not github.com"
use_host gitlab; set_capability GIT_HOST_URL '"https://git.acme.com"'; g remote set-url origin https://git.acme.com/team/app.git
out=$(doc --offline); assert_contains "2.0: a self-hosted GIT_HOST_URL is matched against the remote" "$out" "PASS  git: origin is https://git.acme.com/team/app.git (gitlab)"
g remote set-url origin "$BARE"
assert_contains "2.0: GitLab needs .gitlab-ci.yml to include the gate" "$out" "FAIL  workflows: .gitlab-ci.yml does not include"
use_host github; set_capability GIT_HOST_URL '""'
out=$(doc); assert_contains "doctor: online check reads the remote too" "$out" "shares history"

# acceptance test 1: a host-created README-only first commit
U="$(mktemp -d)"; git init -q -b master "$U"; echo readme > "$U/README.md"; git -C "$U" add -A; git -C "$U" -c user.email=a@a -c user.name=a commit -qm "Initial commit"
BARE2="$(mktemp -d)"; git init -q --bare "$BARE2"; git -C "$U" push -q "$BARE2" master
g remote set-url origin "$BARE2"; g fetch -q origin 2>/dev/null
out=$(doc); assert_contains "acceptance 1: unrelated history is a FAIL" "$out" "FAIL  git: local history and origin/master share no commit"
assert_exit "acceptance 1: doctor exits 1 on a FAIL" 1 "$(doc >/dev/null; echo $?)"
g remote add gitlab "$BARE"
out=$(doc --offline); assert_contains "item 9: other remotes are named and ignored" "$out" "other remotes (gitlab )"
set_capability PIPELINE_REMOTE '"gitlab"'; g fetch -q gitlab
out=$(doc --offline); assert_contains "item 9: PIPELINE_REMOTE picks the remote" "$out" "PASS  git: gitlab/master shares history"
set_capability PIPELINE_REMOTE '"origin"'

# warnings a broad regex, leftovers and stale literals raise
set_capability PIPELINE_TICKET_REGEX '"[A-Z][A-Z0-9]+-[0-9]+"'
out=$(doc --offline); assert_contains "item 3: a broad regex is a WARN" "$out" "also matches macos-14"
set_capability PIPELINE_TICKET_REGEX '"REP-[0-9]+"'
printf '# Append to .gitignore\n' >> "$R/.gitignore"; touch "$R/.gitignore.pipeline"
out=$(doc --offline); assert_contains "item 7: leftover file flagged" "$out" ".gitignore.pipeline is an installer leftover"
assert_contains "item 7: leftover instruction line flagged" "$out" "instruction line"
set_capability BASE_BRANCH '"main"'; mkdir -p "$R/.claude/agents"; echo 'git diff origin/master...HEAD' > "$R/.claude/agents/x.md"
out=$(doc --offline); assert_contains "item 2: a stale master literal is flagged" "$out" ".claude/agents/x.md"
set_capability BASE_BRANCH '"master"'; rm -f "$R/.claude/agents/x.md"

# host checks with the fake gh
out=$(cd "$R" && PIPELINE_GH_CMD="$FAKE/gh" bash scripts/pipeline/doctor.sh 2>&1)
assert_contains "item 6: doctor reports local-hook-only enforcement" "$out" "WARN  host: Enforcement: local hook only"
# upgrading a v1.0.0 install: every project-owned leftover is an [upgrade] finding, and nothing FAILs because of it
legacy_env; use_tracker linear; mkdir -p "$R/.github/workflows"
cat > "$R/.github/workflows/pipeline-gate.yml" <<'YML'
name: Pipeline Gate
on:
  pull_request:
    branches: [master, staging]
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - run: t=$(printf '%s' "$HEAD_REF" | grep -oiE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
YML
printf 'on:\n  push:\n    branches: [master, staging]\njobs: {}\n' > "$R/.github/workflows/deploy.yml"
out=$(doc --offline)
for f in "PIPELINE_REMOTE is not set" "also matches macos-14" "pipeline-gate.yml predates v1.1.0" "deploy.yml runs on every push"; do
  case "$out" in *"$f"*"[upgrade: run /pipeline-init to review the change]"*) ok "upgrade: '$f' is marked [upgrade]";; *) bad "upgrade: '$f' is marked [upgrade]" "$out";; esac
done
case "$(printf '%s\n' "$out" | grep '^FAIL' | grep -v "remote named\|share no commit\|files: missing" || true)" in "") ok "upgrade: a v1.0.0 install raises no FAIL of its own";; *) bad "upgrade: a v1.0.0 install raises no FAIL of its own" "$out";; esac
summary
