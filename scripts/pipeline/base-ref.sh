#!/usr/bin/env bash
# The project's trunk, for agents, workflows and scripts. Never assumes a branch name.
# Usage: base-ref.sh             <remote>/<base branch>, e.g. origin/main (what `git diff X...HEAD` wants)
#        base-ref.sh --branch    <base branch>, e.g. main
#        base-ref.sh --staging   <staging branch>, e.g. staging
#        base-ref.sh --remote    <remote>, e.g. origin
#        base-ref.sh --value KEY the literal value of KEY in pipeline.env, read as data (one of the keys below)
# Values come from scripts/pipeline/pipeline.env (BASE_BRANCH, STAGING_BRANCH, PIPELINE_REMOTE). With no
# BASE_BRANCH there, the remote's default branch (<remote>/HEAD) is used, then a local main or master.
# With PIPELINE_ENV_AS_DATA=1 (set by the install route, scripts/pipeline/install-merge.sh) pipeline.env is never run:
# only the keys below are read from it, as literal values, with scripts/init.sh's rules (the last line naming the key
# decides, and only a plain KEY=value there counts). The process environment's values of those keys are ignored.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data_keys=" GIT_HOST GIT_HOST_URL TRACKER BASE_BRANCH STAGING_BRANCH PIPELINE_REMOTE DEPLOY_MODE PIPELINE_HAS_DEPLOY_ENVS "
env_text=""
env_value() { # KEY -> its literal value when the last line naming it is a plain assignment; nothing otherwise
  local key="$1" l line="" v re="(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|\$)"
  while IFS= read -r l; do if [[ $l =~ $re ]]; then line="$l"; fi; done <<<"$env_text"
  [ -n "$line" ] || return 0
  v="${line#"${line%%[![:space:]]*}"}"
  case "$v" in export[[:space:]]*) v="${v#export}"; v="${v#"${v%%[![:space:]]*}"}";; esac
  v="${v%"${v##*[![:space:]]}"}"
  case "$v" in "$key="*) v="${v#"$key="}";; *) return 0;; esac
  case "$v" in '"'*'"') v="${v#\"}"; v="${v%\"}";; "'"*"'") v="${v#\'}"; v="${v%\'}";; esac
  case "$v" in *\"*|*\'*) return 0;; esac   # a quote left over is literal to bash: not a plain value
  printf '%s' "$v"
}
if [ "${PIPELINE_ENV_AS_DATA:-0}" = 1 ] || [ "${1:-}" = --value ]; then
  # comments removed as init.sh removes them: a # starts one at the start of a line or after whitespace
  [ -f "$here/pipeline.env" ] && env_text="$(tr -d '\r' < "$here/pipeline.env" | sed -E 's/(^|[[:space:]])#.*$/\1/')"
  if [ "${1:-}" = --value ]; then
    case "$data_keys" in *" ${2:-} "*) env_value "$2"; echo; exit 0;; esac
    echo "usage: base-ref.sh --value <$(echo $data_keys | tr ' ' '|')>" >&2; exit 1
  fi
  PIPELINE_REMOTE="$(env_value PIPELINE_REMOTE)"; BASE_BRANCH="$(env_value BASE_BRANCH)"; STAGING_BRANCH="$(env_value STAGING_BRANCH)"
else
  # shellcheck disable=SC1091
  [ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
fi
remote="${PIPELINE_REMOTE:-origin}"
base="${BASE_BRANCH:-}"
if [ -z "$base" ]; then
  base="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"; base="${base#"$remote/"}"
fi
if [ -z "$base" ]; then
  for c in main master; do git rev-parse -q --verify "refs/heads/$c" >/dev/null 2>&1 && { base="$c"; break; }; done
fi
[ -n "$base" ] || base=master
case "${1:-}" in
  --branch) echo "$base";;
  --staging) echo "${STAGING_BRANCH:-staging}";;
  --remote) echo "$remote";;
  "") echo "$remote/$base";;
  *) echo "usage: base-ref.sh [--branch|--staging|--remote|--value KEY]" >&2; exit 1;;
esac
