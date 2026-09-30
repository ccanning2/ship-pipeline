#!/usr/bin/env bash
# The install route: /pipeline-init's one way to merge the pipeline's own install (or upgrade) into the trunk with no
# ticket and no human review (docs/pipeline/BRANCHING.md, "Repository maintenance without a ticket").
# Usage: install-merge.sh              verify, push the install branch, open or reuse the request, merge it
#        install-merge.sh --open-only  push the install branch and open or reuse the request; never merge
# Run it on the install branch, one commit (or more) on top of the trunk. The merge form anchors its proof to the code
# host, never to a local ref: before any push it asks the host for the trunk's head (T), and checks with the plugin's
# own copy of scripts/init.sh (--verify-install --trunk-tip T) that T is an ancestor of the install commit and that
# every file changed since T is one the install writes, with every tooling file matching the plugin's copy. Right
# before the merge it reads the request and the trunk's head from the host again: the request must carry the install
# commit into the trunk, and the trunk must still be at T. So what the host merges is exactly what was checked. The
# guard hook's own check before it lets an agent run this is a network-free pre-check.
# pipeline.env is read as data here, never run (PIPELINE_ENV_AS_DATA, scripts/pipeline/base-ref.sh): the test doubles
# (PIPELINE_GH_CMD, PIPELINE_GLAB_CMD, PIPELINE_CURL_CMD) and PIPELINE_WAIT_TRIES count only from the environment.
# Output and exit:
#   0  MERGED <url> (then any NOTE <text> lines) | OPENED <url> with --open-only
#   1  usage, nothing to merge, no remote, or not on the install branch
#   3  REFUSED <url> <reason>: the host (or the push) refused, or the host could not be read or disagreed with the
#      check. Nothing is retried, forced or overridden: no admin or bypass merge, no change to branch protection or
#      rulesets, no label.
#   4  NOT-INSTALL <path>: <reason>: the commit is not only the install (checked before any push or request)
# The plugin's copy is PIPELINE_PLUGIN_ROOT when the environment sets it, else Claude Code's record of the installed
# plugin (installed_plugins.json). Host calls go through scripts/pipeline/host.sh (test doubles: lib/host-common.sh).
set -uo pipefail
install_branch="ship-pipeline/install"
plugin_name="ship-pipeline"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # scripts/pipeline
mode=merge
case "$#:${1:-}" in
  0:) ;;
  1:--open-only) mode=open;;
  *) echo "usage: install-merge.sh [--open-only]" >&2; exit 1;;
esac
cd "$here/../.." || exit 1
# FR-18: pipeline.env is data for everything this runs; FR-17.3: ancestry and diffs in real history only
nograft="$(mktemp -d)"; trap 'rm -rf "$nograft"' EXIT
export PIPELINE_ENV_AS_DATA=1 GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE="$nograft/none"
G="git -c core.commitGraph=false"

