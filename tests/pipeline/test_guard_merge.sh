#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "guard-merge.sh (branch/tag gates)"
hook() {
  local cmd="$1" json
  json=$($PY -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  (cd "$R" && printf '%s' "$json" | CLAUDE_PROJECT_DIR="$R" bash scripts/pipeline/hooks/guard-merge.sh 2>&1)
}
new_repo
out=$(hook "ls -la"); assert_exit "unrelated command allowed" 0 $? "$out"
out=$(hook "git status"); assert_exit "git status on master allowed" 0 $? "$out"
out=$(cd "$R" && printf 'not json' | CLAUDE_PROJECT_DIR="$R" bash scripts/pipeline/hooks/guard-merge.sh 2>&1); assert_exit "malformed input ignored" 0 $? "$out"

branch feature/REP-90-x; ready_build REP-90 feature yes
out=$(hook "git push -u origin feature/REP-90-x"); assert_exit "push feature branch allowed" 0 $? "$out"
out=$(hook "git push origin feature/master-menu"); assert_exit "branch containing 'master' allowed" 0 $? "$out"
out=$(hook "git merge master"); assert_exit "merge master into feature allowed" 0 $? "$out"
out=$(hook "git push origin HEAD:master"); assert_exit "push to master before build done blocked (dev gate)" 2 $? "$out"
assert_contains "block names dev gate" "$out" "dev gate"
out=$(hook "gh pr merge 3 --merge"); assert_exit "PR merge = dev gate, blocked" 2 $? "$out"
out=$(hook "git push origin HEAD:staging"); assert_exit "push to staging branch blocked (qa gate)" 2 $? "$out"
assert_contains "block names qa gate" "$out" "qa gate"
out=$(hook "git push origin v1.0.0"); assert_exit "tag push blocked (production gate)" 2 $? "$out"
assert_contains "block names production gate" "$out" "production gate"
out=$(hook "git push --tags"); assert_exit "push --tags blocked" 2 $? "$out"
out=$(hook "gh release create v1.0.0"); assert_exit "gh release blocked" 2 $? "$out"
out=$(PIPELINE_BYPASS=1 hook "git push origin master"); assert_exit "PIPELINE_BYPASS allows" 0 $? "$out"; assert_contains "bypass announced" "$out" "bypassed"

built REP-90; head=$(g rev-parse HEAD)
out=$(hook "git push origin HEAD:master"); assert_exit "push to master after build done allowed" 0 $? "$out"
out=$(hook "gh api -X PUT repos/o/r/pulls/3/merge -f merge_method=merge"); assert_exit "REST PR merge after build done allowed" 0 $? "$out"
out=$(hook "git push origin HEAD:staging"); assert_exit "staging push still blocked without dev-check" 2 $? "$out"
record REP-90 Dev "$head"; dev_check REP-90 pass "$head"; g update-ref refs/heads/master "$head"
out=$(hook "git push origin $head:refs/heads/staging"); assert_exit "staging push allowed after dev-check" 0 $? "$out"
out=$(hook "git push origin v1.0.0"); assert_exit "tag still blocked before sign-off" 2 $? "$out"
record REP-90 QA "$head"; qa_report REP-90 pass "$head"; record REP-90 Staging "$head"; signoff REP-90 approved "$head"
golive REP-90
out=$(hook "git push origin refs/tags/v1.0.0"); assert_exit "tag push allowed after go-live + version" 0 $? "$out"
out=$(hook "git push origin v2.0.0"); assert_exit "tag push allowed (gate reads Version from releases, tag name not checked here)" 0 $? "$out"

g checkout -q master
out=$(hook "git merge feature/rep-91-other"); assert_exit "merge unknown ticket into master blocked" 2 $? "$out"
out=$(hook "git merge --ff-only feature/REP-90-x"); assert_exit "merge ready branch into master allowed (ref gated)" 0 $? "$out"
out=$(hook "git push"); assert_exit "bare push on master without ticket blocked" 2 $? "$out"; assert_contains "explains missing ticket" "$out" "no ticket id"
out=$(hook "git merge feature/* --no-edit"); assert_exit "glob in command not expanded" 2 $? "$out"

# cloud: session branch, ticket from env / file
new_repo; branch claude/session-xyz
out=$(PIPELINE_TICKET=REP-98 hook "gh api -X PUT repos/o/r/pulls/12/merge"); assert_exit "PIPELINE_TICKET used; unready blocked" 2 $? "$out"; assert_contains "names env ticket" "$out" "REP-98"
ready_build REP-98 chore no; built REP-98
out=$(PIPELINE_TICKET=REP-98 hook "gh api -X PUT repos/o/r/pulls/12/merge"); assert_exit "PIPELINE_TICKET ready allowed" 0 $? "$out"
echo "REP-98" > "$R/.claude/.pipeline-ticket"
out=$(hook "gh pr merge 12 --merge"); assert_exit ".pipeline-ticket file used; allowed" 0 $? "$out"
echo "REP-99" > "$R/.claude/.pipeline-ticket"
out=$(hook "gh pr merge 12 --merge"); assert_exit ".pipeline-ticket unready blocked" 2 $? "$out"
out=$(hook "bash scripts/pipeline/promote.sh REP-99 dev"); assert_exit "promote.sh itself not blocked (it gates)" 0 $? "$out"

# ---- the command is parsed, not scanned: only a real git/gh command counts ----
new_repo   # on master, no ticket anywhere
out=$(hook 'echo "git push origin master" | tail -1'); assert_exit "push text inside echo is not a push" 0 $? "$out"
out=$(hook 'git log --oneline | grep "git merge"'); assert_exit "merge text inside grep is not a merge" 0 $? "$out"
out=$(hook 'git commit -m "wip; git push origin HEAD:master"'); assert_exit "a quoted ; does not split the command" 0 $? "$out"
out=$(hook "$(printf 'cat > notes.txt <<EOF\ngit push origin master\nEOF')"); assert_exit "heredoc body is not a command" 0 $? "$out"
out=$(hook 'git status && git push origin HEAD:master'); assert_exit "the push in a compound command is still gated" 2 $? "$out"
out=$(hook 'FOO=1 git -C . push origin "HEAD:master" 2>&1 | tail -3'); assert_exit "env prefix, git -C, quoted refspec, pipe: still a push to master" 2 $? "$out"
out=$(hook 'git push origin runner-macos-14:refs/heads/macos-14'); assert_exit "a branch that looks like a broad ticket id is not a promotion" 0 $? "$out"
out=$(hook 'git push origin master 2>/dev/null'); assert_exit "redirection is not a refspec" 2 $? "$out"
out=$(hook 'bash -c "git push origin HEAD:master"'); assert_exit "bash -c does not hide a push" 2 $? "$out"
out=$(hook 'sudo -E git push origin HEAD:master'); assert_exit "sudo does not hide a push" 2 $? "$out"
out=$(hook 'echo master | xargs git push origin'); assert_exit "xargs does not hide a push" 2 $? "$out"
out=$(hook 'eval git push origin HEAD:master'); assert_exit "eval does not hide a push" 2 $? "$out"
out=$(hook 'timeout 30 git push origin HEAD:master'); assert_exit "timeout does not hide a push" 2 $? "$out"
out=$(hook 'bash scripts/build.sh --push'); assert_exit "running a script is not a push" 0 $? "$out"
out=$(hook 'gh'); assert_exit "bare gh is fine (no empty-array error)" 0 $? "$out"

# ---- ways forward, and no agent-settable way around ----
out=$(hook "git push"); assert_exit "bare push on master without ticket blocked" 2 $? "$out"
assert_contains "block names the infra route" "$out" "'infra' label"
assert_contains "block names the owner's own terminal" "$out" "own terminal"
assert_contains "block tells the agent not to work around it" "$out" "Do not try to get around"
out=$(hook "git push --force-with-lease origin master"); assert_exit "acceptance 3: force push to master without ticket blocked" 2 $? "$out"
assert_contains "acceptance 3: force push names a human route" "$out" "own terminal"
case "$out" in *PIPELINE_BYPASS*) bad "acceptance 3: block does not suggest an override the agent could set" "$out";; *) ok "acceptance 3: block does not suggest an override the agent could set";; esac
branch feature/REP-95-x; ready_build REP-95 chore no; built REP-95
out=$(hook "git push origin HEAD:master"); assert_exit "ready ticket may push to master" 0 $? "$out"
out=$(hook "git push -f origin HEAD:master"); assert_exit "but never force-push it, even when ready" 2 $? "$out"
out=$(hook "git push origin +HEAD:staging"); assert_exit "+refspec is a force push" 2 $? "$out"
out=$(hook "git push origin :staging"); assert_exit "deleting staging blocked" 2 $? "$out"
out=$(hook "git push origin --delete v1.0.0"); assert_exit "deleting a version tag blocked" 2 $? "$out"
out=$(hook "git push --all origin"); assert_exit "bulk push blocked" 2 $? "$out"
out=$(hook "git push --mirror origin"); assert_exit "mirror push blocked" 2 $? "$out"
out=$(hook "git push -f origin feature/REP-95-x"); assert_exit "force push of a ticket branch is not gated here" 0 $? "$out"
out=$(hook "gh pr edit 7 --add-label infra"); assert_exit "agent cannot add the infra label" 2 $? "$out"
out=$(hook "gh pr edit 7 --add-label bug,infra"); assert_exit "nor in a label list" 2 $? "$out"
out=$(hook "gh api -X POST repos/o/r/issues/7/labels -f labels[]=infra"); assert_exit "nor through the API" 2 $? "$out"
out=$(hook "gh pr edit 7 --add-label bug"); assert_exit "other labels are fine" 0 $? "$out"
out=$(hook "gh api -X PATCH repos/o/r/git/refs/heads/staging -f sha=abc"); assert_exit "moving staging through the API is the qa gate" 2 $? "$out"
out=$(hook "gh api -X POST repos/o/r/git/refs -f ref=refs/tags/v1.0.0 -f sha=abc"); assert_exit "creating a tag through the API is the production gate" 2 $? "$out"
out=$(PIPELINE_BYPASS=1 hook "git push --force origin master"); assert_exit "PIPELINE_BYPASS from the human's environment lets even this through" 0 $? "$out"
assert_contains "and announces it" "$out" "bypassed"
out=$(hook "PIPELINE_BYPASS=1 git push --force origin master"); assert_exit "PIPELINE_BYPASS written into the command does not reach the hook" 2 $? "$out"

