#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "tracker.sh, host.sh, connect.sh, ci-gate.sh, allow-commands.sh (CLI adapters)"
new_repo
trk() { (cd "$R" && bash scripts/pipeline/tracker.sh "$@" 2>&1); }

# ---- TRACKER=connector: every verb hands the step to the MCP connector ----
use_tracker connector
out=$(trk view REP-1); assert_exit "connector: exit 3" 3 $? "$out"
assert_contains "connector: says to use the connector" "$out" "MCP connector"
# the doctor catches an adapter that no longer matches pipeline.env (TRACKER changed by hand)
set_capability TRACKER '"jira"'
out=$(cd "$R" && bash scripts/pipeline/doctor.sh --offline 2>&1); assert_contains "doctor: a mismatched adapter is a FAIL" "$out" "FAIL  files: tracker.sh is the connector adapter, but pipeline.env says jira"
# a missing credential is one clear error, found before any API call (not a second, misleading one after it)
if command -v jq >/dev/null 2>&1; then
  use_tracker linear
  out=$(cd "$R" && env -u LINEAR_API_KEY PIPELINE_TRACKER_CONFIG="$(mktemp -d)" bash scripts/pipeline/tracker.sh check 2>&1); assert_exit "linear: no API key is an error" 1 $? "$out"
  assert_eq "linear: and exactly one line that says how to sign in" "tracker.sh: no Linear API key: the owner runs bash scripts/pipeline/connect.sh login once" "$out"
  use_tracker jira; set_capability TRACKER_URL '""'
  out=$(cd "$R" && PIPELINE_TRACKER_CONFIG="$(mktemp -d)" JIRA_API_TOKEN=x bash scripts/pipeline/tracker.sh check 2>&1); assert_exit "jira: no site is an error" 1 $? "$out"
  assert_contains "jira: the missing site is named" "$out" "TRACKER_URL (the Jira site) is not set"
fi
# the doctor flags only the placeholders init writes, not a real URL that happens to contain "example"
use_tracker connector; set_capability DEV_URL '"https://dev.shop.example"'; set_capability QA_URL '"https://qa.x.example.invalid"'
out=$(cd "$R" && bash scripts/pipeline/doctor.sh --offline 2>&1)
assert_contains "doctor: a .example.invalid URL is a placeholder" "$out" "WARN  pipeline.env: QA_URL STAGING_URL PRODUCTION_URL still a placeholder"
case "$out" in *"DEV_URL QA_URL"*) bad "doctor: a real .example URL is not a placeholder" "$out";; *) ok "doctor: a real .example URL is not a placeholder";; esac

# ---- GitHub Issues through a fake gh that keeps each issue's labels in a file ----
use_tracker github
ST="$(mktemp -d)"; export ST
cat > "$R/fake-gh.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$ST/log"
lab() { cat "$ST/labels.$1" 2>/dev/null; }
case "$1 $2" in
  "auth status") exit 0;;
  "repo view") echo "o/r";;
  "issue view")
    n="$3"; case "$*" in
      *'startswith("stage:")'*) lab "$n" | grep '^stage:' | paste -sd, -;;
      *'startswith("owner:")'*) lab "$n" | grep '^owner:' | paste -sd, -;;
      *'startswith("state:")'*) lab "$n" | grep '^state:' | paste -sd, -;;
      *) echo "ID: REP-$n"; echo "Title: t";;
    esac;;
  "issue edit")
    n="$3"; shift 3
    while [ $# -gt 0 ]; do case "$1" in
      --add-label) echo "$2" >> "$ST/labels.$n"; shift 2;;
      --remove-label) for l in $(printf '%s' "$2" | tr ',' ' '); do grep -vxF "$l" "$ST/labels.$n" > "$ST/t"; mv "$ST/t" "$ST/labels.$n"; done; shift 2;;
      *) shift;; esac; done;;
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment"|"issue close"|"issue reopen") ;;
  "api repos/o/r/issues/42") echo 9042;;
  "api -X") ;;
  "label list") cat "$ST/repo-labels" 2>/dev/null;;
  "label create") echo "$3" >> "$ST/repo-labels";;
  *) echo "fake-gh: unexpected: $*" >&2; exit 1;;