# the plugin's own copy: the environment Claude Code (or the owner) started with, else Claude Code's own record
plugin_root() {
  local f p ps n
  if [ -n "${PIPELINE_PLUGIN_ROOT:-}" ]; then p="$PIPELINE_PLUGIN_ROOT"
  else
    f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"; [ -f "$f" ] || return 1
    if command -v jq >/dev/null 2>&1; then
      ps="$(jq -r --arg n "$plugin_name@" '.plugins // {} | to_entries[] | select(.key | startswith($n)) | .value | (if type == "array" then .[] else . end) | .installPath // empty' "$f" 2>/dev/null)" || return 1
    else
      local py="" c; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { py="$c"; break; }; done
      [ -n "$py" ] || return 1
      ps="$($py -c 'import json,sys
d=json.load(open(sys.argv[1])).get("plugins") or {}
for k,v in d.items():
    if k.startswith(sys.argv[2]):
        for e in (v if isinstance(v,list) else [v]):
            if e.get("installPath"): print(e["installPath"])' "$f" "$plugin_name@" 2>/dev/null)" || return 1
    fi
    ps="$(printf '%s\n' "$ps" | tr '\\' '/' | tr -d '\r' | sed '/^$/d' | sort -u)"
    n="$(printf '%s\n' "$ps" | sed '/^$/d' | wc -l | tr -d ' ')"
    [ "$n" = 1 ] || return 1   # none, or two recorded installs that disagree
    p="$ps"
  fi
  [ -f "$p/scripts/init.sh" ] && [ -f "$p/.claude-plugin/plugin.json" ] || return 1
  printf '%s' "$p"
}
runnable_root() { # <plugin root> <empty private dir>: the root, or (its scripts checked out with CRLF, which bash off
  # Windows cannot run) a copy in the dir with CR stripped from every .sh. Comparisons ignore CR, so the check is the same.
  local p="$1" t="$2/plugin"
  grep -q $'\r' "$p/scripts/init.sh" 2>/dev/null || { printf '%s' "$p"; return 0; }
  mkdir "$t" && cp -R "$p/." "$t/" || return 1
  find "$t" -type f -name '*.sh' -exec sh -c 'for f; do tr -d "\r" < "$f" > "$f.lf" && mv "$f.lf" "$f" || exit 1; done' sh {} + || return 1
  printf '%s' "$t"
}
one_line() { tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1 | cut -c1-300; }
# host_tip <var>: the trunk's head as the host reports it (one attempt); on failure <var> holds the reason, exit 1
host_tip() {
  local out err rc=0
  out="$(bash "$here/host.sh" branch-head "$base" 2>"$nograft/err")" || rc=$?
  out="$(printf '%s' "$out" | tr -d '\r' | sed '/^[[:space:]]*$/d')"
  if [ "$rc" != 0 ]; then
    err="$( (cat "$nograft/err" 2>/dev/null; printf '%s\n' "$out") | sed 's/^host\.sh: //' | one_line)"
    printf -v "$1" '%s' "${err:-the host call failed}"; return 1
  fi
  case "$out" in
    *[!0-9a-f]*|"") printf -v "$1" '%s' "the host's answer is not a full commit sha"; return 1;;
  esac
  [ ${#out} -eq 40 ] || [ ${#out} -eq 64 ] || { printf -v "$1" '%s' "the host's answer is not a full commit sha"; return 1; }
  printf -v "$1" '%s' "$out"
}

remote="$(bash "$here/base-ref.sh" --remote)"; base="$(bash "$here/base-ref.sh" --branch)"
git remote get-url "$remote" >/dev/null 2>&1 || { echo "install-merge: no remote named '$remote'" >&2; exit 1; }
head="$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || { echo "install-merge: no commit to merge" >&2; exit 1; }
# a local early exit only (it can refuse, never allow): the merge form checks "nothing to merge" against T below
if git rev-parse -q --verify "refs/remotes/$remote/$base^{commit}" >/dev/null 2>&1 \
   && $G merge-base --is-ancestor "$head" "refs/remotes/$remote/$base" 2>/dev/null; then
  echo "install-merge: nothing to merge: HEAD is already on $remote/$base" >&2; exit 1
fi
cur="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
[ "$cur" = "$install_branch" ] || { echo "install-merge: the current branch is '${cur:-a detached HEAD}', not '$install_branch'" >&2; exit 1; }

ref="$(plugin_root || true)"
web="$(bash "$here/host.sh" web-url 2>/dev/null | one_line)"; [ -n "$web" ] || web="$(git remote get-url "$remote" 2>/dev/null)"
title="chore: install ship pipeline"
if [ "$mode" = merge ]; then
  [ -n "$ref" ] || { echo "NOT-INSTALL: the plugin's installed copy could not be found"; exit 4; }
  # FR-17.1: the trunk tip T is what the host says, in the repository the request is merged in; no local ref is T
  host_tip T || { echo "REFUSED $web the trunk tip could not be read from the host ($T)"; exit 3; }
  # FR-17.2: the commit whose id is T, fetched when it is not here yet (looked up by id only, never through a ref)
  if ! git cat-file -e "$T^{commit}" 2>/dev/null; then
    git fetch -q "$remote" "$base" >/dev/null 2>&1 || true
    git cat-file -e "$T^{commit}" 2>/dev/null || { echo "REFUSED $web the host's trunk tip $T could not be fetched"; exit 3; }
  fi
  if $G merge-base --is-ancestor "$head" "$T" 2>/dev/null; then
    echo "install-merge: nothing to merge: HEAD is already on the host's $base ($T)" >&2; exit 1
  fi
  # FR-17.3: the proof against T, by the plugin's own verifier, before anything leaves this machine
  run="$(runnable_root "$ref" "$nograft")" || { echo "NOT-INSTALL: the plugin's installed copy could not be prepared for the check"; exit 4; }
  if ! out="$(bash "$run/scripts/init.sh" --verify-install --trunk-tip "$T" --project-dir "$(pwd)" 2>&1)"; then
    p="${out%%$'\t'*}"; r="${out#*$'\t'}"; [ "$r" != "$out" ] || r="the install check failed: $(printf '%s' "$out" | one_line)"
    r="$(printf '%s' "$r" | one_line)"
    if [ "$p" = - ] || [ "$p" = "$out" ]; then echo "NOT-INSTALL: $r"; else echo "NOT-INSTALL $p: $r"; fi
    exit 4
  fi
  if git cat-file -e "$T:scripts/pipeline/.install-manifest" 2>/dev/null; then
    v="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ref/.claude-plugin/plugin.json" | head -n 1)"
    title="chore: update ship pipeline${v:+ to v$v}"
  fi
