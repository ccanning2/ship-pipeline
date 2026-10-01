#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash). Enforces the branch/tag release model on agent tool calls:
#   push/merge into BASE_BRANCH          -> the ticket must pass the "dev" gate
#   push into STAGING_BRANCH             -> "qa" gate
#   push of a tag vX.Y.Z / gh release    -> "production" gate
# The command is split into simple commands (on ; & | && || newlines, subshells; quotes respected, heredoc
# bodies skipped; wrappers such as `bash -c`, sudo, xargs and eval are looked through) and only a simple command that IS `git push`, `git merge`, `gh pr merge`, `gh api` on a
# merge or ref, `gh release create`, their glab equivalents (`glab mr merge`, `glab api` on a merge or tag,
# `glab release create`) or `scripts/pipeline/host.sh merge|set-ref` is examined. Text in echo, grep, tail or a commit message never trips it.
# Never allowed from an agent, ticket or not: force pushes or deletes of the base/staging branch or a version
# tag, bulk pushes (--all, --mirror), and adding the `infra` label (a human's decision; see pipeline-gate.yml).
# One ticketless route is allowed: scripts/pipeline/install-merge.sh, /pipeline-init's merge of the pipeline's own
# install. It runs only on its own (no other command, no variable assignment), with no argument or exactly
# --open-only, and only when the plugin's own copy of scripts/init.sh (--verify-install) finds the files the route
# runs identical to the plugin's and, to merge, HEAD on the install branch and nothing but the install. The plugin's
# copy comes from this hook's environment (PIPELINE_PLUGIN_ROOT) or Claude Code's record of the installed plugin,
# never from the command or the repository.
# Exit 2 blocks (stderr shown to Claude). PIPELINE_BYPASS=1 in the environment Claude Code itself was started
# with lets a command through (announced). A command cannot set it for the hook: only the human can.
set -uo pipefail
input="$(cat)"
if command -v jq >/dev/null 2>&1; then cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  # A bare `python3` on PATH can be a non-functional stub (Windows), so probe for a real one.
  py=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { py="$c"; break; }; done
  cmd="$(printf '%s' "$input" | $py -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
fi
[ -n "$cmd" ] || exit 0
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"; cd "$project" 2>/dev/null || exit 0
P="$project/scripts/pipeline"
[ -f "$P/base-ref.sh" ] || exit 0
base="$(bash "$P/base-ref.sh" --branch)"; stg="$(bash "$P/base-ref.sh" --staging)"
git_host="$(grep -E '^[[:space:]]*GIT_HOST=' "$P/pipeline.env" 2>/dev/null | tail -n 1 | sed -E 's/^[^=]*=//; s/[[:space:]]+#.*$//' | tr -d "\"' " | tr '[:upper:]' '[:lower:]')"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
ticket_in() { bash "$P/ticket-id.sh" "$@" 2>/dev/null; }
semver='^v[0-9]+\.[0-9]+\.[0-9]+$'