esac
FAKE
chmod +x "$R/fake-gh.sh"; echo "fake-gh.sh" >> "$R/.git/info/exclude"
export PIPELINE_GH_CMD="$R/fake-gh.sh"
out=$(trk check); assert_exit "github: check" 0 $? "$out"; assert_contains "github: check names the repository" "$out" "GitHub Issues of o/r"
echo "stage:product" > "$ST/labels.7"; echo "owner:product-owner" >> "$ST/labels.7"
out=$(trk set REP-7 stage=dev owner=engineer); assert_exit "github: set Stage and Owner" 0 $? "$out"
assert_eq "github: one Stage and one Owner label afterwards" "owner:engineer,stage:dev" "$(sort "$ST/labels.7" | paste -sd, -)"
out=$(trk set REP-7 stage=launch); assert_exit "github: an unknown stage is refused" 1 $? "$out"
assert_contains "github: and the allowed stages are listed" "$out" "analysis"
out=$(trk view ABC-7); assert_exit "github: another team's id is refused" 1 $? "$out"
out=$(trk create REP-7 eng 'Badge endpoint' --body 'FR-1, AC-1'); assert_exit "github: create a child" 0 $? "$out"
assert_eq "github: create prints the new id" "REP-42" "$out"
assert_contains "github: the child is created with its kind label" "$(cat "$ST/log")" "issue create --title Badge endpoint --body FR-1, AC-1 --label eng"
assert_contains "github: and linked as a sub-issue of the parent" "$(cat "$ST/log")" "sub_issues -F sub_issue_id=9042"
out=$(trk create REP-7 epic 'x' --body 'y'); assert_exit "github: an unknown kind is refused" 1 $? "$out"
out=$(trk comment REP-7); assert_exit "github: a comment needs a body" 1 $? "$out"
printf 'in-progress work\n' > "$R/body.txt"
out=$(trk comment REP-7 --body-file "$R/body.txt"); assert_exit "github: comment from a file" 0 $? "$out"
echo "state:in-progress" > "$ST/labels.9"
out=$(trk state REP-9 fixed); assert_exit "github: state fixed" 0 $? "$out"
assert_eq "github: fixed replaces in-progress" "state:fixed" "$(cat "$ST/labels.9")"
out=$(trk state REP-9 verified); assert_contains "github: verified closes the issue as completed" "$(cat "$ST/log")" "issue close 9 --reason completed"
assert_eq "github: and drops the state label" "" "$(cat "$ST/labels.9")"
out=$(trk state REP-9 shipped); assert_exit "github: an unknown state is refused" 1 $? "$out"
out=$(trk handoff REP-7 qa qa-tester --body 'Handoff: engineer → qa'); assert_exit "github: handoff" 0 $? "$out"
assert_eq "github: handoff moves both groups" "owner:qa-tester,stage:qa" "$(sort "$ST/labels.7" | paste -sd, -)"
assert_contains "github: and posts the comment" "$(cat "$ST/log")" "issue comment 7 --body Handoff: engineer → qa"
# setup: --check reports and changes nothing; setup creates every label once and records the state map
rm -f "$ST/repo-labels" "$R/scripts/pipeline/tracker.map"; : > "$ST/log"
out=$(trk setup --check); assert_exit "github: setup --check with nothing set up exits 2" 2 $? "$out"
assert_contains "github: it lists a Stage label" "$out" "MISSING stage:go-live"
assert_contains "github: it lists a kind label" "$out" "MISSING defect"
grep -q "label create" "$ST/log" && bad "github: --check creates nothing" || ok "github: --check creates nothing"
out=$(trk setup); assert_exit "github: setup" 0 $? "$out"
want=$(( $(awk -F'|' '$1=="label-group" {n+=split($3,a,",")} $1=="labels" {n+=split($3,a,",")} END {print n}' "$R/scripts/pipeline/tracker-schema.txt") + 2 ))
assert_eq "github: setup creates every label (groups, kinds, two state labels)" "$want" "$(grep -c '^label create' "$ST/log")"
[ -f "$R/scripts/pipeline/tracker.map" ] && grep -q '^state:fixed|' "$R/scripts/pipeline/tracker.map" && ok "github: setup writes tracker.map" || bad "github: setup writes tracker.map"
out=$(trk setup --check); assert_exit "github: afterwards --check passes" 0 $? "$out"
unset PIPELINE_GH_CMD