# ---- a trunk that is not master, and a narrow ticket id ----
new_repo; set_capability BASE_BRANCH '"main"'; g branch -m master main; commit_all "trunk is main"
out=$(hook "git push origin HEAD:main"); assert_exit "main trunk: push to main is the dev gate" 2 $? "$out"; assert_contains "main trunk: named" "$out" "dev gate"
out=$(hook "git push origin HEAD:master"); assert_exit "main trunk: 'master' is just a branch name" 0 $? "$out"
g checkout -qb build/macos-14
out=$(hook "git push origin HEAD:main"); assert_exit "acceptance 2: 'macos-14' on the branch is not a ticket" 2 $? "$out"; assert_contains "acceptance 2: so no ticket id is found" "$out" "no ticket id"

# ==== SHI-45: the install route (scripts/pipeline/install-merge.sh) ====
if [ "$INIT_MODE" = init ]; then
RM="bash scripts/pipeline/install-merge.sh"
rhook() { PIPELINE_PLUGIN_ROOT="$REPO_SRC" hook "$@"; }   # the reference comes from the hook's own environment only
# route_case <label> <exit> <text in the block, or ""> <change, run in $R and committed on top of the install>
route_case() {
  local at; at="$(g rev-parse HEAD)"
  (cd "$R" && eval "$4"); g add -A; g commit -qm change --allow-empty
  out=$(rhook "$RM"); assert_exit "$1" "$2" $? "$out"; [ -z "$3" ] || assert_contains "$1: says why" "$out" "$3"
  g reset -q --hard "$at"
}
origin_repo; install_branch
out=$(rhook "$RM"); assert_exit "AC-1: a fresh GitHub install on the install branch may be merged" 0 $? "$out"
out=$(rhook "bash -c \"$RM\""); assert_exit "AC-6: through bash -c" 0 $? "$out"
out=$(rhook "./scripts/pipeline/install-merge.sh"); assert_exit "AC-6: as ./scripts/pipeline/install-merge.sh" 0 $? "$out"
out=$(rhook "$RM 2>&1"); assert_exit "the route with its output redirected" 0 $? "$out"
out=$(rhook "timeout 900 $RM"); assert_exit "the route under timeout" 0 $? "$out"
# AC-8 .. AC-15 (FR-3): anything but the install is refused, and the block names the path
route_case "AC-8: an app file in the install commit is refused" 2 "src/app.js is not part of the install" "echo x > src/app.js"
for f in hooks/guard-merge.sh hooks/allow-paths.sh gate.sh check-signoff.sh; do
  route_case "AC-9: an edited $f is refused" 2 "differs from the plugin's copy" "echo '# weaker' >> scripts/pipeline/$f"
