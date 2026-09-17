#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "guard-merge.sh (branch/tag gates)"
hook() {
  local cmd="$1" json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
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
summary