# ---- the doctor asks the tracker through tracker.sh ----
out=$(cd "$R" && PIPELINE_GH_CMD="$R/fake-gh.sh" bash scripts/pipeline/doctor.sh 2>&1)
assert_contains "doctor: the tracker check goes through the CLI" "$out" "PASS  tracker: GitHub Issues of o/r"
assert_contains "doctor: and the workspace comparison too" "$out" "PASS  tracker: every label, field and status the pipeline needs exists"
case "$out" in *"TODO  tracker"*) bad "doctor: no connector TODO lines when a CLI is configured" "$out";; *) ok "doctor: no connector TODO lines when a CLI is configured";; esac
rm -f "$ST/repo-labels"
out=$(cd "$R" && PIPELINE_GH_CMD="$R/fake-gh.sh" bash scripts/pipeline/doctor.sh 2>&1)
assert_contains "doctor: missing tracker items are a FAIL with the fix" "$out" "Create them: bash scripts/pipeline/tracker.sh setup"

# ---- allow-commands.sh: a persona's only shell command is the tracker adapter ----
H="$REPO_SRC/scripts/pipeline/hooks/allow-commands.sh"
ac() { $PY -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | CLAUDE_PROJECT_DIR=/repo bash "$H" scripts/pipeline/tracker.sh >/dev/null 2>&1; echo $?; }
assert_eq "allow-commands: the adapter is allowed" 0 "$(ac "bash scripts/pipeline/tracker.sh view REP-1")"
assert_eq "allow-commands: ./ and a multi-line single-quoted body are allowed" 0 "$(ac "bash ./scripts/pipeline/tracker.sh comment REP-1 --body 'line one; with | and \$x
line two'")"
assert_eq "allow-commands: an escaped quote inside the body is allowed" 0 "$(ac "bash scripts/pipeline/tracker.sh comment REP-1 --body 'it'\\''s'")"
for c in "bash scripts/pipeline/tracker.sh view REP-1; rm -rf x" "bash scripts/pipeline/tracker.sh view \$(id)" 'bash scripts/pipeline/tracker.sh comment REP-1 --body "x `id`"' \
         "bash scripts/pipeline/tracker.sh view REP-1 > out.txt" "bash scripts/pipeline/tracker.sh view REP-1 && git push" "bash scripts/pipeline/promote.sh REP-1 dev" \
         "rm -rf x" "bash scripts/pipeline/tracker.sh view REP-1
git push" "bash scripts/pipeline/tracker.sh comment REP-1 --body 'unclosed"; do
  assert_eq "allow-commands: blocked: $(printf '%s' "$c" | head -1)" 2 "$(ac "$c")"
