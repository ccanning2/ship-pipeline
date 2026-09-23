#!/usr/bin/env bash
# The Bitbucket Cloud code-host adapter, installed as scripts/pipeline/host.sh when GIT_HOST="bitbucket" (REST with an API token).
# Verbs and test doubles: scripts/pipeline/lib/host-common.sh. To change host, re-run /pipeline-init: it installs the
# matching adapter (the doctor flags an adapter that does not match GIT_HOST).
# adapter: host=bitbucket
set -uo pipefail
host=bitbucket; pfx=bb
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/host-common.sh"

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

host_main "$@"
