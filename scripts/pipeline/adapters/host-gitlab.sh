#!/usr/bin/env bash
# The GitLab code-host adapter, installed as scripts/pipeline/host.sh when GIT_HOST="gitlab" (glab; self-managed through GIT_HOST_URL).
# Verbs and test doubles: scripts/pipeline/lib/host-common.sh. To change host, re-run /pipeline-init: it installs the
# matching adapter (the doctor flags an adapter that does not match GIT_HOST).
# adapter: host=gitlab
set -uo pipefail
host=gitlab; pfx=gl
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/host-common.sh"

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

host_main "$@"