# ---- split into simple commands, one per line ----
segments="$(printf '%s\n' "$cmd" | awk -v sq="'" '
  hd != "" { t=$0; if (strip) sub(/^\t+/, "", t); if (t == hd) hd=""; next }   # inside a heredoc body
  { line=$0; out=""; q=""; nexthd=""
    if (match(line, "<<-?[ \t]*[\"" sq "]?[A-Za-z_][A-Za-z0-9_]*") && substr(line, RSTART-1, 1) != "<" && substr(line, RSTART+2, 1) != "<") {
      m=substr(line, RSTART, RLENGTH); strip=(m ~ /^<<-/); sub("^<<-?[ \t]*[\"" sq "]?", "", m); nexthd=m
    }
    for (i=1; i<=length(line); i++) { c=substr(line,i,1)
      if (q != "") { if (c == q) { q=""; continue }; if (c ~ /[;&|()`]/) c=" "; out=out c; continue }
      if (c == "\"" || c == sq) { q=c; continue }
      if (c ~ /[;&|(){}`]/) { out=out "\n"; continue }
      out=out c }
    print out; hd=nexthd }')"

bypassed=0
block() { if [ "${PIPELINE_BYPASS:-0}" = 1 ]; then bypassed=1; return 0; fi; echo "$*" >&2; exit 2; }
human_only() { # <what>
  block "PIPELINE GATE: blocked '$seg': $1. An agent never does this. If it is really needed (for example a one-off bootstrap of a new remote), ask the owner to run it in their own terminal: this hook gates agent tool calls only. Do not try to get around it."
}
no_ticket() { # <stage>
  block "PIPELINE GATE: blocked '$seg' ($1 gate): no ticket id found in the command, branch '$branch', PIPELINE_TICKET or .claude/.pipeline-ticket.
Ways forward:
  - Ticket work: run /ship <TICKET>; scripts/pipeline/promote.sh moves the build through the gates.
  - Repository maintenance with no ticket (an install commit, a CI or dependency change): push a branch that is not $base or $stg and open a pull request. A human reviews it, adds the 'infra' label (docs/pipeline/BRANCHING.md) and merges it.
  - The pipeline's own install or upgrade: /pipeline-init merges it through scripts/pipeline/install-merge.sh, which accepts nothing but the plugin's own files.
  - Or ask the owner to run the command in their own terminal: this hook gates agent tool calls only.
Do not try to get around this hook."
}
# gate <stage> [ref]: needs a ticket, then the stage gate for it
gate() {
  local stage="$1" ref="${2:-}" ticket out
  ticket="$(ticket_in "$seg")" || ticket="$(ticket_in "$branch")" || ticket="$(ticket_in "${PIPELINE_TICKET:-}")" \
    || ticket="$(ticket_in "$(cat "$project/.claude/.pipeline-ticket" 2>/dev/null)")" || no_ticket "$stage"
  [ "${PIPELINE_BYPASS:-0}" = 1 ] && { bypassed=1; return 0; }
  if ! out="$(bash "$P/gate.sh" "$ticket" "$stage" $ref 2>&1)"; then
    echo "$out" >&2; block "PIPELINE GATE: blocked '$seg' ($stage gate). Use /ship $ticket, which promotes through scripts/pipeline/promote.sh."
  fi
}
dst_stage() { # <destination ref> -> dev | qa | production | nothing
  local d="${1#refs/heads/}"
  [ "$d" = HEAD ] && d="$branch"
  case "$1" in refs/tags/*) echo production; return;; esac
  if [[ "$d" =~ $semver ]]; then echo production; elif [ "$d" = "$stg" ]; then echo qa; elif [ "$d" = "$base" ]; then echo dev; fi
}

check_push() { # args after `push`
  local a force=0 del=0 skip=0 tags=0 pos=() stages="" rs src dst s
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      --all|--mirror|--branches) human_only "a bulk push ($a) moves $base, $stg and tags at once, outside the gates";;
      --tags) tags=1; stages="$stages production";;
      --follow-tags) stages="$stages production";;
      -f|--force|--force-with-lease*|--force-if-includes) force=1;;
      -d|--delete) del=1;;
      --repo|-o|--push-option|--receive-pack|--exec) skip=1;;
      -*) ;;
      *) pos+=("$a");;
    esac
  done
  [ "${#pos[@]}" -gt 0 ] || pos=(remote)
  [ "${#pos[@]}" -gt 1 ] || [ "$tags" = 1 ] || pos+=("$branch")   # no refspec: the current branch is pushed
  for rs in "${pos[@]:1}"; do
    case "$rs" in +*) force=1; rs="${rs#+}";; esac
    src="${rs%%:*}"; dst="$rs"; case "$rs" in *:*) dst="${rs#*:}"; [ -z "$src" ] && del=1;; esac
    [ -n "$dst" ] || dst="$src"
    # Bitbucket has no PR labels: an infra/* source branch is how a human marks a PR as maintenance with no ticket
    case "$git_host:${dst#refs/heads/}" in bitbucket:infra/*) human_only "pushing an infra/ branch, which lets a pull request skip the ticket requirement";; esac
    s="$(dst_stage "$dst")"; [ -n "$s" ] || continue
    [ "$force" = 1 ] && human_only "a force push to '$dst'. The release model never rewrites $base, $stg or a version tag"
    [ "$del" = 1 ] && human_only "deleting '$dst'"
    stages="$stages $s"
  done
  for s in $stages; do gate "$s"; done
}
check_merge() { # args after `merge`; gates when the current branch is base or staging
  local a ref="" stage=""
  [ "$branch" = "$base" ] && stage=dev; [ "$branch" = "$stg" ] && stage=qa
  [ -n "$stage" ] || return 0
  for a in "$@"; do case "$a" in --abort|--quit|--continue) return 0;; esac; done
  # a ref that carries a ticket id (e.g. feature/REP-1-x) is the build to gate
  for a in "$@"; do
    case "$a" in -*) continue;; esac
    ticket_in "$a" >/dev/null && git rev-parse --verify -q "${a}^{commit}" >/dev/null 2>&1 && { ref="$a"; break; }
  done
  gate "$stage" "$ref"
}
check_gh() { # args after `gh`
  local sub="${1:-}" act="${2:-}" a
  case "$sub $act" in
    "pr merge") gate dev; return;;
    "release create") gate production; return;;
    "pr edit"|"issue edit")
      for a in "$@"; do case ",$a," in *,infra,*) human_only "adding the 'infra' label, which lets a pull request skip the ticket requirement";; esac; done; return;;
  esac
  [ "$sub" = api ] || return 0
  local all=" $* "
  case "$all" in *" infra "*|*"labels[]=infra"*|*"labels=infra"*) case "$all" in *labels*) human_only "adding the 'infra' label";; esac;; esac
  for a in "$@"; do
    if [[ "$a" =~ pulls/[0-9]+/merge ]]; then gate dev; return; fi
    case "$a" in
      */git/refs/tags/*|ref=refs/tags/*) gate production; return;;
      */git/refs/heads/*) s="$(dst_stage "${a##*/git/refs/heads/}")"; [ -n "$s" ] && { gate "$s"; return; };;
      ref=refs/heads/*) s="$(dst_stage "${a#ref=}")"; [ -n "$s" ] && { gate "$s"; return; };;
    esac
  done
}
check_glab() { # args after `glab`
  local sub="${1:-}" act="${2:-}" a all=" $* " method=""
  case "$sub $act" in
    "mr merge") gate dev; return;;
    "release create") gate production; return;;
    "mr update"|"issue update"|"mr create"|"issue create")
      for a in "$@"; do case ",$a," in *,infra,*) human_only "adding the 'infra' label, which lets a merge request skip the ticket requirement";; esac; done; return;;
  esac
  [ "$sub" = api ] || return 0
  case "$all" in *labels=infra*|*labels=*,infra*|*add_labels=*infra*) human_only "adding the 'infra' label";; esac
  for a in "$@"; do case "$a" in POST|PUT|PATCH|DELETE) method="$a";; esac; done
  for a in "$@"; do
    case "$a" in
      */merge_requests/*/merge|*/merge_requests/*/merge\?*) gate dev; return;;
      */repository/tags*) [ -n "$method" ] && { gate production; return; };;
      branch=*) s="$(dst_stage "${a#branch=}")"; [ -n "$s" ] && { gate "$s"; return; };;
    esac
  done
}
check_host() { # args after scripts/pipeline/host.sh: merge and set-ref move the base branch, the staging branch or a tag
  local s
  case "${1:-}" in
    merge) s="$(dst_stage "${3:-}")"; gate "${s:-dev}";;
    request-merge) gate dev;;   # merges a PR/MR by id, like gh pr merge
    set-ref) s="$(dst_stage "${2:-}")"; [ -n "$s" ] && gate "$s";;
  esac
  return 0
}

