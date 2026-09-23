#!/usr/bin/env bash
# The code host, behind one interface: GitHub (gh), GitLab (glab) or Bitbucket Cloud (REST through curl).
# GIT_HOST / GIT_HOST_URL in scripts/pipeline/pipeline.env pick the host; an empty GIT_HOST_URL means the public
# service (github.com, gitlab.com, bitbucket.org), anything else a self-hosted one (GitHub Enterprise, GitLab
# self-managed). Every caller (promote.sh, enforcement.sh, doctor.sh, init.sh) goes through here, so nothing
# else knows which host it is talking to.
# Usage: host.sh <verb> [args]
#   name                               github | gitlab | bitbucket
#   check                              exit 0 when the host CLI/API is installed and signed in (prints why not)
#   slug                               owner/repo, group/project or workspace/repo
#   merge <branch> <base> <title>      open (or reuse) a PR/MR from <branch> into <base> and merge it at HEAD
#   set-ref <refs/heads/x|refs/tags/x> <sha>   create or move a branch or tag through the API (never forced)
#   dispatch <env> <sha> <ticket> <ref>        start the deploy pipeline for <env> on <ref>
#   wait <env> <sha> [ref]             wait for the deploy run for <env> on <sha> (on <ref>: the branch or tag that
#                                      carried it); exit 1 if it fails
#   var-get <NAME> | var-set <NAME> <VALUE>    repository CI/CD variable (never a secret)
#   protect <branch>                   require the Pipeline Gate check before anything merges into <branch>
#   enforcement                        prints "ENFORCEMENT=<host|local|unknown>" then one line explaining it
#   web-url                            the repository's web address
# Test doubles: PIPELINE_GH_CMD (gh), PIPELINE_GLAB_CMD (glab), PIPELINE_CURL_CMD (curl), PIPELINE_WAIT_TRIES.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
host="$(printf '%s' "${GIT_HOST:-github}" | tr '[:upper:]' '[:lower:]')"
host_url="${GIT_HOST_URL:-}"; host_url="${host_url%/}"
remote="$(bash "$here/base-ref.sh" --remote)"
wf="${DEPLOY_WORKFLOW:-deploy.yml}"
tries="${PIPELINE_WAIT_TRIES:-45}"
gh_cmd="${PIPELINE_GH_CMD:-gh}"; glab_cmd="${PIPELINE_GLAB_CMD:-glab}"; curl_cmd="${PIPELINE_CURL_CMD:-curl}"
hostname_of() { printf '%s' "$1" | sed -E 's#^[a-z]+://##; s#/.*$##'; }
# a self-hosted GitHub or GitLab: the CLIs read the host name from the environment
if [ -n "$host_url" ]; then
  case "$host" in github) export GH_HOST; GH_HOST="$(hostname_of "$host_url")";; gitlab) export GITLAB_HOST; GITLAB_HOST="$host_url";; esac
fi
die() { echo "host.sh: $*" >&2; exit 1; }
have() { command -v "${1%% *}" >/dev/null 2>&1; }
remote_path() { # the path part of the remote URL: owner/repo
  git remote get-url "$remote" 2>/dev/null | sed -E 's#^(git@|ssh://git@|https?://)([^@/]+@)?[^/:]+(:[0-9]+)?[/:]##; s#\.git$##'
}
urlenc() { printf '%s' "$1" | sed -e 's/%/%25/g' -e 's#/#%2F#g' -e 's/ /%20/g' -e 's/:/%3A/g'; }
json() { have jq || die "needs jq to read the $host API (/pipeline-init installs it)"; jq -r "$1"; }

