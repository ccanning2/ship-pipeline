#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "host.sh: GitHub, GitLab and Bitbucket adapters through fake CLIs"
# Each fake logs what it was asked and answers with canned API JSON. The fake gh applies -q with jq, as gh does, so
# the adapters' own filters run too. The install route's use of these verbs is in test_install_merge.sh.
command -v jq >/dev/null 2>&1 || { echo "  (skipped: needs jq)"; summary; exit 0; }
new_repo
ST="$(mktemp -d)"; export ST TMPDIR="$ST" PIPELINE_WAIT_TRIES=1
hst() { (cd "$R" && bash scripts/pipeline/host.sh "$@" 2>&1); }
fake() { cat > "$ST/$1"; chmod +x "$ST/$1"; }
head_sha="$(g rev-parse HEAD)"
# canned <key> <json>: the answer the fakes give for "<METHOD> <path>"
canned() { printf '%s' "$2" > "$ST/r.$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; }
reset() { rm -f "$ST"/r.* "$ST"/*.log "$ST"/fail.*; }
FAKE_COMMON='
key() { printf "%s" "$1" | tr -c "A-Za-z0-9._-" "_"; }
answer() { local k; k="$(key "$1")"; [ -f "$ST/fail.$k" ] && { cat "$ST/fail.$k" >&2; exit 1; }; cat "$ST/r.$k" 2>/dev/null; }'

# ================================================================ GitHub ====
use_host github; g remote add origin https://github.com/acme/app.git
{ echo '#!/usr/bin/env bash'; echo "$FAKE_COMMON"; cat <<'FAKE'
printf '%s\n' "$*" >> "$ST/gh.log"
case "$1 $2" in
  "auth status") exit 0;;
  "repo view") echo acme/app; exit 0;;
  "variable get") answer "VAR $3"; exit;;
  "variable set"|"workflow run") exit 0;;
  "run list") out="$(answer "RUNS")"; q=""; while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done; printf '%s' "$out" | jq -r "$q"; exit;;
  "run watch") [ -f "$ST/fail.watch" ] && exit 1; exit 0;;
esac
shift; m=GET q=""; path=""
while [ $# -gt 0 ]; do case "$1" in -X) m="$2"; shift 2;; -q) q="$2"; shift 2;; -f|-F) shift 2;; --input) cat > "$ST/gh.input"; shift 2;; *) path="$1"; shift;; esac; done
out="$(answer "$m $path")" || exit 1
if [ -n "$q" ]; then printf '%s' "$out" | jq -r "$q"; else printf '%s' "$out"; fi
FAKE
} | fake gh
export PIPELINE_GH_CMD="$ST/gh"
out=$(hst slug); assert_eq "github: slug" "acme/app" "$out"
out=$(hst web-url); assert_eq "github: web-url" "https://github.com/acme/app" "$out"

reset; canned "GET repos/acme/app/pulls?head=acme:feature/REP-1-x&state=open" '[]'
canned "POST repos/acme/app/pulls" '{"number":12,"html_url":"https://github.com/acme/app/pull/12"}'
canned "PUT repos/acme/app/pulls/12/merge" '{"merged":true}'
out=$(hst merge feature/REP-1-x master 'REP-1: health'); assert_exit "github: merge opens a PR and merges it" 0 $? "$out"
assert_contains "github: the PR is opened from the branch into the base" "$(cat "$ST/gh.log")" "api -X POST repos/acme/app/pulls -f title=REP-1: health -f head=feature/REP-1-x -f base=master"
assert_contains "github: and merged pinned to HEAD" "$(cat "$ST/gh.log")" "api -X PUT repos/acme/app/pulls/12/merge -f merge_method=merge -f sha=$head_sha"
reset; canned "GET repos/acme/app/pulls?head=acme:feature/REP-1-x&state=open" '[{"number":9}]'
printf 'gh: Pull Request is not mergeable (HTTP 405)' > "$ST/fail.PUT_repos_acme_app_pulls_9_merge"
out=$(hst merge feature/REP-1-x master 'x'); assert_exit "github: a refused merge is an error" 1 $? "$out"
assert_contains "github: naming the reused PR" "$out" "GitHub refused to merge PR #9"
case "$(cat "$ST/gh.log")" in *"-X POST"*) bad "github: an open PR is reused, not opened again";; *) ok "github: an open PR is reused, not opened again";; esac

reset; canned "GET repos/acme/app/pulls?head=acme:ship-pipeline/install&base=master&state=open" '[]'
canned "POST repos/acme/app/pulls" '{"number":13,"html_url":"https://github.com/acme/app/pull/13"}'
out=$(hst request-open ship-pipeline/install master 'Install' 'Body'); assert_eq "github: request-open prints id and url" "13 https://github.com/acme/app/pull/13" "$out"
case "$(cat "$ST/gh.log")" in *label*|*reviewer*) bad "github: request-open adds no label or reviewer";; *) ok "github: request-open adds no label or reviewer";; esac
for c in 'null:checking' 'true:ready' 'false:blocked'; do
  canned "GET repos/acme/app/pulls/13" "{\"head\":{\"sha\":\"abc123\"},\"mergeable\":${c%%:*},\"base\":{\"ref\":\"master\"}}"
  out=$(hst request-info 13); assert_eq "github: request-info, mergeable ${c%%:*}" "abc123 ${c#*:} master" "$out"
done
canned "GET repos/acme/app/branches/release%2F1" '{"commit":{"sha":"def456"}}'
out=$(hst branch-head release/1); assert_eq "github: branch-head url-encodes the branch" "def456" "$out"
printf 'gh: Head branch was modified. Review and try the merge again. (HTTP 409)\n{"message":"payload"}' > "$ST/fail.PUT_repos_acme_app_pulls_13_merge"
out=$(hst request-merge 13 abc123); assert_exit "github: a refused request-merge exits 3" 3 $? "$out"
assert_eq "github: with one line, the host's reason and no payload" "GitHub refused to merge PR #13: Head branch was modified. Review and try the merge again. (HTTP 409)" "$out"

reset; printf 'gh: Reference does not exist (HTTP 422)' > "$ST/fail.PATCH_repos_acme_app_git_refs_tags_v1.0.0"; canned "POST repos/acme/app/git/refs" '{}'
out=$(hst set-ref refs/tags/v1.0.0 "$head_sha"); assert_exit "github: set-ref creates a ref that does not exist" 0 $? "$out"
assert_contains "github: never forced" "$(cat "$ST/gh.log")" "api -X PATCH repos/acme/app/git/refs/tags/v1.0.0 -f sha=$head_sha -F force=false"
assert_contains "github: then created" "$(cat "$ST/gh.log")" "api -X POST repos/acme/app/git/refs -f ref=refs/tags/v1.0.0 -f sha=$head_sha"
out=$(hst dispatch staging "$head_sha" REP-1 staging); assert_exit "github: dispatch" 0 $? "$out"
assert_contains "github: dispatch runs the deploy workflow with env, sha and ticket" "$(tail -1 "$ST/gh.log")" "workflow run deploy.yml --ref staging -f env=staging -f sha=$head_sha -f ticket=REP-1"
canned RUNS '[{"databaseId":3,"displayTitle":"resolve dev"},{"databaseId":5,"displayTitle":"resolve staging"}]'
out=$(hst wait staging "$head_sha"); assert_exit "github: wait" 0 $? "$out"
assert_contains "github: wait watches the run for that environment" "$out" "watching run 5"
touch "$ST/fail.watch"; out=$(hst wait staging "$head_sha"); assert_exit "github: a failed run fails the wait" 1 $? "$out"; rm -f "$ST/fail.watch"
canned RUNS '[]'; out=$(hst wait qa "$head_sha"); assert_exit "github: no run is an error" 1 $? "$out"
assert_contains "github: naming the environment" "$out" "no 'qa' deploy run found"
canned "PUT repos/acme/app/branches/staging/protection" '{}'
out=$(hst protect staging); assert_exit "github: protect" 0 $? "$out"
assert_eq "github: protect requires the gate check and forbids force pushes" '["gate"]|false' "$(jq -r '"\(.required_status_checks.contexts|tostring)|\(.allow_force_pushes)"' "$ST/gh.input")"
canned "VAR PIPELINE_DEPLOY_ENABLED" 'true'; out=$(hst var-get PIPELINE_DEPLOY_ENABLED); assert_eq "github: var-get" "true" "$out"

reset
for b in master staging; do canned "GET repos/acme/app/branches/$b/protection" '{"required_status_checks":{"contexts":["gate"]}}'; canned "GET repos/acme/app/rules/branches/$b" '[]'; done
out=$(hst enforcement); assert_contains "github: enforcement host when both branches require the gate" "$out" "ENFORCEMENT=host"
canned "GET repos/acme/app/branches/staging/protection" '{"required_status_checks":{"contexts":[]}}'
canned "GET repos/acme/app/rules/branches/staging" '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"gate"}]}}]'
out=$(hst enforcement); assert_contains "github: a ruleset counts as well as branch protection" "$out" "ENFORCEMENT=host"
for b in master staging; do printf 'gh: Upgrade to GitHub Pro or make this repository public (HTTP 403)' > "$ST/fail.GET_repos_acme_app_branches_${b}_protection"
  printf 'gh: (HTTP 403)' > "$ST/fail.GET_repos_acme_app_rules_branches_$b"; done
out=$(hst enforcement); assert_contains "github: a plan that cannot protect is local only" "$out" "ENFORCEMENT=local"
assert_contains "github: and says why" "$out" "need a paid plan or a public repository"
unset PIPELINE_GH_CMD

# ================================================================ GitLab ====
use_host gitlab; g remote set-url origin https://gitlab.invalid/grp/sub/app.git
{ echo '#!/usr/bin/env bash'; echo "$FAKE_COMMON"; cat <<'FAKE'
printf '%s\n' "$*" >> "$ST/glab.log"
[ "$1" = auth ] && exit 0
shift; m=GET path=""
while [ $# -gt 0 ]; do case "$1" in -X) m="$2"; shift 2;; -f|-F) shift 2;; *) path="$1"; shift;; esac; done
answer "$m $path"
FAKE
} | fake glab
export PIPELINE_GLAB_CMD="$ST/glab"
P="projects/grp%2Fsub%2Fapp"
out=$(hst web-url); assert_eq "gitlab: web-url keeps subgroups" "https://gitlab.com/grp/sub/app" "$out"
reset; canned "GET $P/merge_requests?state=opened&source_branch=feature%2FREP-1-x&target_branch=master" '[]'
canned "POST $P/merge_requests" '{"iid":5}'; canned "PUT $P/merge_requests/5/merge" '{}'
out=$(hst merge feature/REP-1-x master 'REP-1: health'); assert_exit "gitlab: merge opens an MR and merges it" 0 $? "$out"
assert_contains "gitlab: the MR is opened from the branch into the base" "$(cat "$ST/glab.log")" "api -X POST $P/merge_requests -f source_branch=feature/REP-1-x -f target_branch=master -f title=REP-1: health"
assert_contains "gitlab: and merged pinned to HEAD" "$(cat "$ST/glab.log")" "api -X PUT $P/merge_requests/5/merge -f sha=$head_sha"
reset; canned "GET $P/merge_requests?state=opened&source_branch=ship-pipeline%2Finstall&target_branch=master" '[{"iid":6,"web_url":"https://gitlab.com/grp/sub/app/-/merge_requests/6"}]'
out=$(hst request-open ship-pipeline/install master 'Install' 'Body'); assert_eq "gitlab: request-open reuses the open MR" "6 https://gitlab.com/grp/sub/app/-/merge_requests/6" "$out"
for c in 'mergeable:ready' 'checking:checking' 'not_approved:blocked' 'ci_still_running:blocked'; do
  canned "GET $P/merge_requests/6" "{\"sha\":\"abc123\",\"detailed_merge_status\":\"${c%%:*}\",\"target_branch\":\"master\"}"
  out=$(hst request-info 6); assert_eq "gitlab: request-info, ${c%%:*}" "abc123 ${c#*:} master" "$out"
done
canned "GET $P/merge_requests/6" '{"sha":"abc123","merge_status":"can_be_merged","target_branch":"master"}'
out=$(hst request-info 6); assert_eq "gitlab: request-info reads merge_status on older GitLab" "abc123 ready master" "$out"
printf 'glab: 406 Branch cannot be merged' > "$ST/fail.PUT_projects_grp_2Fsub_2Fapp_merge_requests_6_merge"
out=$(hst request-merge 6 abc123); assert_exit "gitlab: a refused request-merge exits 3" 3 $? "$out"
assert_eq "gitlab: with the host's reason" "GitLab refused to merge !6: 406 Branch cannot be merged" "$out"
reset; canned "POST $P/repository/tags" '{}'
out=$(hst set-ref refs/tags/v1.2.0 "$head_sha"); assert_exit "gitlab: set-ref of a tag" 0 $? "$out"
assert_contains "gitlab: creates the tag on the sha" "$(cat "$ST/glab.log")" "api -X POST $P/repository/tags -f tag_name=v1.2.0 -f ref=$head_sha -f message=v1.2.0"
canned "POST $P/repository/branches" '{}'
out=$(hst set-ref refs/heads/staging "$head_sha"); assert_exit "gitlab: set-ref of a branch the remote lacks" 0 $? "$out"
assert_contains "gitlab: creates the branch on the sha" "$(cat "$ST/glab.log")" "api -X POST $P/repository/branches -f branch=staging -f ref=$head_sha"
canned "POST $P/pipeline" '{"id":77}'; canned "GET $P/pipelines/77" '{"status":"success"}'
out=$(hst dispatch qa "$head_sha" REP-1 staging); assert_exit "gitlab: dispatch" 0 $? "$out"
assert_contains "gitlab: dispatch passes env, sha and ticket as pipeline variables" "$(tail -1 "$ST/glab.log")" "variables[][value]=qa -f variables[][key]=PIPELINE_SHA -f variables[][value]=$head_sha -f variables[][key]=PIPELINE_TICKET -f variables[][value]=REP-1"
out=$(hst wait qa "$head_sha" staging); assert_exit "gitlab: wait on the dispatched pipeline" 0 $? "$out"
assert_contains "gitlab: wait follows the pipeline dispatch started" "$out" "pipeline 77 passed"
canned "GET $P/pipelines?sha=$head_sha&ref=v1.2.0&order_by=id&sort=desc" '[{"id":80}]'; canned "GET $P/pipelines/80" '{"status":"failed"}'
out=$(hst wait production "$head_sha" v1.2.0); assert_exit "gitlab: a failed pipeline fails the wait" 1 $? "$out"
assert_contains "gitlab: naming it" "$out" "pipeline 80 for production ended failed"
printf 'glab: 404 Variable Not Found' > "$ST/fail.PUT_projects_grp_2Fsub_2Fapp_variables_PIPELINE_DEPLOY_ENABLED"; canned "POST $P/variables" '{}'
out=$(hst var-set PIPELINE_DEPLOY_ENABLED true); assert_exit "gitlab: var-set creates a missing variable" 0 $? "$out"
assert_contains "gitlab: with its key and value" "$(tail -1 "$ST/glab.log")" "api -X POST $P/variables -f key=PIPELINE_DEPLOY_ENABLED -f value=true"
reset
for b in master staging; do canned "GET $P/protected_branches/$b" "{\"name\":\"$b\"}"; done
canned "GET $P" '{"only_allow_merge_if_pipeline_succeeds":true}'
out=$(hst enforcement); assert_contains "gitlab: enforcement host when both are protected and pipelines must pass" "$out" "ENFORCEMENT=host"
canned "GET $P" '{"only_allow_merge_if_pipeline_succeeds":false}'
out=$(hst enforcement); assert_contains "gitlab: local when merges do not need a passing pipeline" "$out" "ENFORCEMENT=local"
unset PIPELINE_GLAB_CMD

# ================================================================ Bitbucket ====
use_host bitbucket; g remote set-url origin https://bitbucket.invalid/acme/app.git
export BITBUCKET_EMAIL=me@example.com BITBUCKET_API_TOKEN=bb-token
{ echo '#!/usr/bin/env bash'; echo "$FAKE_COMMON"; cat <<'FAKE'
m=GET u="" d=""; while [ $# -gt 0 ]; do case "$1" in -X) m="$2"; shift 2;; --data) d="$2"; shift 2;; -u|-H) shift 2;; http*) u="$1"; shift;; *) shift;; esac; done
p="${u#https://api.bitbucket.org/2.0/}"; printf '%s\t%s\t%s\n' "$m" "$p" "$d" >> "$ST/bb.log"
[ -z "$d" ] || printf '%s' "$d" | jq -e . >/dev/null 2>&1 || { echo "curl: (22) The requested URL returned error: 400 (invalid JSON)" >&2; exit 22; }
answer "$m $p"
FAKE
} | fake curl-bb
export PIPELINE_CURL_CMD="$ST/curl-bb"
R2="repositories/acme/app"
data_of() { awk -F'\t' -v m="$1" -v p="$2" '$1==m && $2==p {d=$3} END {print d}' "$ST/bb.log"; }
reset; canned "GET $R2" '{}'; out=$(hst check); assert_exit "bitbucket: check" 0 $? "$out"
out=$(cd "$R" && env -u BITBUCKET_API_TOKEN XDG_CONFIG_HOME="$ST/none" bash scripts/pipeline/host.sh check 2>&1); assert_exit "bitbucket: no token fails the check" 1 $? "$out"
assert_contains "bitbucket: and says which variables" "$out" "no Bitbucket API token"
mkdir -p "$ST/cfg/ship-pipeline"; printf 'BITBUCKET_EMAIL=me@example.com\nBITBUCKET_API_TOKEN=saved\n' > "$ST/cfg/ship-pipeline/bitbucket.env"
out=$(cd "$R" && env -u BITBUCKET_API_TOKEN XDG_CONFIG_HOME="$ST/cfg" bash scripts/pipeline/host.sh check 2>&1); assert_exit "bitbucket: a saved token counts" 0 $? "$out"
set_capability GIT_HOST_URL '"https://bitbucket.example.com"'
out=$(hst check); assert_exit "bitbucket: Data Center is refused for API promotion" 1 $? "$out"
assert_contains "bitbucket: and says so" "$out" "supported for git and CI only"
set_capability GIT_HOST_URL '""'

reset; canned "POST $R2/pullrequests" '{"id":21}'; canned "POST $R2/pullrequests/21/merge" '{}'
out=$(hst merge feature/REP-1-x master 'REP-1: the "health" endpoint'); assert_exit "bitbucket: merge with a quote in the title" 0 $? "$out"
assert_eq "bitbucket: the PR's JSON keeps the title intact" 'REP-1: the "health" endpoint|feature/REP-1-x|master' \
  "$(data_of POST "$R2/pullrequests" | jq -r '"\(.title)|\(.source.branch.name)|\(.destination.branch.name)"')"
assert_eq "bitbucket: merged as a merge commit" "merge_commit" "$(data_of POST "$R2/pullrequests/21/merge" | jq -r .merge_strategy)"
canned "POST $R2/pullrequests" '{"id":22,"links":{"html":{"href":"https://bitbucket.org/acme/app/pull-requests/22"}}}'
out=$(hst request-open ship-pipeline/install master 'Install' 'Line "one"'); assert_eq "bitbucket: request-open prints id and url" "22 https://bitbucket.org/acme/app/pull-requests/22" "$out"
canned "GET $R2/pullrequests/22" '{"source":{"commit":{"hash":"abc123"}},"destination":{"branch":{"name":"master"}}}'
out=$(hst request-info 22); assert_eq "bitbucket: request-info" "abc123 ready master" "$out"
canned "GET $R2/refs/branches/release%2F1" '{"target":{"hash":"def456"}}'
out=$(hst branch-head release/1); assert_eq "bitbucket: branch-head" "def456" "$out"
printf 'curl: (22) The requested URL returned error: 409' > "$ST/fail.POST_repositories_acme_app_pullrequests_22_merge"
out=$(hst request-merge 22 abc123); assert_exit "bitbucket: a refused request-merge exits 3" 3 $? "$out"
assert_eq "bitbucket: with the host's reason" "Bitbucket refused to merge PR #22: (22) The requested URL returned error: 409" "$out"
reset; canned "POST $R2/refs/tags" '{}'
out=$(hst set-ref refs/tags/v1.2.0 "$head_sha"); assert_exit "bitbucket: set-ref of a tag" 0 $? "$out"
assert_eq "bitbucket: the tag points at the sha" "v1.2.0|$head_sha" "$(data_of POST "$R2/refs/tags" | jq -r '"\(.name)|\(.target.hash)"')"
canned "POST $R2/pipelines/" '{"uuid":"{p-1}"}'; canned "GET $R2/pipelines/%7Bp-1%7D" '{"state":{"name":"COMPLETED","result":{"name":"SUCCESSFUL"}}}'
out=$(hst dispatch staging "$head_sha" REP-1 staging); assert_exit "bitbucket: dispatch" 0 $? "$out"
assert_eq "bitbucket: dispatch runs the custom deploy pipeline with env, sha and ticket" "custom/deploy|staging|staging,$head_sha,REP-1" \
  "$(data_of POST "$R2/pipelines/" | jq -r '"\(.target.selector.type)/\(.target.selector.pattern)|\(.target.ref_name)|\([.variables[].value]|join(","))"')"
out=$(hst wait staging "$head_sha" staging); assert_exit "bitbucket: wait" 0 $? "$out"
assert_contains "bitbucket: wait follows the dispatched pipeline" "$out" "pipeline {p-1} passed"
canned "GET $R2/pipelines/?sort=-created_on&pagelen=20" '{"values":[{"uuid":"{other}","target":{"commit":{"hash":"0000"},"ref_name":"master"}},{"uuid":"{p-2}","target":{"commit":{"hash":"'"$head_sha"'"},"ref_name":"v1.2.0"}}]}'
canned "GET $R2/pipelines/%7Bp-2%7D" '{"state":{"name":"COMPLETED","result":{"name":"FAILED"}}}'
out=$(hst wait production "$head_sha" v1.2.0); assert_exit "bitbucket: a failed pipeline fails the wait" 1 $? "$out"
assert_contains "bitbucket: picking the pipeline for that sha and ref" "$out" "pipeline {p-2} for production ended COMPLETED/FAILED"
canned "GET $R2/pipelines_config/variables/?pagelen=100" '{"values":[{"key":"PIPELINE_DEPLOY_ENABLED","uuid":"{v-1}","value":"false"}]}'
canned "PUT $R2/pipelines_config/variables/%7Bv-1%7D" '{}'
out=$(hst var-get PIPELINE_DEPLOY_ENABLED); assert_eq "bitbucket: var-get" "false" "$out"
out=$(hst var-set PIPELINE_DEPLOY_ENABLED true); assert_exit "bitbucket: var-set updates an existing variable" 0 $? "$out"
assert_eq "bitbucket: as a plain (not secured) variable" "true|false" "$(data_of PUT "$R2/pipelines_config/variables/%7Bv-1%7D" | jq -r '"\(.value)|\(.secured)"')"
reset; canned "GET $R2" '{}'
canned "GET $R2/branch-restrictions?pagelen=100" '{"values":[{"pattern":"master","kind":"require_passing_builds_to_merge"},{"pattern":"staging","kind":"require_passing_builds_to_merge"}]}'
out=$(hst enforcement); assert_contains "bitbucket: enforcement host when both need passing builds" "$out" "ENFORCEMENT=host"
canned "GET $R2/branch-restrictions?pagelen=100" '{"values":[{"pattern":"master","kind":"require_passing_builds_to_merge"},{"pattern":"staging","kind":"force"}]}'
out=$(hst enforcement); assert_contains "bitbucket: local when one branch does not" "$out" "ENFORCEMENT=local"
unset PIPELINE_CURL_CMD BITBUCKET_EMAIL BITBUCKET_API_TOKEN

summary