# ---- the install route: scripts/pipeline/install-merge.sh (SHI-45) ----
plugin_name=ship-pipeline
json_field() { # <field> of the hook input
  if command -v jq >/dev/null 2>&1; then printf '%s' "$input" | jq -r ".$1 // empty" 2>/dev/null
  else
    local p="" c; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { p="$c"; break; }; done
    [ -n "$p" ] && printf '%s' "$input" | $p -c 'import sys,json; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null
  fi
}
plugin_root() { # the plugin's own copy: this hook's environment, else Claude Code's record of the installed plugin
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
check_route() { # after every segment: route_seg, route_path, route_args and route_alone describe the route's call
  local ref run tmp out r cwd abs d want a k=0 mode=""
  [ "${PIPELINE_BYPASS:-0}" = 1 ] && { bypassed=1; return 0; }
  refuse() {
    block "PIPELINE GATE: blocked '$route_seg' (install route): $1. This route merges only the pipeline's own install: every changed file must be one that scripts/init.sh installs, and each tooling file must match the plugin's copy. Way forward: run 'bash scripts/pipeline/install-merge.sh --open-only' and leave the request for the owner to mark infra and merge. Do not try to get around this hook."
  }
  # a. the project's own route, however the path is spelled
  cwd="$(json_field cwd | tr '\\' '/')"; [ -n "$cwd" ] || cwd="$project"
  case "$route_path" in /*|[A-Za-z]:/*|[A-Za-z]:\\*) abs="$(printf '%s' "$route_path" | tr '\\' '/')";; *) abs="$cwd/$route_path";; esac
  d="$(cd "${abs%/*}" 2>/dev/null && pwd -P)"; want="$(cd "$P" 2>/dev/null && pwd -P)"
  [ -n "$d" ] && [ "$d" = "$want" ] && [ "${abs##*/}" = install-merge.sh ] || refuse "the route must be run as scripts/pipeline/install-merge.sh"
  # b. no argument, or exactly --open-only
  for a in ${route_args[@]+"${route_args[@]}"}; do
    if [ "$k" = 0 ] && [ "$a" = --open-only ]; then mode=--open-only; else refuse "unexpected argument '$a'"; fi
    k=$((k+1))
  done
  # c, d. the plugin's own init.sh checks the route's files and, to merge, the install commit
  ref="$(plugin_root)" || refuse "the plugin's installed copy could not be found"
  tmp="$(mktemp -d)" || refuse "no private directory for the install check"
  run="$(runnable_root "$ref" "$tmp")" || { rm -rf "$tmp"; refuse "the plugin's installed copy could not be prepared for the check"; }
  r=0; out="$(bash "$run/scripts/init.sh" --verify-install $mode --project-dir "$project" 2>&1)" || r=$?
  rm -rf "$tmp"
  if [ "$r" != 0 ]; then
    r="${out#*$'\t'}"; [ "$r" != "$out" ] || r="the install check failed ($(printf '%s' "$out" | tr -d '\r' | head -n 1))"
    refuse "$(printf '%s' "$r" | head -n 1)"
  fi
  # nothing may run before, beside or after it in the same call (it could change what was just checked)
  [ "$route_alone" = 1 ] || refuse "the route must run on its own: no variable assignment and no other command in the same call"
}