done
route_case "AC-10: settings.json without the guard hook is refused" 2 ".claude/settings.json differs from the plugin's copy" "printf '{}\n' > .claude/settings.json"
route_case "AC-11: an edited pipeline-gate.yml is refused" 2 ".github/workflows/pipeline-gate.yml differs from the plugin's copy" "echo '# x' >> .github/workflows/pipeline-gate.yml"
route_case "AC-12: host.sh that is not the GIT_HOST adapter is refused" 2 "host.sh" "cp '$REPO_SRC/scripts/pipeline/adapters/host-gitlab.sh' scripts/pipeline/host.sh"
route_case "AC-15: an extra persona is refused" 2 ".claude/agents/extra.md is not part of the install" "echo x > .claude/agents/extra.md"
route_case "AC-15: an extra template is refused" 2 "docs/pipeline/_templates/extra.md is not part of the install" "echo x > docs/pipeline/_templates/extra.md"
route_case "a .new copy that is not the plugin's is refused" 2 "differs from the plugin's copy" "echo x > scripts/pipeline/gate.sh.new"
route_case "a .new beside no install file is refused" 2 "src/App.java.new is not part of the install" "echo x > src/App.java.new"
route_case "a .gitattributes is not part of the install" 2 ".gitattributes is not part of the install" "echo '* -text' > .gitattributes"
route_case "the free project files take any content" 0 "" "echo more >> docs/pipeline/CONTEXT.md; echo '# mine' >> .gitignore; echo '# x' >> scripts/pipeline/pipeline.env"
# AC-4: CR-only and mode-only differences are the same file
route_case "AC-4: tooling committed with CRLF line endings is allowed" 0 "" "git config core.autocrlf false; sed -i 's/\$/\r/' scripts/pipeline/gate.sh docs/pipeline/TICKETS.md .claude/agents/qa-tester.md"
g config --unset core.autocrlf 2>/dev/null
route_case "AC-4: a mode-only change is allowed" 0 "" "git update-index --chmod=-x scripts/pipeline/gate.sh"
CRREF="$(mktemp -d)/ref"; mkdir -p "$CRREF"; (cd "$REPO_SRC" && cp -r .claude-plugin agents scripts template "$CRREF/")
find "$CRREF/scripts" "$CRREF/agents" "$CRREF/template" -type f \( -name '*.sh' -o -name '*.md' -o -name '*.yml' -o -name '*.json' \) -exec sed -i 's/$/\r/' {} +
out=$(PIPELINE_PLUGIN_ROOT="$CRREF" hook "$RM"); assert_exit "AC-4: a plugin copy checked out with CRLF matches an LF install" 0 $? "$out"
# AC-16, AC-17, AC-18: the install branch, on the remote trunk, with the trunk it names
tipsha="$(g rev-parse origin/master)"
g update-ref -d refs/remotes/origin/master
out=$(rhook "$RM"); assert_exit "AC-16: no origin/master is refused" 2 $? "$out"; assert_contains "AC-16: and says so" "$out" "origin/master is missing or not an ancestor of HEAD"
g update-ref refs/remotes/origin/master "$(g commit-tree -m other "$(g rev-parse 'HEAD^{tree}')")"
out=$(rhook "$RM"); assert_exit "AC-16: an origin/master that is not an ancestor is refused" 2 $? "$out"
g update-ref refs/remotes/origin/master HEAD
out=$(rhook "$RM"); assert_exit "AC-16: HEAD equal to origin/master is refused" 2 $? "$out"; assert_contains "AC-16: nothing to merge" "$out" "nothing to merge"
g update-ref refs/remotes/origin/master "$tipsha"
sed -i 's/^BASE_BRANCH=.*/BASE_BRANCH="main"/' "$R/scripts/pipeline/pipeline.env"; commit_all "main"
sed -i 's/^BASE_BRANCH=.*/BASE_BRANCH="master"/' "$R/scripts/pipeline/pipeline.env"   # the working tree says master
out=$(rhook "$RM"); assert_exit "AC-17: a committed pipeline.env naming another trunk is refused" 2 $? "$out"; assert_contains "AC-17: says so" "$out" 'BASE_BRANCH="main"'
g reset -q --hard HEAD~1
g checkout -q -b chore/install
out=$(rhook "$RM"); assert_exit "AC-18: the same install on another branch is refused" 2 $? "$out"; assert_contains "AC-18: names the branch" "$out" "the current branch is 'chore/install', not 'ship-pipeline/install'"
echo x > "$R/src/app.js"; commit_all "app change"
out=$(rhook "$RM --open-only"); assert_exit "AC-7: --open-only is allowed on any branch with any diff" 0 $? "$out"
g checkout -q ship-pipeline/install; g branch -q -D chore/install
# AC-19, AC-20: the project's own route, no arguments but --open-only
mkdir -p "$R/scripts/other" "$R/xcopy"; cp "$R/scripts/pipeline/install-merge.sh" "$R/scripts/other/"; cp "$R/scripts/pipeline/install-merge.sh" "$R/xcopy/"
echo "scripts/other/" >> "$R/.git/info/exclude"; echo "xcopy/" >> "$R/.git/info/exclude"
for c in "bash scripts/other/install-merge.sh" "bash $R/xcopy/install-merge.sh"; do
  out=$(rhook "$c"); assert_exit "AC-19: another copy of the route is refused ($c)" 2 $? "$out"
  assert_contains "AC-19: and says where the route is" "$out" "the route must be run as scripts/pipeline/install-merge.sh"
