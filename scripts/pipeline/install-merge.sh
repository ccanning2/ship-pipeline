#!/usr/bin/env bash
# The install route: /pipeline-init's one way to merge the pipeline's own install (or upgrade) into the trunk with no
# ticket and no human review (docs/pipeline/BRANCHING.md, "Repository maintenance without a ticket").
# Usage: install-merge.sh              verify, push the install branch, open or reuse the request, merge it
#        install-merge.sh --open-only  push the install branch and open or reuse the request; never merge
# Run it on the install branch, one commit (or more) on top of <remote>/<trunk>. Before any push, the merge form checks
# with the plugin's own copy of scripts/init.sh (--verify-install) that every changed file is one the install writes
# and every tooling file matches the plugin's copy. The guard hook runs the same check before it lets an agent run this.
# Output and exit:
#   0  MERGED <url> (then any NOTE <text> lines) | OPENED <url> with --open-only
#   1  usage, nothing to merge, no remote, or not on the install branch
#   3  REFUSED <url> <reason>: the host (or the push) refused. Nothing is retried, forced or overridden: no admin or
#      bypass merge, no change to branch protection or rulesets, no label.
#   4  NOT-INSTALL <path>: <reason>: the commit is not only the install (checked before any push or host call)
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
one_line() { tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1 | cut -c1-300; }

remote="$(bash "$here/base-ref.sh" --remote)"; base="$(bash "$here/base-ref.sh" --branch)"
git remote get-url "$remote" >/dev/null 2>&1 || { echo "install-merge: no remote named '$remote'" >&2; exit 1; }
head="$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || { echo "install-merge: no commit to merge" >&2; exit 1; }
if git rev-parse -q --verify "refs/remotes/$remote/$base^{commit}" >/dev/null 2>&1 && git merge-base --is-ancestor "$head" "$remote/$base" 2>/dev/null; then
  echo "install-merge: nothing to merge: HEAD is already on $remote/$base" >&2; exit 1
fi
cur="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
[ "$cur" = "$install_branch" ] || { echo "install-merge: the current branch is '${cur:-a detached HEAD}', not '$install_branch'" >&2; exit 1; }

ref="$(plugin_root || true)"
if [ "$mode" = merge ]; then   # defence in depth: the same check the guard runs, before anything leaves this machine
  [ -n "$ref" ] || { echo "NOT-INSTALL: the plugin's installed copy could not be found"; exit 4; }
  if ! out="$(bash "$ref/scripts/init.sh" --verify-install --project-dir "$(pwd)" 2>&1)"; then
    p="${out%%$'\t'*}"; r="${out#*$'\t'}"; [ "$r" != "$out" ] || r="the install check failed: $(printf '%s' "$out" | one_line)"
    if [ "$p" = - ] || [ "$p" = "$out" ]; then echo "NOT-INSTALL: $r"; else echo "NOT-INSTALL $p: $r"; fi
    exit 4
  fi
fi

title="chore: install ship pipeline"
if git cat-file -e "refs/remotes/$remote/$base:scripts/pipeline/.install-manifest" 2>/dev/null; then
  v=""; [ -n "$ref" ] && v="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ref/.claude-plugin/plugin.json" | head -n 1)"
  title="chore: update ship pipeline${v:+ to v$v}"
fi
body="Ship pipeline install, opened and merged by /pipeline-init without a human review. Every file matches the plugin's copy or is a project file init.sh scaffolds (docs/pipeline/BRANCHING.md)."
web="$(bash "$here/host.sh" web-url 2>/dev/null | one_line)"; [ -n "$web" ] || web="$(git remote get-url "$remote" 2>/dev/null)"

# 1. push the install branch (never forced; nothing else is pushed)
if ! err="$(git push -q "$remote" "HEAD:refs/heads/$install_branch" 2>&1)"; then
  echo "REFUSED $web the push of $install_branch was rejected ($(printf '%s' "$err" | one_line))"; exit 3
fi
# 2. open the request, or reuse the open one from the install branch
if ! req="$(bash "$here/host.sh" request-open "$install_branch" "$base" "$title" "$body" 2>&1)"; then
  echo "REFUSED $web the request could not be opened ($(printf '%s' "$req" | one_line))"; exit 3
fi
req="$(printf '%s' "$req" | one_line)"; id="${req%% *}"; url="${req#* }"
[ -n "$id" ] && [ "$url" != "$req" ] || { echo "REFUSED $web the host did not say which request it opened"; exit 3; }
if [ "$mode" = open ]; then echo "OPENED $url"; exit 0; fi

# 3. merge it at the install commit: wait (bounded) while the host works out whether it can merge, check the request
#    still carries the install commit, then ask once. A refusal is final.
tries="${PIPELINE_WAIT_TRIES:-10}"; src=""; state=""
for t in $(seq 1 "$tries"); do
  info="$(bash "$here/host.sh" request-info "$id" 2>&1)" || { echo "REFUSED $url the request could not be read ($(printf '%s' "$info" | one_line))"; exit 3; }
  info="$(printf '%s' "$info" | one_line)"; src="${info%% *}"; state="${info#* }"
  [ "$state" = checking ] && [ "$t" -lt "$tries" ] || break
  sleep 3
done
case "$src" in
  ???????*) case "$head" in "$src"*) ;; *) echo "REFUSED $url the request's source commit is $src, not the install commit $head"; exit 3;; esac;;
  *) echo "REFUSED $url the host did not report the request's source commit"; exit 3;;
esac
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
