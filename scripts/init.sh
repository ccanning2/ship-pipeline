#!/usr/bin/env bash
# Scaffold (or update) the pipeline in a project. Idempotent; never overwrites project-owned files.
# Usage: init.sh [--project-dir DIR] [--name NAME] [--team-key KEY] [--profile NAME] [--force-tooling]
#               [--base-branch NAME] [--staging-branch NAME] [--no-deploy-envs]
#               [--git-host github|gitlab|bitbucket] [--git-url URL] [--tracker jira|linear|github|gitlab|connector]
#               [--tracker-url URL] [--tracker-cloud-id ID] [--deploy-mode merge|explicit]
#               [--dev-url URL] [--qa-url URL] [--staging-url URL] [--production-url URL] [--health-path PATH]
#               [--create-branches] [--start-at analysis|engineering|devops|qa]
# Every question /pipeline-init asks has a flag here, so one run installs everything; nothing below prompts.
#   --git-host        default: GIT_HOST from an existing pipeline.env, else the remote's URL (gitlab / bitbucket),
#                     else github. Picks the CI files: .github/workflows/* (github), .gitlab/pipeline-*.yml plus an
#                     include in .gitlab-ci.yml (gitlab), bitbucket-pipelines.yml (bitbucket)
#   --git-url         a self-hosted code host's base URL (GitHub Enterprise, GitLab self-managed); empty = public service
#   --tracker         default: TRACKER from an existing pipeline.env, else linear. Tickets are read and written through
#                     scripts/pipeline/tracker.sh with the tracker's CLI; "connector" falls back to an MCP connector
#   --deploy-mode     merge (default): pushes and tags deploy; explicit: nothing deploys on a push, promote.sh
#                     dispatches every environment. CI template lines marked "#@on-merge" are dropped for explicit
#   --start-at        where /ship picks a ticket up (default analysis): analysis (product owner + business analyst),
#                     engineering (tickets arrive ready for dev), devops (built, ready to promote), qa (already on qa).
#                     The work upstream of the level is recorded by scripts/pipeline/handover.sh at intake
#   --create-branches push the base branch when the remote lacks it, and create the staging branch from the remote
#                     base branch when it is missing. Never moves or forces an existing branch
#   --base-branch     the trunk (merging here = dev). Default: BASE_BRANCH from an existing pipeline.env, else
#                     origin's default branch (origin/HEAD), else the current branch. Written into pipeline.env,
#                     the workflows and the docs; nothing assumes "master".
#   --staging-branch  default: STAGING_BRANCH from an existing pipeline.env, else "staging"
#   --force-tooling   also overwrite tooling files edited by hand since the last install (normally they are kept
#                     and the new version is written beside them as <file>.new), and refresh scripts/deploy/*
#   --no-deploy-envs  the project has no hosts/image/deploy workflow: no scripts/deploy/*, no deploy.yml,
#                     empty deploy keys, and PIPELINE_HAS_DEPLOY_ENVS="no" in a freshly created pipeline.env
#   Without --no-deploy-envs, an existing scripts/pipeline/pipeline.env is read (never written): a project
#   that already declares PIPELINE_HAS_DEPLOY_ENVS="no" is scaffolded as if the flag had been passed.
#   It never deletes anything from an existing install; the capability defaults to "yes".
#   Project-owned (created once, then yours): docs/pipeline/CONTEXT.md, RELEASE_CHECKLIST.md, scripts/pipeline/pipeline.env,
#     the host's CI files (.github/workflows/*.yml | .gitlab/*.yml + .gitlab-ci.yml | bitbucket-pipelines.yml),
#     scripts/deploy/*, .claude/settings.json
#   Tooling (refreshed on every run): scripts/pipeline/{gate,promote,intake,handover,status,next-version,check-signoff,
#     cloud-setup,ticket-id,base-ref,enforcement,doctor,connect,ci-gate,ci-resolve}.sh, scripts/pipeline/lib/*,
#     host.sh + tracker.sh (the adapters for the chosen platforms, from scripts/pipeline/adapters/), tracker-schema.txt,
#     scripts/pipeline/hooks/*, .claude/agents/*, docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md, docs/pipeline/_templates/*
#   The plugin's test suite (tests/pipeline/*) is never installed; an older install's untouched copy is removed.
#   scripts/pipeline/.install-manifest records a checksum of every tooling file as installed. A tooling file whose
#   content no longer matches its record was edited by hand: it is kept, and the new version goes to <file>.new.
#   .gitignore gains the pipeline's entries once, under "# ship-pipeline".
#   __BASE_BRANCH__ / __STAGING_BRANCH__ in any scaffolded file are replaced with the project's branch names.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(pwd)"; name=""; key=""; profile=""; force=0; deploy_envs=yes; base=""; stg=""
git_host=""; git_url=""; tracker=""; tracker_url=""; cloud_id=""; deploy_mode=merge; mkbranches=0; start=""
dev_url=""; qa_url=""; stg_url=""; prod_url=""; health=""
while [ $# -gt 0 ]; do case "$1" in
  --project-dir) dir="$2"; shift 2;; --name) name="$2"; shift 2;; --team-key) key="$2"; shift 2;;
  --profile) profile="$2"; shift 2;; --force-tooling) force=1; shift;;
  --base-branch) base="${2:-}"; shift 2;; --staging-branch) stg="${2:-}"; shift 2;;
  --no-deploy-envs) deploy_envs=no; shift;;
  --git-host) git_host="${2:-}"; shift 2;; --git-url) git_url="${2:-}"; shift 2;;
  --tracker) tracker="${2:-}"; shift 2;; --tracker-url) tracker_url="${2:-}"; shift 2;; --tracker-cloud-id) cloud_id="${2:-}"; shift 2;;
  --deploy-mode) deploy_mode="${2:-}"; shift 2;; --create-branches) mkbranches=1; shift;; --start-at) start="${2:-}"; shift 2;;
  --dev-url) dev_url="${2:-}"; shift 2;; --qa-url) qa_url="${2:-}"; shift 2;; --staging-url) stg_url="${2:-}"; shift 2;;
  --production-url) prod_url="${2:-}"; shift 2;; --health-path) health="${2:-}"; shift 2;;
  *) echo "unknown arg $1" >&2; exit 1;; esac; done