done
out=$(rhook "bash $R/scripts/pipeline/install-merge.sh"); assert_exit "the route by its absolute path is the route" 0 $? "$out"
for a in "--force" "master" "--open-only x" "--open-only --open-only"; do
  out=$(rhook "$RM $a"); assert_exit "AC-20: '$a' is refused" 2 $? "$out"; assert_contains "AC-20: '$a' names the argument" "$out" "unexpected argument"
done
# AC-21: the files the route runs must be the plugin's, in the working tree
for f in install-merge.sh lib/host-common.sh; do
  echo "# edited" >> "$R/scripts/pipeline/$f"
  out=$(rhook "$RM"); assert_exit "AC-21: an edited working-tree $f is refused (merge)" 2 $? "$out"; assert_contains "AC-21: $f named" "$out" "(used by the route) differs from the plugin's copy"
  out=$(rhook "$RM --open-only"); assert_exit "AC-21: an edited working-tree $f is refused (--open-only)" 2 $? "$out"
  g checkout -q -- "scripts/pipeline/$f"
done
# AC-22, FR-4: the reference is the hook's environment or Claude Code's record, nothing else
out=$(hook "$RM"); assert_exit "AC-22: no reference is refused" 2 $? "$out"; assert_contains "AC-22: and says so" "$out" "the plugin's installed copy could not be found"
CC="$(mktemp -d)"; mkdir -p "$CC/plugins"
$PY -c 'import json,sys; print(json.dumps({"version":2,"plugins":{"ship-pipeline@m":[{"scope":"user","installPath":sys.argv[1]}]}}))' "$REPO_SRC" > "$CC/plugins/installed_plugins.json"
out=$(CLAUDE_CONFIG_DIR="$CC" hook "$RM"); assert_exit "FR-4: Claude Code's record of the installed plugin is the reference" 0 $? "$out"
$PY -c 'import json,sys; print(json.dumps({"version":2,"plugins":{"ship-pipeline@m":[{"installPath":sys.argv[1]}],"ship-pipeline@n":[{"installPath":sys.argv[2]}]}}))' "$REPO_SRC" "$CRREF" > "$CC/plugins/installed_plugins.json"
out=$(CLAUDE_CONFIG_DIR="$CC" hook "$RM"); assert_exit "FR-4: two recorded installs that disagree fail closed" 2 $? "$out"
# AC-23: a fake plugin root named anywhere in the command or the repository is ignored
FAKE="$(mktemp -d)/fake"; mkdir -p "$FAKE"; cp -r "$CRREF/." "$FAKE/"; echo "# weaker" >> "$FAKE/scripts/pipeline/hooks/guard-merge.sh"
echo "# weaker" >> "$R/scripts/pipeline/hooks/guard-merge.sh"; commit_all "weaker guard"
echo "$FAKE" > "$R/.claude/.pipeline-init"
for c in "$RM $FAKE" "PIPELINE_PLUGIN_ROOT=$FAKE $RM" "env PIPELINE_PLUGIN_ROOT=$FAKE $RM"; do
  out=$(rhook "$c"); assert_exit "AC-23: still compared with the true reference ($c)" 2 $? "$out"
