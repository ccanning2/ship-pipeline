# Shared by every code-host adapter (sourced, never run). /pipeline-init installs ONE adapter as scripts/pipeline/host.sh:
#   adapters/host-github.sh (gh), adapters/host-gitlab.sh (glab) or adapters/host-bitbucket.sh (Bitbucket Cloud REST via curl).
# The adapter sets $host and $pfx, defines <pfx>_<verb> functions, then calls host_main "$@".
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
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # scripts/pipeline
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
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

# ---------------------------------------------------------------- dispatch (called by the adapter) ----
say() { echo "ENFORCEMENT=$1"; echo "$2"; exit 0; }
host_main() {
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
}