# --- argument validation: everything that can reject a run happens BEFORE the first file is copied ---
# (CONTEXT.md high-risk area / FR-15: an early exit must never leave a half-applied install behind)
src_ctx="$here/template/docs/pipeline/CONTEXT.md"; src_chk="$here/template/RELEASE_CHECKLIST.md"
if [ -n "$profile" ]; then
  [ -f "$here/profiles/$profile/CONTEXT.md" ] && [ -f "$here/profiles/$profile/RELEASE_CHECKLIST.md" ] \
    || { echo "init: unknown profile '$profile' (see $here/profiles)" >&2; exit 1; }
  src_ctx="$here/profiles/$profile/CONTEXT.md"; src_chk="$here/profiles/$profile/RELEASE_CHECKLIST.md"
fi
cd "$dir"; git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "init: $dir is not a git repository" >&2; exit 1; }
[ -n "$name" ] || name="$(basename "$(git rev-parse --show-toplevel)")"

# A project that already declared it has no deployable environments keeps that shape on a flagless
# re-run. The key is only ever READ: pipeline.env is project-owned and is never written, rewritten or
# deleted here (BR-13). Parsed with grep/sed rather than sourced, so nothing in the file is executed.
# Same fail-closed resolution as gate.sh/promote.sh: off only for an exact `no` once unquoted,
# trimmed and lowercased; absent, empty or anything else resolves on (today's stricter behaviour).
# Known limit: init reads pipeline.env as TEXT and does not evaluate shell control flow, so a value that
# only bash could resolve (inside `if false; then ... fi`, an uncalled function or a heredoc) is not seen.
declared_value() { # file key -> echoes the key's value when the last line naming it is a plain assignment; nothing otherwise
  local file="$1" key="$2" line v
  [ -f "$file" ] || return 0
  # The LAST line that mentions the key as a whole word decides, comments removed first: a `#` only starts
  # a comment when it follows whitespace (a `#` glued to a word is part of the value, as in bash), and the
  # comment itself may hold anything, quotes and apostrophes included.
  line="$(tr -d '\r' < "$file" \
    | sed -E 's/(^|[[:space:]])#.*$/\1/' \
    | grep -E "(^|[^A-Za-z0-9_])$key([^A-Za-z0-9_]|\$)" \
    | tail -n 1 || true)"
  [ -n "$line" ] || return 0
  # Only an exact assignment shape counts. Anything else on that last line -- `unset`, `+=`, `declare`,
  # `readonly`, another value, a mention in passing -- is unrecognised and falls through to strict.
  v="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/^export[[:space:]]+//; s/[[:space:]]+$//')"
  case "$v" in "$key="*) v="${v#"$key="}";; *) return 0;; esac
  case "$v" in '"'*'"') v="${v#\"}"; v="${v%\"}";; "'"*"'") v="${v#\'}"; v="${v%\'}";; esac
  # a quote that survives one matching outer pair is literal to bash ('"no"', "'no'", or an unbalanced quote)
  case "$v" in *\"*|*\'*) return 0;; esac
  printf '%s' "$v"
}
declared_capability() { # file key -> echoes "no" only when the key resolves to no; nothing otherwise
  case "$(declared_value "$1" "$2" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" in
    no) echo no;; esac
}