done
NB="$(mktemp -d)"; for x in jq python3 python py; do printf '#!/bin/sh
exit 1
' > "$NB/$x"; chmod +x "$NB/$x"; done   # a jq and pythons that cannot parse
out=$(printf '{"tool_input":{"command":"ls"}}' | PATH="$NB:$PATH" bash "$H" scripts/pipeline/tracker.sh 2>&1); assert_exit "allow-commands: fails closed when it cannot read the command" 2 $? "$out"
# every Bash-limited persona's frontmatter hook really is this one
cd "$REPO_SRC"; AD=.claude/agents; [ -d agents ] && [ -f .claude-plugin/plugin.json ] && AD=agents
for a in product-owner business-analyst; do
  cmd=$($PY -c 'import yaml,sys; s=open(sys.argv[1]).read().split("\n---\n")[0].lstrip("---\n"); h=yaml.safe_load(s)["hooks"]["PreToolUse"]; print([x for x in h if x["matcher"]=="Bash"][0]["hooks"][0]["command"])' "$AD/$a.md")
  rc() { printf '%s' "$1" | $PY -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' | CLAUDE_PROJECT_DIR="$REPO_SRC" bash -c "$cmd" >/dev/null 2>&1; echo $?; }
  assert_eq "$a: its Bash hook blocks git, allows view and children, and blocks every write verb" "2|0|0|2|2|2" \
    "$(rc 'git push origin HEAD:master')|$(rc 'bash scripts/pipeline/tracker.sh view REP-1')|$(rc 'bash scripts/pipeline/tracker.sh children REP-1')|$(rc "bash scripts/pipeline/tracker.sh create REP-1 eng 'x' --body 'y'")|$(rc "bash scripts/pipeline/tracker.sh handoff REP-1 build engineer --body 'x'")|$(rc 'bash scripts/pipeline/tracker.sh setup')"
done
cd - >/dev/null

# ---- guard-merge.sh: glab, host.sh and the Bitbucket infra/ route are gated too ----
GH="$R/scripts/pipeline/hooks/guard-merge.sh"
guard() { $PY -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | (cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$GH" 2>&1); }
g checkout -qb chore/no-ticket
out=$(guard "glab mr merge 12 --yes"); assert_exit "guard: glab mr merge needs a ticket" 2 $? "$out"
out=$(guard "glab api -X PUT projects/:id/merge_requests/12/merge"); assert_exit "guard: a glab API merge needs a ticket" 2 $? "$out"
out=$(guard "glab api -X POST projects/:id/repository/tags -f tag_name=v1.0.0"); assert_exit "guard: a glab API tag needs the production gate" 2 $? "$out"
out=$(guard "glab mr update 12 --label infra"); assert_exit "guard: an agent never adds the infra label on GitLab" 2 $? "$out"
out=$(guard "bash scripts/pipeline/host.sh merge chore/no-ticket master x"); assert_exit "guard: host.sh merge into the base branch needs a ticket" 2 $? "$out"
out=$(guard "bash scripts/pipeline/host.sh set-ref refs/tags/v1.0.0 abc"); assert_exit "guard: host.sh set-ref of a tag needs the production gate" 2 $? "$out"
out=$(guard "glab mr list"); assert_exit "guard: read-only glab is fine" 0 $? "$out"
out=$(guard "git push origin infra/bump"); assert_exit "guard: an infra/ branch is ordinary on GitHub" 0 $? "$out"
set_capability GIT_HOST '"bitbucket"'
out=$(guard "git push origin HEAD:infra/bump"); assert_exit "guard: on Bitbucket an agent never pushes an infra/ branch" 2 $? "$out"
set_capability GIT_HOST '"github"'; g checkout -q master

# ---- ci-gate.sh: the PR/MR gate the GitLab and Bitbucket CI files run ----
cg() { (cd "$R" && bash scripts/pipeline/ci-gate.sh "$@" 2>&1); }
out=$(cg feature/x "t" some-branch false); assert_exit "ci-gate: a request into another branch passes" 0 $? "$out"
out=$(cg chore/x "no ticket" master true); assert_exit "ci-gate: infra skips the ticket gate" 0 $? "$out"
out=$(cg chore/x "no ticket" master false); assert_exit "ci-gate: no ticket into the base branch fails" 1 $? "$out"
assert_contains "ci-gate: and says how to mark it infra" "$out" "marks it infra"
branch feature/REP-61-x; ready_build REP-61 feature no; built REP-61; g checkout -q master; g update-ref refs/remotes/origin/master master
out=$(cd "$R" && git checkout -q feature/REP-61-x && bash scripts/pipeline/ci-gate.sh feature/REP-61-x "REP-61: x" master false 2>&1); assert_exit "ci-gate: a ready ticket passes the dev gate" 0 $? "$out"
g checkout -q master

# ---- promote.sh with DEPLOY_MODE=explicit dispatches every environment ----
new_repo; set_capability DEPLOY_MODE '"explicit"'; branch feature/REP-71-x; ready_build REP-71 chore no; built REP-71
GL2="$(mktemp)"; export GL2
cat > "$R/fake-gh2.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$GL2"
case "$1 $2" in "workflow run") ;; "run list") echo 123;; "run watch") ;; *) exit 1;; esac
FAKE
chmod +x "$R/fake-gh2.sh"; echo "fake-gh2.sh" >> "$R/.git/info/exclude"
out=$(cd "$R" && env -u PIPELINE_DEPLOY_CMD PIPELINE_NO_PUSH=1 PIPELINE_GH_CMD="$R/fake-gh2.sh" PIPELINE_SMOKE_CMD=true PIPELINE_DISPATCH_SETTLE=0 bash scripts/pipeline/promote.sh REP-71 dev 2>&1)
assert_exit "explicit: dev promote" 0 $? "$out"
assert_contains "explicit: dev is dispatched on the base branch" "$(cat "$GL2")" "workflow run deploy.yml --ref master -f env=dev"
assert_contains "explicit: and its run is watched" "$(cat "$GL2")" "run watch 123 --exit-status"
: > "$GL2"; set_capability DEPLOY_MODE '"merge"'; built REP-71
out=$(cd "$R" && env -u PIPELINE_DEPLOY_CMD PIPELINE_NO_PUSH=1 PIPELINE_GH_CMD="$R/fake-gh2.sh" PIPELINE_SMOKE_CMD=true PIPELINE_DISPATCH_SETTLE=0 bash scripts/pipeline/promote.sh REP-71 dev 2>&1)
assert_exit "merge: a second dev promote" 0 $? "$out"
grep -q "workflow run" "$GL2" && bad "merge: dev is not dispatched (the push deploys it)" "$(cat "$GL2")" || ok "merge: dev is not dispatched (the push deploys it)"