done
out=$(rhook "PIPELINE_PLUGIN_ROOT=$FAKE $RM"); assert_contains "AC-23: the edited guard is what it names" "$out" "differs from the plugin's copy"
out=$(rhook "$RM"); assert_exit "AC-23: a marker file under .claude changes nothing" 2 $? "$out"
rm -f "$R/.claude/.pipeline-init"; g reset -q --hard HEAD~1
out=$(rhook "PIPELINE_WAIT_TRIES=1 $RM"); assert_exit "a valid route with a variable assignment is refused" 2 $? "$out"; assert_contains "and says it must run on its own" "$out" "on its own"
out=$(rhook "$RM | tail -3"); assert_exit "a valid route beside another command is refused" 2 $? "$out"
out=$(rhook "git commit -qm x --allow-empty; $RM"); assert_exit "nothing may change the checked state before the route runs" 2 $? "$out"
# AC-25 .. AC-29 (FR-6): every other route is decided as before, on the install branch too
for c in "git push origin HEAD:master" "gh pr merge 5 --merge" "gh api -X PUT repos/o/r/pulls/5/merge" "glab mr merge 5" \
         "bash scripts/pipeline/host.sh merge ship-pipeline/install master x" "bash scripts/pipeline/host.sh request-merge 5 abc"; do
  out=$(rhook "$c"); assert_exit "AC-25: '$c' from the install branch needs a ticket" 2 $? "$out"; assert_contains "AC-25: '$c' names the missing ticket" "$out" "no ticket id"