# Branch names: a flag wins, then what pipeline.env already says, then the remote's default branch, then the
# current branch. A value that only a shell could resolve ($VAR, a placeholder) is not a branch name.
plain_branch() { case "$1" in *'$'*|*__*) ;; *) printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//';; esac; }
if [ -z "$key" ] && [ -f scripts/pipeline/pipeline.env ]; then   # an existing install's key (for the report only)
  key="$(grep -E '^[[:space:]]*(export[[:space:]]+)?TRACKER_TEAM_KEY=' scripts/pipeline/pipeline.env | tail -n 1 \
    | sed -E 's/^[^=]*=//; s/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"'][[:space:]]*$//' | tr -cd 'A-Za-z0-9' || true)"
fi
[ -n "$key" ] || key="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z' | cut -c1-4)"
[ -n "$key" ] || key="PROJ"
base_from="--base-branch"
if [ -z "$base" ]; then base="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env BASE_BRANCH)")"; base_from="pipeline.env"; fi
if [ -z "$base" ]; then base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"; base="${base#origin/}"; base_from="origin/HEAD"; fi
if [ -z "$base" ]; then base="$(git symbolic-ref --short HEAD 2>/dev/null || true)"; base_from="the current branch"; fi
if [ -z "$base" ]; then base=master; base_from="default"; fi
[ -n "$stg" ] || stg="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env STAGING_BRANCH)")"
[ -n "$stg" ] || stg=staging
for b in "$base" "$stg"; do
  git check-ref-format --branch "$b" >/dev/null 2>&1 || { echo "init: '$b' is not a valid branch name" >&2; exit 1; }
done
[ "$base" != "$stg" ] || { echo "init: the base and staging branches must differ (both '$base')" >&2; exit 1; }
# code host: a flag wins, then pipeline.env, then the remote's URL
unfilled() { case "$1" in *__*) ;; *) printf '%s' "$1";; esac; }
[ -n "$git_host" ] || git_host="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env GIT_HOST)")"
if [ -z "$git_host" ]; then
  case "$(git remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
    *gitlab*) git_host=gitlab;; *bitbucket*) git_host=bitbucket;; *) git_host=github;; esac