# ---- connect.sh: which tools a project needs, and a sign-in never happens without a terminal ----
CF="$(mktemp -d)"; printf 'LINEAR_API_KEY=x\n' > "$CF/linear.env"
set_capability GIT_HOST '"bitbucket"'; set_capability TRACKER '"linear"'
out=$(cd "$R" && PIPELINE_TRACKER_CONFIG="$CF" bash scripts/pipeline/connect.sh status 2>&1); rc=$?
for t in git jq curl bitbucket linear; do assert_contains "connect: bitbucket + linear needs $t" "$out" "TOOL $t "; done
assert_contains "connect: a saved Linear key counts as signed in" "$out" "TOOL linear installed=n/a signed-in=yes"
assert_contains "connect: a missing Bitbucket token is reported" "$out" "TOOL bitbucket installed=n/a signed-in=no"
case "$rc" in 4|5) ok "connect: status is not ready ($rc)";; *) bad "connect: status is not ready" "rc=$rc $out";; esac
set_capability GIT_HOST '"gitlab"'; set_capability TRACKER '"jira"'
out=$(cd "$R" && PIPELINE_TRACKER_CONFIG="$CF" bash scripts/pipeline/connect.sh status 2>&1)
for t in glab acli jira; do assert_contains "connect: gitlab + jira needs $t" "$out" "TOOL $t "; done
if ! (: </dev/tty) 2>/dev/null; then
  out=$(cd "$R" && PIPELINE_TRACKER_CONFIG="$CF" bash scripts/pipeline/connect.sh login </dev/null 2>&1); assert_exit "connect: login without a terminal stops" 4 $? "$out"
  assert_contains "connect: and says where to run it" "$out" "run it in your own terminal"
fi
summary
