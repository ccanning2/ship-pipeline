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
marketing REP-90 ready; add_ticket REP-90 REP-9090 marketing - - done; commit_all mk; golive REP-90
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
summary