fi
git_host="$(printf '%s' "$git_host" | tr '[:upper:]' '[:lower:]')"
case "$git_host" in github|gitlab|bitbucket) ;; *) echo "init: --git-host must be github, gitlab or bitbucket (got '$git_host')" >&2; exit 1;; esac
[ -n "$git_url" ] || git_url="$(unfilled "$(declared_value scripts/pipeline/pipeline.env GIT_HOST_URL)")"
[ -n "$tracker" ] || tracker="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env TRACKER)")"
[ -n "$tracker" ] || tracker=linear
tracker="$(printf '%s' "$tracker" | tr '[:upper:]' '[:lower:]')"
case "$tracker" in jira|linear|github|gitlab|connector) ;; *) echo "init: --tracker must be jira, linear, github, gitlab or connector (got '$tracker')" >&2; exit 1;; esac
[ -n "$tracker_url" ] || tracker_url="$(unfilled "$(declared_value scripts/pipeline/pipeline.env TRACKER_URL)")"
[ -n "$start" ] || start="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env PIPELINE_START_LEVEL)")"
start="$(printf '%s' "${start:-analysis}" | tr '[:upper:]' '[:lower:]')"
case "$start" in analysis|engineering|devops|qa) ;; *) echo "init: --start-at must be analysis, engineering, devops or qa (got '$start')" >&2; exit 1;; esac
case "$deploy_mode" in merge|explicit) ;; *) echo "init: --deploy-mode must be merge or explicit (got '$deploy_mode')" >&2; exit 1;; esac
for u in "$git_url" "$tracker_url" "$dev_url" "$qa_url" "$stg_url" "$prod_url"; do
  case "$u" in ""|http://*|https://*) ;; *) echo "init: '$u' is not an http(s) URL" >&2; exit 1;; esac
  case "$u" in *[[:space:]\"\'\#\\\|]*) echo "init: '$u' contains a character a URL cannot hold here" >&2; exit 1;; esac
done
case "$health" in ""|/*) ;; *) echo "init: --health-path must start with / (got '$health')" >&2; exit 1;; esac
case "$cloud_id$health" in *[!A-Za-z0-9/._-]*) echo "init: --tracker-cloud-id and --health-path take letters, digits and / . _ - only" >&2; exit 1;; esac
# an existing pipeline.env is never rewritten: a flag that picks another platform installs that adapter, and says
# which line of pipeline.env the owner (or /pipeline-init, with their yes) must change to match
env_note=""
for kv in "GIT_HOST:$git_host" "TRACKER:$tracker" "PIPELINE_START_LEVEL:$start"; do
  was="$(plain_branch "$(declared_value scripts/pipeline/pipeline.env "${kv%%:*}")" | tr '[:upper:]' '[:lower:]')"
  [ -z "$was" ] || [ "$was" = "${kv#*:}" ] || env_note="${env_note:+$env_note; }set ${kv%%:*}=\"${kv#*:}\" in scripts/pipeline/pipeline.env (it says $was)"
done
sed_esc() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }
base_esc="$(sed_esc "$base")"; stg_esc="$(sed_esc "$stg")"

declared_deploy_envs=""
if [ "$deploy_envs" = yes ]; then
  declared_deploy_envs="$(declared_capability scripts/pipeline/pipeline.env PIPELINE_HAS_DEPLOY_ENVS)"
  [ "$declared_deploy_envs" = no ] && deploy_envs=no || true
fi

created=(); updated=(); kept=(); customised=(); removed=(); retired_kept=()
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
render() { # src dst [out] -> sets $rendered to the file to install (no subshell: init copies ~60 files).
  # Only docs, CI files, the checklist and pipeline.env get the branch placeholders filled; scripts and agents are
  # copied verbatim (they may name a placeholder).
  local out="${3:-$tmpd/r}"
  case "$2" in
    .github/*|.gitlab/*|bitbucket-pipelines*.yml)
      # "#@on-merge" marks CI lines that deploy on a push or tag: kept (marker removed) for merge, dropped for explicit
      if [ "$deploy_mode" = explicit ]; then sed -e '/#@on-merge/d' "$1"; else sed -e 's/[[:space:]]*#@on-merge.*$//' "$1"; fi \
        | sed -e "s:__BASE_BRANCH__:$base_esc:g" -e "s:__STAGING_BRANCH__:$stg_esc:g" > "$out"; rendered="$out";;
    docs/*|RELEASE_CHECKLIST.md|scripts/pipeline/pipeline.env)
      sed -e "s:__BASE_BRANCH__:$base_esc:g" -e "s:__STAGING_BRANCH__:$stg_esc:g" "$1" > "$out"; rendered="$out";;
    *) rendered="$1";;
  esac
}
manifest=scripts/pipeline/.install-manifest; had_manifest=0; [ -f "$manifest" ] && had_manifest=1
manifest_lines=()   # "<sum> <size> <path>" for every tooling file, as installed
sum_of() { cksum < "$1" | awk '{print $1" "$2}'; }
ensure_dir() { case "$1" in */*) [ -d "${1%/*}" ] || mkdir -p "${1%/*}";; esac; }
recorded() { [ -f "$manifest" ] && awk -v p="$1" '$3==p {print $1" "$2}' "$manifest" || true; }
# Tooling is planned first and applied in one pass: one cksum over every source, one over every existing copy, and
# one cp per directory. Per-file cmp/cat/cksum made an install take ~20s on Windows, where each process is slow.
plan_src=(); plan_dst=()
copy_tooling() { plan_src+=("$1"); plan_dst+=("$2"); }
apply_tooling() {
  local n=${#plan_src[@]} i src dst rec a b rest want=() have=() ex=() inst=() queued=() d e srcs
  [ "$n" -gt 0 ] || return 0
  # docs only need the branch names filled: copy them into a mirror of their destination and fill them all with one sed
  local docs=() mdirs=()
  for ((i=0; i<n; i++)); do
    have+=("")
    case "${plan_dst[$i]}" in
      docs/*) inst+=("$tmpd/m/${plan_dst[$i]}"); docs+=("$i"); mdirs+=("$tmpd/m/${plan_dst[$i]%/*}");;
      *) render "${plan_src[$i]}" "${plan_dst[$i]}" "$tmpd/r$i"; inst+=("$rendered");;
    esac
  done
  if [ ${#docs[@]} -gt 0 ]; then
    mkdir -p $(printf '%s\n' "${mdirs[@]}" | sort -u)
    for d in $(printf '%s\n' "${mdirs[@]}" | sort -u); do
      srcs=(); for e in "${docs[@]}"; do [ "$tmpd/m/${plan_dst[$e]%/*}" = "$d" ] && srcs+=("${plan_src[$e]}"); done
      cp "${srcs[@]}" "$d/"
    done
    sed -i.bak -e "s:__BASE_BRANCH__:$base_esc:g" -e "s:__STAGING_BRANCH__:$stg_esc:g" $(for e in "${docs[@]}"; do printf '%s\n' "${inst[$e]}"; done)
  fi
  while read -r a b rest; do want+=("$a $b"); done < <(cksum "${inst[@]}")
  for ((i=0; i<n; i++)); do [ -f "${plan_dst[$i]}" ] && ex+=("$i"); done
  if [ ${#ex[@]} -gt 0 ]; then
    i=0; while read -r a b rest; do have[${ex[$i]}]="$a $b"; i=$((i+1)); done < <(for e in "${ex[@]}"; do printf '%s\n' "${plan_dst[$e]}"; done | tr '\n' '\0' | xargs -0 cksum)
  fi
  for ((i=0; i<n; i++)); do
    src="${inst[$i]}"; dst="${plan_dst[$i]}"
    if [ "${have[$i]}" = "${want[$i]}" ]; then   # already current
      [ ! -e "$dst.new" ] || rm -f "$dst.new"; manifest_lines+=("${want[$i]} $dst"); continue
    fi
    a=""
    if [ -n "${have[$i]}" ]; then
      # git's autocrlf rewrites line endings on checkout (Windows): a copy that differs only in CRs is not an edit
      a="$(tr -d '\r' < "$dst" | cksum | awk '{print $1" "$2}')"
      if [ "$a" = "$(tr -d '\r' < "$src" | cksum | awk '{print $1" "$2}')" ]; then
        [ ! -e "$dst.new" ] || rm -f "$dst.new"; manifest_lines+=("${have[$i]} $dst"); continue
      fi
    fi
    if [ -n "${have[$i]}" ] && [ "$force" != 1 ]; then
      rec="$(recorded "$dst")"
      if [ -n "$rec" ] && [ "$rec" != "${have[$i]}" ] && [ "$rec" != "$a" ]; then   # edited by hand since the last install: keep it
        cat "$src" > "$dst.new"; customised+=("$dst"); manifest_lines+=("$rec $dst"); continue
      fi
    fi
    if [ -n "${have[$i]}" ]; then updated+=("$dst"); else created+=("$dst"); fi
    [ ! -e "$dst.new" ] || rm -f "$dst.new"; manifest_lines+=("${want[$i]} $dst"); ensure_dir "$dst"
    if [ "${src##*/}" = "${dst##*/}" ]; then queued+=("$dst|$src"); else cat "$src" > "$dst"; fi
  done
  if [ ${#queued[@]} -gt 0 ]; then   # one cp per destination directory
    for d in $(printf '%s\n' "${queued[@]}" | sed 's#/[^/|]*|.*##' | sort -u); do
      srcs=(); for e in "${queued[@]}"; do [ "${e%/*|*}" = "$d" ] && srcs+=("${e#*|}"); done
      cp "${srcs[@]}" "$d/"
    done
  fi
  plan_src=(); plan_dst=()
}
copy_owned() { # src dst
  if [ -f "$2" ]; then kept+=("$2"); return; fi
  ensure_dir "$2"; render "$1" "$2"; cat "$rendered" > "$2"; created+=("$2")
}

# --- tooling (always current) ---
for f in gate promote intake handover status next-version check-signoff cloud-setup ticket-id base-ref enforcement doctor connect ci-gate ci-resolve; do
  copy_tooling "$here/scripts/pipeline/$f.sh" "scripts/pipeline/$f.sh"
done
# the code host and the tracker: the one adapter for each platform chosen, installed under a fixed name
copy_tooling "$here/scripts/pipeline/adapters/host-$git_host.sh" scripts/pipeline/host.sh
copy_tooling "$here/scripts/pipeline/adapters/tracker-$tracker.sh" scripts/pipeline/tracker.sh
copy_tooling "$here/scripts/pipeline/lib/host-common.sh" scripts/pipeline/lib/host-common.sh
[ "$tracker" = connector ] || copy_tooling "$here/scripts/pipeline/lib/tracker-common.sh" scripts/pipeline/lib/tracker-common.sh
copy_tooling "$here/scripts/pipeline/tracker-schema.txt" "scripts/pipeline/tracker-schema.txt"
copy_tooling "$here/scripts/pipeline/hooks/allow-paths.sh" "scripts/pipeline/hooks/allow-paths.sh"
copy_tooling "$here/scripts/pipeline/hooks/guard-merge.sh" "scripts/pipeline/hooks/guard-merge.sh"
copy_tooling "$here/scripts/pipeline/hooks/allow-commands.sh" "scripts/pipeline/hooks/allow-commands.sh"
for f in "$here"/agents/*.md; do copy_tooling "$f" ".claude/agents/${f##*/}"; done
for f in TICKETS BRANCHING CLOUD; do copy_tooling "$here/template/docs/pipeline/$f.md" "docs/pipeline/$f.md"; done
for f in "$here"/template/docs/pipeline/_templates/*.md; do copy_tooling "$f" "docs/pipeline/_templates/${f##*/}"; done
planned=" ${plan_dst[*]} "
apply_tooling
# Retired tooling: a file an earlier install put in place that this version no longer ships (a removed persona or
# template, the adapter for a platform no longer chosen, the test suite older versions copied in). It is removed
# when it is still exactly as installed (line endings aside); a copy the owner edited is kept and reported.
if [ -f "$manifest" ]; then
  while read -r sum size path; do
    case "$path" in scripts/pipeline/*|.claude/agents/*|docs/pipeline/_templates/*|docs/pipeline/TICKETS.md|docs/pipeline/BRANCHING.md|docs/pipeline/CLOUD.md) ;;
      tests/pipeline/*) [ "$(cd "$here" && pwd -P)" != "$(pwd -P)" ] || continue;;   # the plugin's own suite stays put
      *) continue;; esac
    case "$planned" in *" $path "*) continue;; esac
    [ -f "$path" ] || continue
    if [ "$(sum_of "$path")" = "$sum $size" ] || [ "$(tr -d '\r' < "$path" | cksum | awk '{print $1" "$2}')" = "$sum $size" ]; then
      rm -f "$path" "$path.new"; removed+=("$path")
    else retired_kept+=("$path"); fi
  done < "$manifest"
  for d in tests/pipeline tests scripts/pipeline/lib; do rmdir "$d" 2>/dev/null || true; done
fi

# --- project-owned (created once) --- (src_ctx / src_chk were resolved during argument validation)
copy_owned "$src_ctx" docs/pipeline/CONTEXT.md
copy_owned "$src_chk" RELEASE_CHECKLIST.md
copy_owned "$here/template/scripts/pipeline/pipeline.env" scripts/pipeline/pipeline.env
ci_note=""
if [ "$deploy_envs" = yes ]; then
  for f in deploy rollback smoke; do copy_owned "$here/scripts/deploy/$f.sh" "scripts/deploy/$f.sh"; done
else
  # No deployable environments: don't create the deploy machinery — and never remove what an earlier
  # install created (it is project-owned; the owner decides). Report it as kept instead.
  for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml .gitlab/pipeline-deploy.yml; do
    if [ -f "$f" ]; then kept+=("$f"); fi
  done
fi
case "$git_host" in
  github)
    [ "$deploy_envs" = yes ] && copy_owned "$here/template/.github/workflows/deploy.yml" ".github/workflows/deploy.yml"
    copy_owned "$here/template/.github/workflows/pipeline-gate.yml" ".github/workflows/pipeline-gate.yml";;
  gitlab)
    copy_owned "$here/template/.gitlab/pipeline-gate.yml" ".gitlab/pipeline-gate.yml"
    [ "$deploy_envs" = yes ] && copy_owned "$here/template/.gitlab/pipeline-deploy.yml" ".gitlab/pipeline-deploy.yml"
    inc=("/.gitlab/pipeline-gate.yml"); [ -f .gitlab/pipeline-deploy.yml ] && inc+=("/.gitlab/pipeline-deploy.yml")
    if [ ! -f .gitlab-ci.yml ]; then
      { echo "# GitLab CI entry point. The ship pipeline's jobs live in the included files."; echo "include:"
        for i in "${inc[@]}"; do echo "  - local: '$i'"; done; } > .gitlab-ci.yml; created+=(.gitlab-ci.yml)
    else
      missing_inc=(); for i in "${inc[@]}"; do grep -qF "$i" .gitlab-ci.yml || missing_inc+=("$i"); done
      if [ ${#missing_inc[@]} -eq 0 ]; then kept+=(.gitlab-ci.yml)
      elif grep -qE '^include:' .gitlab-ci.yml; then
        # a second top-level include: key would be invalid YAML, so this one merge is left to /pipeline-init
        ci_note="add to the include: list in .gitlab-ci.yml:$(printf " - local: '%s'" "${missing_inc[@]}")"; kept+=(.gitlab-ci.yml)
      else
        { [ -z "$(tail -c1 .gitlab-ci.yml)" ] || echo; echo; echo "# ship-pipeline"; echo "include:"
          for i in "${missing_inc[@]}"; do echo "  - local: '$i'"; done; } >> .gitlab-ci.yml; updated+=(.gitlab-ci.yml)
      fi
    fi;;
  bitbucket)
    bsrc="$here/template/bitbucket-pipelines.yml"; [ "$deploy_envs" = yes ] || bsrc="$here/template/bitbucket-pipelines.gate-only.yml"
    if [ -f bitbucket-pipelines.yml ] && ! grep -q 'Pipeline Gate' bitbucket-pipelines.yml; then
      copy_owned "$bsrc" bitbucket-pipelines.ship.yml
      ci_note="bitbucket-pipelines.yml already exists: merge the steps from bitbucket-pipelines.ship.yml into it (Bitbucket reads one file only)"
    else copy_owned "$bsrc" bitbucket-pipelines.yml; fi;;
esac
copy_owned "$here/template/.claude/settings.json" .claude/settings.json
copy_owned "$here/template/docs/pipeline/README.md" docs/pipeline/README.md
if [ "$force" = 1 ] && [ "$deploy_envs" = yes ]; then
  for f in deploy rollback smoke; do copy_tooling "$here/scripts/deploy/$f.sh" "scripts/deploy/$f.sh"; done
fi

# fill placeholders in freshly created files only
# with no deployable environments the deploy keys are written present-but-empty (nothing points anywhere)
# URLs: the flags, else .invalid placeholders that never resolve (the doctor flags them)
[ -n "$dev_url" ] || dev_url="https://dev.$name.example.invalid"; [ -n "$qa_url" ] || qa_url="https://qa.$name.example.invalid"
[ -n "$stg_url" ] || stg_url="https://staging.$name.example.invalid"; [ -n "$prod_url" ] || prod_url="https://$name.example.invalid"
[ -n "$health" ] || health="/actuator/health"
if [ "$deploy_envs" = no ]; then dev_url=""; qa_url=""; stg_url=""; prod_url=""; health=""; fi
urlesc() { printf '%s' "$1" | sed 's/[&#]/\\&/g'; }
for f in scripts/pipeline/pipeline.env docs/pipeline/CONTEXT.md; do
  if printf '%s\n' "${created[@]}" | grep -qx "$f"; then
    sed -i.bak -e "s/__PROJECT_NAME__/$name/g" -e "s/__TEAM_KEY__/$key/g" \
      -e "s#__DEV_URL__#$(urlesc "$dev_url")#g" -e "s#__QA_URL__#$(urlesc "$qa_url")#g" \
      -e "s#__STAGING_URL__#$(urlesc "$stg_url")#g" -e "s#__PRODUCTION_URL__#$(urlesc "$prod_url")#g" \
      -e "s#__HEALTH_PATH__#$health#g" -e "s#__GIT_HOST__#$git_host#g" -e "s#__GIT_HOST_URL__#$(urlesc "$git_url")#g" \
      -e "s#__TRACKER__#$tracker#g" -e "s#__TRACKER_URL__#$(urlesc "$tracker_url")#g" -e "s#__TRACKER_CLOUD_ID__#$cloud_id#g" \
      -e "s#__DEPLOY_MODE__#$deploy_mode#g" -e "s#__START_LEVEL__#$start#g" "$f" && rm -f "$f.bak"
  fi
done
# record the declared capabilities in a freshly created pipeline.env (an existing one is project-owned)
if printf '%s\n' "${created[@]}" | grep -qx scripts/pipeline/pipeline.env; then
  e=scripts/pipeline/pipeline.env
  if [ "$deploy_envs" = no ]; then
    de_line='PIPELINE_HAS_DEPLOY_ENVS="no"  # this project has no deployable environments: the deploy wait, the staging dispatch and smoke are skipped, and the deploy keys below are intentionally empty'
    sed -i.bak -e 's|^DEPLOY_WORKFLOW=.*|DEPLOY_WORKFLOW=""|' "$e" && rm -f "$e.bak"
  else
    de_line='PIPELINE_HAS_DEPLOY_ENVS="yes" # yes | no - no skips the deploy wait, the staging dispatch and smoke'
  fi
  awk -v de="$de_line" '
    /^PIPELINE_HAS_DEPLOY_ENVS=/ { print de; next }
    { print }' "$e" > "$e.new" && mv "$e.new" "$e"
fi
apply_tooling   # the --force-tooling deploy scripts above
chmod +x scripts/pipeline/*.sh scripts/pipeline/hooks/*.sh scripts/deploy/*.sh 2>/dev/null || true
# gitignore: each entry once, under one "# ship-pipeline" comment; nothing else from the data file
gi_changed=0; gi_existed=0; [ -f .gitignore ] && gi_existed=1
if [ -f .gitignore ] && grep -qx '# Append to .gitignore' .gitignore; then   # an older install copied its instruction line
  sed -i.bak 's/^# Append to \.gitignore$/# ship-pipeline/' .gitignore && rm -f .gitignore.bak; gi_changed=1
fi
gi_missing=()
while IFS= read -r e; do
  [ -f .gitignore ] && grep -qxF "$e" .gitignore || gi_missing+=("$e")
done < <(grep -vE '^[[:space:]]*(#|$)' "$here/template/.gitignore.pipeline")
if [ ${#gi_missing[@]} -gt 0 ]; then
  {
    if [ -s .gitignore ]; then [ -z "$(tail -c1 .gitignore)" ] || echo; fi
    if ! grep -qx '# ship-pipeline' .gitignore 2>/dev/null; then [ -s .gitignore ] && echo; echo '# ship-pipeline'; fi
    printf '%s\n' "${gi_missing[@]}"
  } >> .gitignore
  gi_changed=1
fi
if [ "$gi_changed" = 1 ]; then if [ "$gi_existed" = 1 ]; then updated+=(.gitignore); else created+=(.gitignore); fi; fi
# an older install left its .gitignore instructions behind as a file; remove it only when it is exactly that file
if [ -f .gitignore.pipeline ] && printf '# Append to .gitignore\n.claude/.pipeline-ticket\n.claude/settings.local.json\n' | cmp -s - .gitignore.pipeline; then
  rm -f .gitignore.pipeline; removed+=(.gitignore.pipeline)
fi

printf '%s\n' "${manifest_lines[@]}" | sort -k3 > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"

# --- branches on the remote (only with --create-branches; never moves or forces an existing branch) ---
branch_note=""
if [ "$mkbranches" = 1 ]; then
  r="$(declared_value scripts/pipeline/pipeline.env PIPELINE_REMOTE)"; r="${r:-origin}"
  if ! git remote get-url "$r" >/dev/null 2>&1; then branch_note="no remote named '$r', so no branch was created"
  else
    if ! git ls-remote --exit-code --heads "$r" "$base" >/dev/null 2>&1; then
      if git rev-parse -q --verify "refs/heads/$base" >/dev/null; then
        git push -q "$r" "refs/heads/$base:refs/heads/$base" && branch_note="pushed $base to $r" || branch_note="could not push $base to $r"
      else branch_note="there is no local $base to push"; fi
    fi
    if git ls-remote --exit-code --heads "$r" "$base" >/dev/null 2>&1 && ! git ls-remote --exit-code --heads "$r" "$stg" >/dev/null 2>&1; then
      git fetch -q "$r" "$base" 2>/dev/null || true
      bsha="$(git ls-remote --heads "$r" "$base" | awk '{print $1}')"
      git push -q "$r" "$bsha:refs/heads/$stg" && branch_note="${branch_note:+$branch_note; }created $stg on $r from $base" \
        || branch_note="${branch_note:+$branch_note; }could not create $stg on $r"
    fi
    [ -n "$branch_note" ] || branch_note="$base and $stg already exist on $r"
  fi
fi

printf 'init: %s (team key %s)\n' "$name" "$key"
printf '  branches: base=%s (from %s) staging=%s\n' "$base" "$base_from" "$stg"
printf '  capabilities: deploy-envs=%s\n' "$deploy_envs"
printf '  host: %s%s  tracker: %s  deploy-mode: %s  start-at: %s\n' "$git_host" "${git_url:+ ($git_url)}" "$tracker" "$deploy_mode" "$start"
[ -n "$branch_note" ] && printf '  branches on the remote: %s\n' "$branch_note"
[ -n "$ci_note" ] && printf '  ACTION: %s\n' "$ci_note"
[ -n "$env_note" ] && printf '  ACTION: %s\n' "$env_note"
[ ${#created[@]} -gt 0 ] && printf '  created %s\n' "${created[@]}"
[ ${#updated[@]} -gt 0 ] && printf '  updated %s\n' "${updated[@]}"
[ ${#kept[@]} -gt 0 ] && printf '  kept    %s\n' "${kept[@]}"
[ ${#removed[@]} -gt 0 ] && printf '  removed %s (no longer part of the pipeline)\n' "${removed[@]}"
[ ${#retired_kept[@]} -gt 0 ] && printf '  kept    %s (no longer part of the pipeline, but edited by hand: delete it when you are done with it)\n' "${retired_kept[@]}"
if [ ${#customised[@]} -gt 0 ]; then
  for f in "${customised[@]}"; do printf '  customised, kept %s (new version beside it: %s.new)\n' "$f" "$f"; done
  echo 'These tooling files were edited by hand since the last install. Merge each <file>.new by hand, or re-run with --force-tooling to take the new versions. Keep project-specific rules in docs/pipeline/CONTEXT.md so the tooling can stay stock.'
fi
if printf '%s\n' "${kept[@]}" | grep -qx scripts/pipeline/pipeline.env && ! grep -qE '^[[:space:]]*(export[[:space:]]+)?PIPELINE_REMOTE=' scripts/pipeline/pipeline.env; then
  echo 'This install predates v1.1.0. Its pipeline.env and workflows are yours and were not changed: run /pipeline-doctor and act on each [upgrade] finding (/pipeline-init shows every change as a diff first).'
fi
if [ "$had_manifest" = 0 ] && [ ${#updated[@]} -gt 0 ] && [ -f scripts/pipeline/gate.sh ] && ! printf '%s\n' "${created[@]}" | grep -qx scripts/pipeline/gate.sh; then
  echo 'No install record existed, so every tooling file was refreshed. If you had edited any of them, git diff shows what changed. From now on hand edits are detected and kept.'
fi
if [ "$deploy_envs" = no ] && [ "$declared_deploy_envs" != no ] && printf '%s\n' "${kept[@]}" | grep -qx scripts/pipeline/pipeline.env; then
  echo 'This project declared no deployable environments. Existing deploy files were left untouched — set PIPELINE_HAS_DEPLOY_ENVS="no" in scripts/pipeline/pipeline.env yourself, and delete scripts/deploy/* and .github/workflows/deploy.yml if you no longer want them.'
fi
cat <<MSG
Next (/pipeline-init runs these for you, after asking everything up front):
  1. bash scripts/pipeline/connect.sh install     the $git_host and $tracker CLIs (and jq)
     bash scripts/pipeline/connect.sh login       sign in, once, in your own terminal
  2. bash scripts/pipeline/tracker.sh setup       the tracker's labels, fields and statuses (tracker-schema.txt)
  3. Fill in docs/pipeline/CONTEXT.md and RELEASE_CHECKLIST.md
  4. bash scripts/pipeline/doctor.sh              seconds; install is done when it reports no FAIL
  5. Commit, then run: /ship <TICKET>
MSG