done
out=$(rhook "git push"); assert_exit "AC-25/R6: a bare push of the install branch itself is decided as before (not a trunk push)" 0 $? "$out"
for c in "git push origin HEAD:staging" "git push origin v1.0.0" "git push --force origin HEAD:master" "git push --all origin" "gh pr edit 5 --add-label infra"; do
  out=$(rhook "$c"); assert_exit "AC-26: '$c' is blocked as before" 2 $? "$out"
done
set_capability GIT_HOST '"bitbucket"'
out=$(rhook "git push origin HEAD:infra/x"); assert_exit "AC-26: on Bitbucket an infra/ branch is still refused" 2 $? "$out"
g checkout -q -- scripts/pipeline/pipeline.env
out=$(rhook "$RM && git push origin HEAD:master"); assert_exit "AC-27: a push beside the route is blocked" 2 $? "$out"; assert_contains "AC-27: for the push" "$out" "no ticket id"
echo x > "$R/src/app.js"; commit_all "not the install"
out=$(PIPELINE_BYPASS=1 rhook "$RM"); assert_exit "AC-28: PIPELINE_BYPASS from the human's environment lets the route through" 0 $? "$out"; assert_contains "AC-28: announced" "$out" "bypassed"
out=$(rhook "PIPELINE_BYPASS=1 $RM"); assert_exit "AC-28: PIPELINE_BYPASS in the command does not" 2 $? "$out"
g reset -q --hard HEAD~1
new_repo   # on a master that carries the pipeline, no ticket anywhere
out=$(rhook "git push"); assert_exit "AC-29: a ticketless push on master is blocked" 2 $? "$out"
for t in "'infra' label" "own terminal" "Do not try to get around" "install-merge.sh"; do assert_contains "AC-29: the block still says: $t" "$out" "$t"; done
out=$(hook 'FOO=/x git push origin HEAD:master'); assert_exit "an assignment whose value holds a / does not hide a push" 2 $? "$out"
# AC-2, AC-3, AC-11, AC-13: every host and shape
for flags in "--git-host gitlab" "--git-host bitbucket" "--no-deploy-envs" "--deploy-mode explicit" "--git-host bitbucket --no-deploy-envs" "--tracker connector"; do
  origin_repo; install_branch $flags
  out=$(rhook "$RM"); assert_exit "AC-2: a fresh install [$flags] may be merged" 0 $? "$out"