# ---------------------------------------------------------------- GitHub (gh) ----
gh_slug() { $gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || remote_path; }
gh_check() {
  have "$gh_cmd" || { echo "gh is not installed"; return 1; }
  $gh_cmd auth status >/dev/null 2>&1 || { echo "gh is not signed in${GH_HOST:+ to $GH_HOST}"; return 1; }
}
gh_merge() { # branch base title
  local or pr; or="$(gh_slug)"
  pr="$($gh_cmd api "repos/$or/pulls?head=${or%%/*}:$1&state=open" -q '.[0].number' 2>/dev/null || true)"
  if [ -z "$pr" ] || [ "$pr" = null ]; then
    pr="$($gh_cmd api -X POST "repos/$or/pulls" -f title="$3" -f head="$1" -f base="$2" -f body="Pipeline ticket. See docs/pipeline/." -q .number)" || die "could not create a pull request"
  fi
  $gh_cmd api -X PUT "repos/$or/pulls/$pr/merge" -f merge_method=merge -f sha="$(git rev-parse HEAD)" >/dev/null || die "GitHub refused to merge PR #$pr"
}
gh_set_ref() {
  local or; or="$(gh_slug)"
  $gh_cmd api -X PATCH "repos/$or/git/$1" -f sha="$2" -F force=false >/dev/null 2>&1 \
    || $gh_cmd api -X POST "repos/$or/git/refs" -f ref="$1" -f sha="$2" >/dev/null || die "could not update $1"
}
gh_dispatch() { $gh_cmd workflow run "$wf" --ref "$4" -f env="$1" -f sha="$2" -f ticket="$3"; }
gh_wait() { # env sha
  local id=""
  for _ in $(seq 1 "$tries"); do
    id="$($gh_cmd run list --workflow "$wf" --commit "$2" --limit 5 --json databaseId,displayTitle \
          -q "[.[] | select(.displayTitle | test(\"$1\"))][0].databaseId" 2>/dev/null || true)"
    [ -n "$id" ] && [ "$id" != null ] && break; sleep 4
  done
  [ -n "$id" ] && [ "$id" != null ] || die "no '$1' deploy run found for $2"
  echo "host.sh: watching run $id"; $gh_cmd run watch "$id" --exit-status
}
gh_var_get() { $gh_cmd variable get "$1" 2>/dev/null; }
gh_var_set() { $gh_cmd variable set "$1" --body "$2"; }
gh_protect() {
  local or; or="$(gh_slug)"
  printf '{"required_status_checks":{"strict":true,"contexts":["gate"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}' \
    | $gh_cmd api -X PUT "repos/$or/branches/$1/protection" --input - >/dev/null
}
gh_enforcement() {
  local slug forbidden=0 missing="" b checks out
  have "$gh_cmd" || say unknown "Enforcement: unknown (gh is not installed, so branch protection could not be checked)."
  $gh_cmd auth status >/dev/null 2>&1 || say unknown "Enforcement: unknown (gh is not signed in; run /pipeline-init to sign in)."
  slug="$($gh_cmd repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$slug" ] || say unknown "Enforcement: unknown (gh cannot see this repository on the code host)."
  for b in "$base" "$stg"; do
    checks=""
    if out="$($gh_cmd api "repos/$slug/branches/$b/protection" \
          -q '[.required_status_checks.contexts[]?, .required_status_checks.checks[]?.context] | join(",")' 2>&1)"; then
      checks="$out"
    else case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac; fi
    if out="$($gh_cmd api "repos/$slug/rules/branches/$b" \
          -q '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | join(",")' 2>&1)"; then
      checks="$checks,$out"
    else case "$out" in *403*|*"Upgrade to GitHub Pro"*) forbidden=1;; esac; fi
    case ",$(printf '%s' "$checks" | tr '[:upper:]' '[:lower:]')," in *gate*) ;; *) missing="$missing $b";; esac
  done
  [ -z "$missing" ] && say host "Enforcement: host. The Pipeline Gate check is required on $base and $stg."
  [ "$forbidden" = 1 ] && say local "Enforcement: local hook only. The host refused branch protection and rulesets for $slug (HTTP 403: they need a paid plan or a public repository), so nothing on the host requires the Pipeline Gate check. The hook gates agent sessions only; a human or another tool can push past it."
  say local "Enforcement: local hook only. No required Pipeline Gate check on:$missing. /pipeline-init can add it (docs/pipeline/BRANCHING.md). Until then the hook gates agent sessions only; a human or another tool can push past it."
}
gh_web() { echo "https://${GH_HOST:-github.com}/$(gh_slug)"; }

# ---------------------------------------------------------------- GitLab (glab) ----
gl_pid() { urlenc "$(remote_path)"; }
gl_check() {
  have "$glab_cmd" || { echo "glab is not installed"; return 1; }
  $glab_cmd auth status ${GITLAB_HOST:+--hostname "$(hostname_of "$GITLAB_HOST")"} >/dev/null 2>&1 || { echo "glab is not signed in${GITLAB_HOST:+ to $GITLAB_HOST}"; return 1; }
}
gl_merge() { # branch base title
  local p iid; p="$(gl_pid)"
  iid="$($glab_cmd api "projects/$p/merge_requests?state=opened&source_branch=$(urlenc "$1")&target_branch=$(urlenc "$2")" 2>/dev/null | json '.[0].iid // empty')"
  if [ -z "$iid" ]; then
    iid="$($glab_cmd api -X POST "projects/$p/merge_requests" -f source_branch="$1" -f target_branch="$2" -f title="$3" \
          -f description="Pipeline ticket. See docs/pipeline/." | json '.iid')" || die "could not create a merge request"
  fi
  $glab_cmd api -X PUT "projects/$p/merge_requests/$iid/merge" -f sha="$(git rev-parse HEAD)" >/dev/null || die "GitLab refused to merge !$iid"
}
gl_set_ref() { # ref sha
  local p name; p="$(gl_pid)"
  case "$1" in
    refs/tags/*) name="${1#refs/tags/}"
      $glab_cmd api -X POST "projects/$p/repository/tags" -f tag_name="$name" -f ref="$2" -f message="$name" >/dev/null || die "could not create tag $name";;
    refs/heads/*) name="${1#refs/heads/}"
      # branches have no "move" call: push the sha (a fast-forward), or create the branch when it is new
      if git ls-remote --exit-code --heads "$remote" "$name" >/dev/null 2>&1; then git push -q "$remote" "$2:$1" || die "push to $1 rejected"
      else $glab_cmd api -X POST "projects/$p/repository/branches" -f branch="$name" -f ref="$2" >/dev/null || die "could not create branch $name"; fi;;
  esac
}
gl_dispatch() { # env sha ticket ref
  $glab_cmd api -X POST "projects/$(gl_pid)/pipeline" -f ref="$4" \
    -f 'variables[][key]=PIPELINE_ENV' -f "variables[][value]=$1" \
    -f 'variables[][key]=PIPELINE_SHA' -f "variables[][value]=$2" \
    -f 'variables[][key]=PIPELINE_TICKET' -f "variables[][value]=$3" | json '.id' > "${TMPDIR:-/tmp}/pipeline-dispatch.$1" || die "could not start the $1 pipeline"
}
gl_wait() { # env sha [ref]
  local p id="" st f="${TMPDIR:-/tmp}/pipeline-dispatch.$1"; p="$(gl_pid)"
  [ -f "$f" ] && { id="$(cat "$f")"; rm -f "$f"; }
  for _ in $(seq 1 "$tries"); do
    [ -n "$id" ] || id="$($glab_cmd api "projects/$p/pipelines?sha=$2${3:+&ref=$(urlenc "$3")}&order_by=id&sort=desc" 2>/dev/null | json '.[0].id // empty')"
    if [ -n "$id" ]; then
      st="$($glab_cmd api "projects/$p/pipelines/$id" 2>/dev/null | json '.status')"
      case "$st" in success) echo "host.sh: pipeline $id passed"; return 0;; failed|canceled|skipped) die "pipeline $id for $1 ended $st";; esac
    fi
    sleep 8
  done
  die "no finished '$1' pipeline for $2"
}
gl_var_get() { $glab_cmd api "projects/$(gl_pid)/variables/$1" 2>/dev/null | json '.value'; }
gl_var_set() { local p; p="$(gl_pid)"
  $glab_cmd api -X PUT "projects/$p/variables/$1" -f value="$2" >/dev/null 2>&1 || $glab_cmd api -X POST "projects/$p/variables" -f key="$1" -f value="$2" >/dev/null; }
gl_protect() { # protected branch (no direct pushes) + merges only when the pipeline succeeded
  local p; p="$(gl_pid)"
  $glab_cmd api -X POST "projects/$p/protected_branches" -f name="$1" -f push_access_level=0 -f merge_access_level=30 -F allow_force_push=false >/dev/null 2>&1 || true
  $glab_cmd api -X PUT "projects/$p" -F only_allow_merge_if_pipeline_succeeds=true >/dev/null
}
gl_enforcement() {
  local p prot ok=1 b msg
  msg="$(gl_check)" || say unknown "Enforcement: unknown ($msg)."
  p="$(gl_pid)"
  for b in "$base" "$stg"; do
    prot="$($glab_cmd api "projects/$p/protected_branches/$(urlenc "$b")" 2>/dev/null | json '.name // empty')"
    [ -n "$prot" ] || ok=0
  done
  [ "$($glab_cmd api "projects/$p" 2>/dev/null | json '.only_allow_merge_if_pipeline_succeeds')" = true ] || ok=0
  [ "$ok" = 1 ] && say host "Enforcement: host. $base and $stg are protected and merge requests merge only when the pipeline (with the Pipeline Gate job) succeeds."
  say local "Enforcement: local hook only. $base/$stg are not both protected, or merges do not require a passing pipeline. /pipeline-init can set both. Until then the hook gates agent sessions only."
}
gl_web() { echo "${host_url:-https://gitlab.com}/$(remote_path)"; }

# ---------------------------------------------------------------- Bitbucket Cloud (REST) ----
# Auth: BITBUCKET_EMAIL + BITBUCKET_API_TOKEN (an Atlassian API token with Bitbucket scopes), from the environment or
# from ~/.config/ship-pipeline/bitbucket.env (written by connect.sh, never committed).
bb_env() { local f="${XDG_CONFIG_HOME:-$HOME/.config}/ship-pipeline/bitbucket.env"
  # shellcheck disable=SC1090
  [ -n "${BITBUCKET_API_TOKEN:-}" ] || { [ -f "$f" ] && source "$f"; }; }
bb_api_base() { [ -n "$host_url" ] && [ "$host_url" != "https://bitbucket.org" ] && echo "$host_url/rest/api/1.0" || echo "https://api.bitbucket.org/2.0"; }
bb() { # method path [json-body]
  bb_env
  local body=(); [ -n "${3:-}" ] && body=(-H 'Content-Type: application/json' --data "$3")
  $curl_cmd -fsS -u "${BITBUCKET_EMAIL:-}:${BITBUCKET_API_TOKEN:-}" -X "$1" "$(bb_api_base)/$2" ${body[@]+"${body[@]}"}
}
bb_repo() { echo "repositories/$(remote_path)"; }
bb_check() {
  have "$curl_cmd" || { echo "curl is not installed"; return 1; }
  bb_env; [ -n "${BITBUCKET_API_TOKEN:-}" ] || { echo "no Bitbucket API token (BITBUCKET_EMAIL/BITBUCKET_API_TOKEN)"; return 1; }
  [ -z "$host_url" ] || [ "$host_url" = "https://bitbucket.org" ] || { echo "Bitbucket Data Center ($host_url) is supported for git and CI only, not for API promotion"; return 1; }
  bb GET "$(bb_repo)" >/dev/null 2>&1 || { echo "the Bitbucket API token cannot read $(remote_path)"; return 1; }
}
bb_merge() { # branch base title
  local r id; r="$(bb_repo)"
  id="$(bb GET "$r/pullrequests?state=OPEN&q=$(urlenc "source.branch.name=\"$1\" AND destination.branch.name=\"$2\"")" 2>/dev/null | json '.values[0].id // empty')"
  if [ -z "$id" ]; then
    id="$(bb POST "$r/pullrequests" "{\"title\":\"$3\",\"source\":{\"branch\":{\"name\":\"$1\"}},\"destination\":{\"branch\":{\"name\":\"$2\"}},\"description\":\"Pipeline ticket. See docs/pipeline/.\"}" | json '.id')" \
      || die "could not create a pull request"
  fi
  bb POST "$r/pullrequests/$id/merge" '{"merge_strategy":"merge_commit"}' >/dev/null || die "Bitbucket refused to merge PR #$id"
}
bb_set_ref() {
  local r name; r="$(bb_repo)"
  case "$1" in
    refs/tags/*) name="${1#refs/tags/}"; bb POST "$r/refs/tags" "{\"name\":\"$name\",\"target\":{\"hash\":\"$2\"}}" >/dev/null || die "could not create tag $name";;
    refs/heads/*) name="${1#refs/heads/}"
      if git ls-remote --exit-code --heads "$remote" "$name" >/dev/null 2>&1; then git push -q "$remote" "$2:$1" || die "push to $1 rejected"
      else bb POST "$r/refs/branches" "{\"name\":\"$name\",\"target\":{\"hash\":\"$2\"}}" >/dev/null || die "could not create branch $name"; fi;;
  esac
}
bb_dispatch() { # env sha ticket ref -> the custom "deploy" pipeline
  bb POST "$(bb_repo)/pipelines/" "{\"target\":{\"type\":\"pipeline_ref_target\",\"ref_type\":\"branch\",\"ref_name\":\"$4\",\"selector\":{\"type\":\"custom\",\"pattern\":\"deploy\"}},\"variables\":[{\"key\":\"PIPELINE_ENV\",\"value\":\"$1\"},{\"key\":\"PIPELINE_SHA\",\"value\":\"$2\"},{\"key\":\"PIPELINE_TICKET\",\"value\":\"$3\"}]}" \
    | json '.uuid' > "${TMPDIR:-/tmp}/pipeline-dispatch.$1" || die "could not start the $1 pipeline"
}
bb_wait() {
  local r id="" st f="${TMPDIR:-/tmp}/pipeline-dispatch.$1"; r="$(bb_repo)"
  [ -f "$f" ] && { id="$(cat "$f")"; rm -f "$f"; }
  for _ in $(seq 1 "$tries"); do
    [ -n "$id" ] || id="$(bb GET "$r/pipelines/?sort=-created_on&pagelen=20" 2>/dev/null | json "[.values[] | select(.target.commit.hash==\"$2\" and (\"${3:-}\" == \"\" or .target.ref_name==\"${3:-}\"))][0].uuid // empty")"
    if [ -n "$id" ]; then
      st="$(bb GET "$r/pipelines/$(urlenc "$id")" 2>/dev/null | json '(.state.name) + "/" + (.state.result.name // "")')"
      case "$st" in COMPLETED/SUCCESSFUL) echo "host.sh: pipeline $id passed"; return 0;; COMPLETED/*) die "pipeline $id for $1 ended $st";; esac
    fi
    sleep 8
  done
  die "no finished '$1' pipeline for $2"
}
bb_var_get() { bb GET "$(bb_repo)/pipelines_config/variables/?pagelen=100" 2>/dev/null | json "[.values[] | select(.key==\"$1\")][0].value // empty"; }
bb_var_set() { local r u; r="$(bb_repo)"; u="$(bb GET "$r/pipelines_config/variables/?pagelen=100" 2>/dev/null | json "[.values[] | select(.key==\"$1\")][0].uuid // empty")"
  if [ -n "$u" ]; then bb PUT "$r/pipelines_config/variables/$(urlenc "$u")" "{\"key\":\"$1\",\"value\":\"$2\",\"secured\":false}" >/dev/null
  else bb POST "$r/pipelines_config/variables/" "{\"key\":\"$1\",\"value\":\"$2\",\"secured\":false}" >/dev/null; fi; }
bb_protect() {
  local r k; r="$(bb_repo)"
  for k in force delete; do bb POST "$r/branch-restrictions" "{\"kind\":\"$k\",\"branch_match_kind\":\"glob\",\"pattern\":\"$1\"}" >/dev/null 2>&1 || true; done
  bb POST "$r/branch-restrictions" "{\"kind\":\"require_passing_builds_to_merge\",\"branch_match_kind\":\"glob\",\"pattern\":\"$1\",\"value\":1}" >/dev/null
}
bb_enforcement() {
  local msg kinds ok=1 b
  msg="$(bb_check)" || say unknown "Enforcement: unknown ($msg)."
  kinds="$(bb GET "$(bb_repo)/branch-restrictions?pagelen=100" 2>/dev/null | json '[.values[] | .pattern + "=" + .kind] | join(",")')"
  for b in "$base" "$stg"; do case ",$kinds," in *",$b=require_passing_builds_to_merge,"*) ;; *) ok=0;; esac; done
  [ "$ok" = 1 ] && say host "Enforcement: host. Pull requests into $base and $stg need a passing build (the Pipeline Gate step)."
  say local "Enforcement: local hook only. $base/$stg have no 'require passing builds' restriction (a Premium feature on Bitbucket Cloud). /pipeline-init can add it. Until then the hook gates agent sessions only."
}
bb_web() { echo "https://bitbucket.org/$(remote_path)"; }

# ---------------------------------------------------------------- dispatch ----
say() { echo "ENFORCEMENT=$1"; echo "$2"; exit 0; }
case "$host" in github) pfx=gh;; gitlab) pfx=gl;; bitbucket) pfx=bb;; *) die "unknown GIT_HOST '$host' (github | gitlab | bitbucket)";; esac
verb="${1:-}"; [ $# -gt 0 ] && shift
base="$(bash "$here/base-ref.sh" --branch)"; stg="$(bash "$here/base-ref.sh" --staging)"
case "$verb" in
  name) echo "$host";;
  check) "${pfx}_check";;
  slug) case "$pfx" in gh) gh_slug;; *) remote_path;; esac;;
  merge) [ $# -ge 3 ] || die "usage: host.sh merge <branch> <base> <title>"; "${pfx}_merge" "$@";;
  set-ref) [ $# -ge 2 ] || die "usage: host.sh set-ref <ref> <sha>"; "${pfx}_set_ref" "$@";;
  dispatch) [ $# -ge 4 ] || die "usage: host.sh dispatch <env> <sha> <ticket> <ref>"; "${pfx}_dispatch" "$@";;
  wait) [ $# -ge 2 ] || die "usage: host.sh wait <env> <sha> [ref]"; "${pfx}_wait" "$@";;
  var-get) "${pfx}_var_get" "$1";;
  var-set) "${pfx}_var_set" "$1" "$2";;
  protect) "${pfx}_protect" "$1";;
  enforcement) "${pfx}_enforcement";;
  web-url) "${pfx}_web";;
  *) die "usage: host.sh <name|check|slug|merge|set-ref|dispatch|wait|var-get|var-set|protect|enforcement|web-url>";;
esac