elif git cat-file -e "refs/remotes/$remote/$base:scripts/pipeline/.install-manifest" 2>/dev/null; then
  # --open-only reads no trunk tip from the host (it never merges): the title is only a label
  v=""; [ -n "$ref" ] && v="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ref/.claude-plugin/plugin.json" | head -n 1)"
  title="chore: update ship pipeline${v:+ to v$v}"
fi
body="Ship pipeline install, opened and merged by /pipeline-init without a human review. Every file matches the plugin's copy or is a project file init.sh scaffolds (docs/pipeline/BRANCHING.md)."

# 1. push the install commit to the install branch (never forced; nothing else is pushed)
if ! err="$(git push -q "$remote" "$head:refs/heads/$install_branch" 2>&1)"; then
  echo "REFUSED $web the push of $install_branch was rejected ($(printf '%s' "$err" | one_line))"; exit 3
fi
# 2. open the request, or reuse the open one from the install branch
if ! req="$(bash "$here/host.sh" request-open "$install_branch" "$base" "$title" "$body" 2>&1)"; then
  echo "REFUSED $web the request could not be opened ($(printf '%s' "$req" | one_line))"; exit 3
fi
req="$(printf '%s' "$req" | one_line)"; id="${req%% *}"; url="${req#* }"
[ -n "$id" ] && [ "$url" != "$req" ] || { echo "REFUSED $web the host did not say which request it opened"; exit 3; }
if [ "$mode" = open ]; then echo "OPENED $url"; exit 0; fi

# 3. merge it at the install commit: wait (bounded) while the host works out whether it can merge, then (FR-17.4)
#    check from the host that the request carries the install commit into the trunk and the trunk is still at T.
#    Then ask once. A refusal is final.
tries="${PIPELINE_WAIT_TRIES:-10}"; src=""; state=""; target=""
for t in $(seq 1 "$tries"); do
  info="$(bash "$here/host.sh" request-info "$id" 2>&1)" || { echo "REFUSED $url the request could not be read ($(printf '%s' "$info" | sed 's/^host\.sh: //' | one_line))"; exit 3; }
  info="$(printf '%s' "$info" | one_line)"; src="${info%% *}"; state="${info#* }"; target="${state#* }"; state="${state%% *}"
  [ "$target" != "$info" ] && [ "$target" != "$state" ] || target=""
  [ "$state" = checking ] && [ "$t" -lt "$tries" ] || break
  sleep 3
done
case "$src" in
  ???????*) case "$head" in "$src"*) ;; *) echo "REFUSED $url the request's source commit is $src, not the install commit $head"; exit 3;; esac;;
  *) echo "REFUSED $url the host did not report the request's source commit"; exit 3;;
esac
[ -n "$target" ] || { echo "REFUSED $url the request could not be read (the host did not report its target branch)"; exit 3; }
[ "$target" = "$base" ] || { echo "REFUSED $url the request targets '$target', not '$base'"; exit 3; }
host_tip now || { echo "REFUSED $url the trunk tip could not be read from the host ($now)"; exit 3; }
[ "$now" = "$T" ] || { echo "REFUSED $url the trunk moved since the check (host: $now, checked: $T)"; exit 3; }
if ! m="$(bash "$here/host.sh" request-merge "$id" "$head" 2>&1)"; then
  r="$(printf '%s' "$m" | sed 's/^host\.sh: //' | one_line)"; echo "REFUSED $url ${r:-the host refused the merge}"; exit 3
fi
echo "MERGED $url"

# 4. the local trunk follows the remote one; the install branch goes (a failure here is only a note)
git fetch -q "$remote" "$base" 2>/dev/null || echo "NOTE could not fetch $remote/$base"
if git rev-parse -q --verify "refs/heads/$base" >/dev/null 2>&1; then git checkout -q "$base" 2>/dev/null || echo "NOTE could not switch to $base"
else git checkout -q -b "$base" "$remote/$base" 2>/dev/null || echo "NOTE could not create a local $base"; fi
git merge -q --ff-only "$remote/$base" 2>/dev/null || echo "NOTE could not fast-forward $base to $remote/$base"
git push -q "$remote" --delete "$install_branch" 2>/dev/null || echo "NOTE could not delete $install_branch on $remote (the host may have deleted it already)"
git branch -q -d "$install_branch" 2>/dev/null || echo "NOTE could not delete the local $install_branch"
exit 0