done
origin_repo; install_branch --git-host gitlab
route_case "AC-11: an edited .gitlab/pipeline-gate.yml is refused" 2 ".gitlab/pipeline-gate.yml differs from the plugin's copy" "echo '# x' >> .gitlab/pipeline-gate.yml"
route_case "AC-13: a hand-made .gitlab-ci.yml is refused" 2 ".gitlab-ci.yml differs" "echo 'extra: 1' >> .gitlab-ci.yml"
origin_repo; install_branch --git-host bitbucket
route_case "AC-11: an edited bitbucket-pipelines.yml is refused" 2 "bitbucket-pipelines.yml differs from the plugin's copy" "echo '# x' >> bitbucket-pipelines.yml"
origin_repo; printf 'stages: [test]\nunit:\n  script: [make test]\n' > "$R/.gitlab-ci.yml"; commit_all "ci"; g push -q origin master; g fetch -q origin
install_branch --git-host gitlab
out=$(rhook "$RM"); assert_exit "AC-3: .gitlab-ci.yml with init's include block appended is allowed" 0 $? "$out"
origin_repo; printf 'include:\n  - template: Security/SAST.gitlab-ci.yml\n' > "$R/.gitlab-ci.yml"; commit_all "ci"; g push -q origin master; g fetch -q origin
install_branch --git-host gitlab
out=$(rhook "$RM"); assert_exit "the ACTION case: init leaves the include: list alone, so the install still passes" 0 $? "$out"
route_case "AC-13: an install commit that edits the trunk's own include: list is refused" 2 ".gitlab-ci.yml differs from what the install writes" \
  "printf '  - local: /.gitlab/pipeline-gate.yml\n' >> .gitlab-ci.yml"
# AC-5, AC-14: an upgrade over an older install
origin_repo
bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name demo --team-key REP --base-branch master --staging-branch staging >/dev/null
echo "# old" > "$R/scripts/pipeline/gate.sh"; echo "# old persona" > "$R/.claude/agents/old-persona.md"; echo "# my edit" >> "$R/scripts/pipeline/status.sh"
(cd "$R" && grep -v ' scripts/pipeline/gate.sh$' scripts/pipeline/.install-manifest > m; cksum scripts/pipeline/gate.sh .claude/agents/old-persona.md >> m; sort -k3 m > scripts/pipeline/.install-manifest; rm m)
commit_all "an older install"; g push -q origin master; g fetch -q origin
install_branch
assert_eq "AC-5: the fixture updates gate.sh, retires a persona and writes status.sh.new" "M|D|A" \
  "$(g diff --no-renames --name-status origin/master HEAD -- scripts/pipeline/gate.sh | cut -c1)|$(g diff --no-renames --name-status origin/master HEAD -- .claude/agents/old-persona.md | cut -c1)|$(g diff --no-renames --name-status origin/master HEAD -- scripts/pipeline/status.sh.new | cut -c1)"
out=$(rhook "$RM"); assert_exit "AC-5: the upgrade may be merged" 0 $? "$out"
route_case "AC-14: deleting gate.sh is refused" 2 "scripts/pipeline/gate.sh is deleted but is not retired tooling" "git rm -q scripts/pipeline/gate.sh"
route_case "AC-14: deleting settings.json is refused" 2 ".claude/settings.json is deleted but is not retired tooling" "git rm -q .claude/settings.json"
route_case "deleting an app file is refused" 2 "src/App.java is deleted but is not retired tooling" "git rm -q src/App.java"
# AC-24: the existing guard tests are only added to
bref="$(cd "$REPO_SRC" && git rev-parse -q --verify origin/master 2>/dev/null || true)"
if [ -n "$bref" ]; then
  removed="$(cd "$REPO_SRC" && git diff "$bref" -- tests/pipeline/test_guard_merge.sh tests/pipeline/test_adapters.sh | grep -E '^-[^-]|^-$' || true)"
  assert_eq "AC-24: test_guard_merge.sh and test_adapters.sh only gain lines" "" "$removed"
fi
# AC-30 (FR-15): /ship and the personas never use the route
leak="$(cd "$REPO_SRC" && grep -l 'install-merge' commands/ship.md agents/*.md .claude/agents/*.md 2>/dev/null || true)"
assert_eq "AC-30: /ship and the personas do not name install-merge" "" "$leak"
fi
summary