route_n=0; nprog=0; route_seg=""; route_path=""; route_args=(); route_assign=0
set -f
while IFS= read -r seg; do
  read -ra w <<<"$seg" || true
  i=0; n=${#w[@]}; seg_assign=0
  # leading assignments and keywords are not the command; a wrapper (bash -c, sudo, xargs, eval, ...) runs the
  # words after it, so it is skipped together with its options and the command it wraps is examined instead
  while [ "$i" -lt "$n" ]; do
    # an assignment whose value holds a / (FOO=/x) is still an assignment, not a program named x
    case "${w[$i]}" in [A-Za-z_]*=*) seg_assign=1; i=$((i+1)); continue;; esac
    case "${w[$i]##*/}" in
      [A-Za-z_]*=*) seg_assign=1; i=$((i+1));;
      then|do|else|'!') i=$((i+1));;
      command|exec|time|nohup|env|sudo|doas|nice|timeout|xargs|eval|bash|sh|zsh|dash|ksh)
        i=$((i+1))
        while [ "$i" -lt "$n" ]; do case "${w[$i]}" in [A-Za-z_]*=*) seg_assign=1; i=$((i+1));; -*|[0-9]*) i=$((i+1));; *) break;; esac; done;;
      *) break;;
    esac
  done
  [ "$i" -lt "$n" ] || continue
  args=(); j=$((i+1)); prog="${w[$i]##*/}"
  case "$prog" in *[!0-9]*) nprog=$((nprog+1));; esac   # a bare number is the tail of a 2>&1, not a command
  while [ "$j" -lt "$n" ]; do
    t="${w[$j]}"
    case "$t" in
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>') j=$((j+2)); continue;;      # redirection and its target
      '>'*|'<'*|[0-9]'>'*) j=$((j+1)); continue;;
    esac
    args+=("$t"); j=$((j+1))
  done
  case "$prog" in
    git)
      k=0; while [ "$k" -lt "${#args[@]}" ]; do
        case "${args[$k]}" in -C|-c|--git-dir|--work-tree|--namespace) k=$((k+2));; -*) k=$((k+1));; *) break;; esac
      done
      [ "$k" -lt "${#args[@]}" ] || continue
      sub="${args[$k]}"; rest=("${args[@]:$((k+1))}")
      # ${a[@]+"${a[@]}"}: an empty array under set -u is an error in bash 3.2 (macOS)
      case "$sub" in push) check_push ${rest[@]+"${rest[@]}"};; merge) check_merge ${rest[@]+"${rest[@]}"};; esac;;
    gh) check_gh ${args[@]+"${args[@]}"};;
    glab) check_glab ${args[@]+"${args[@]}"};;
    host.sh) check_host ${args[@]+"${args[@]}"};;
    install-merge.sh) route_n=$((route_n+1)); route_seg="$seg"; route_path="${w[$i]}"; route_args=(${args[@]+"${args[@]}"}); route_assign=$seg_assign;;
  esac
done <<<"$segments"
if [ "$route_n" -gt 0 ]; then   # decided last, so a push or merge beside it is refused for what it is
  route_alone=0; [ "$route_n" = 1 ] && [ "$nprog" = 1 ] && [ "$route_assign" = 0 ] && route_alone=1
  check_route
fi
set +f
[ "$bypassed" = 1 ] && echo "PIPELINE GATE: bypassed via PIPELINE_BYPASS=1 for: $cmd" >&2
exit 0
