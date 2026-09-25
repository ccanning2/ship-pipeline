#!/usr/bin/env bash
# Stage gate. Usage: gate.sh <TICKET> <build|dev|qa|staging|production> [REF]
#   build       requirements + eng tickets ready; engineer may start
#   dev         may merge to the base branch (deploys dev, builds the image <registry>:<sha>)
#   qa          dev self-check passed on the base-branch build; may push it to the staging branch (deploys qa)
#   staging     qa passed on that build; may dispatch it to the staging environment
#   production  staging approved, defects closed, go-live + version set; may tag vX.Y.Z (deploys production)
# REF omitted -> working tree + HEAD; REF given -> committed files at REF (branch, tag or sha).
# PIPELINE_DOCS_REF=<ref> reads the pipeline docs from that ref (CI uses <remote>/<BASE_BRANCH>, where promote.sh
#   syncs the records) while the code/sha checks use REF. Tags and the staging branch point at build shas that
#   predate the records, so CI must read docs from the base branch.
# Success prints "DEPLOY_SHA=<sha>" (and "VERSION=<tag>" for production) and exits 0.
# Project capabilities come from scripts/pipeline/pipeline.env only (never from the environment):
#   PIPELINE_HAS_DEPLOY_ENVS="no"  -> no gate condition changes (deploy/smoke live in promote.sh)
# Anything but an explicit "no" keeps the stricter default, so an install without the keys is unchanged.
set -euo pipefail

ticket="${1:-}"; stage="${2:-}"; ref="${3:-}"
usage() { echo "usage: gate.sh <TICKET> <build|dev|qa|staging|production> [REF]" >&2; exit 1; }
[ -n "$ticket" ] && [ -n "$stage" ] || usage
[ "$stage" = merge ] && stage=production
case "$stage" in build|dev|qa|staging|production) ;; *) usage;; esac
ticket="$(printf '%s' "$ticket" | tr '[:lower:]' '[:upper:]')"

root="${PIPELINE_ROOT:-$(git rev-parse --show-toplevel)}"
rel="docs/pipeline/$ticket"
fail() { echo "PIPELINE GATE [$ticket/$stage]: $*" >&2; exit 1; }
# Project capabilities are project-level settings, never per-run overrides: drop anything inherited
# from the environment so only pipeline.env can set them.
unset PIPELINE_HAS_DEPLOY_ENVS
# shellcheck disable=SC1091
[ -f "$root/scripts/pipeline/pipeline.env" ] && source "$root/scripts/pipeline/pipeline.env"
regex="$(bash "$root/scripts/pipeline/ticket-id.sh" --regex)"   # the one ticket-id definition
base_branch="$(bash "$root/scripts/pipeline/base-ref.sh" --branch)"; remote="$(bash "$root/scripts/pipeline/base-ref.sh" --remote)"
# Capability resolution — fail closed: off only for an explicit `no` (trimmed, lowercased, CR tolerated);
# absent, empty or any unrecognised value falls through to `yes` = today's stricter behaviour.
capability() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" in no) echo no;; *) echo yes;; esac; }
on_off() { case "$1" in no) echo off;; *) echo on;; esac; }
has_deploy_envs="$(capability "${PIPELINE_HAS_DEPLOY_ENVS:-}")"

docs_ref="${PIPELINE_DOCS_REF:-$ref}"
if [ -n "$ref" ]; then
  git -C "$root" rev-parse --verify -q "${ref}^{commit}" >/dev/null || fail "ref '$ref' not found"
  target="$ref"
else
  target="HEAD"
fi
if [ -n "$docs_ref" ]; then
  git -C "$root" rev-parse --verify -q "${docs_ref}^{commit}" >/dev/null || fail "docs ref '$docs_ref' not found"
  has_file()  { git -C "$root" cat-file -e "$docs_ref:$rel/$1" 2>/dev/null; }
  read_file() { git -C "$root" show "$docs_ref:$rel/$1" 2>/dev/null; }
  has_dir()   { git -C "$root" cat-file -e "$docs_ref:$rel" 2>/dev/null; }
else
  has_file()  { [ -f "$root/$rel/$1" ]; }
  read_file() { cat "$root/$rel/$1" 2>/dev/null; }
  has_dir()   { [ -d "$root/$rel" ]; }
fi
target_sha="$(git -C "$root" rev-parse "${target}^{commit}")"

field() { local line; line="$(read_file "$1" | grep -m1 -E "^$2:" || true)"; printf '%s' "${line#*:}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]'; }
first_word() { printf '%s' "$1" | awk '{print $1}'; }
require_file() { has_file "$1" || fail "missing $1"; }
expect() { [ "$(field "$1" "$2")" = "$3" ] || fail "$1 $2 is not '$3' (got '$(field "$1" "$2")')"; }
resolve_sha() {
  local label="$1" v="$2" full
  [[ "$v" =~ ^[0-9a-f]{7,40}$ ]] || fail "$label is not a valid sha (got '$v')"
  full="$(git -C "$root" rev-parse -q --verify "${v}^{commit}" 2>/dev/null)" || fail "$label commit $v not found"
  git -C "$root" merge-base --is-ancestor "$full" "$target_sha" || fail "$label commit $v is not an ancestor of $target"
  printf '%s' "$full"
}
no_code_change_since() {
  local changed; changed="$(git -C "$root" diff --name-only "$1" "$target_sha" -- . ':(exclude)docs/pipeline')"
  [ -z "$changed" ] || fail "code changed since $2 ($1). Merge to $base_branch again (dev) and restart from there. Changed: $(echo "$changed" | head -5 | tr '\n' ' ')"
}
base_ref() {
  if [ -n "${PIPELINE_BASE_REF:-}" ]; then echo "$PIPELINE_BASE_REF"; return; fi
  local b="$base_branch" c
  for c in "$remote/$b" "$b"; do git -C "$root" rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1 && { echo "$c"; return; }; done
}
require_on_base() { # the build must already have been merged to the base branch
  local b; b="$(base_ref)"; [ -n "$b" ] || fail "cannot find base branch"
  git -C "$root" merge-base --is-ancestor "$1" "$b" || fail "build $1 is not on $b (merge to $base_branch / promote to dev first)"
}
require_up_to_date() {
  local b; b="$(base_ref)"; [ -n "$b" ] || fail "cannot find base branch"
  git -C "$root" merge-base --is-ancestor "$b" "$target_sha" || fail "branch is not up to date with $b; merge $b into the branch (no rebase/force-push)"
}
ticket_rows() {
  read_file tickets.md | awk -F'|' -v re="^$regex\$" 'NF>=7 { id=$2; gsub(/^[ \t]+|[ \t]+$/,"",id); if (toupper(id) !~ re) next; out=toupper(id); for(i=3;i<=6;i++){v=$i; gsub(/^[ \t]+|[ \t]+$/,"",v); out=out "|" tolower(v)}; print out }'
}
rows_where() { ticket_rows | awk -F'|' "$1"; }
list_ids() { awk -F'|' '{printf "%s(%s) ", $1, $5}'; }
known_states='open|in-progress|fixed|verified|done|wontfix|reopened'; known_kinds='story|eng|defect|follow-up|marketing'   # marketing: rows from installs before 3.0.0
level() { case "$1" in build) echo 1;; dev) echo 2;; qa) echo 3;; staging) echo 4;; production) echo 5;; esac; }
L="$(level "$stage")"

# ---- build ----
has_dir || fail "no pipeline folder at $rel${ref:+ on $ref}"
require_file brief.md; require_file product.md; expect product.md Status approved
type="$(field product.md Type)"; case "$type" in feature|bugfix|security|chore) ;; *) fail "product.md Type must be feature|bugfix|security|chore (got '$type')";; esac
uf="$(field product.md User-facing)"; case "$uf" in yes|no) ;; *) fail "product.md User-facing must be yes|no (got '$uf')";; esac
require_file requirements.md; expect requirements.md Status approved
require_file tickets.md
bad="$(rows_where "\$2 !~ /^($known_kinds)\$/ || \$5 !~ /^($known_states)\$/" | list_ids)"; [ -z "$bad" ] || fail "tickets.md has rows with unknown kind/state: $bad"
[ -n "$(rows_where '$2=="eng"')" ] || fail "no eng tickets in tickets.md (business analyst must create them)"
deploy_sha="$target_sha"

# ---- dev (merge to the base branch) ----
if [ "$L" -ge 2 ]; then
  require_file impl-notes.md; expect impl-notes.md Status ready-for-dev
  x="$(rows_where '$2=="eng" && $5!="done" && $5!="wontfix"' | list_ids)"; [ -z "$x" ] || fail "eng tickets not done: $x"
  x="$(rows_where '$2=="defect" && ($5=="open" || $5=="in-progress" || $5=="reopened")' | list_ids)"; [ -z "$x" ] || fail "defect tickets still open: $x"
  [ "$L" -eq 2 ] && require_up_to_date   # merging: the branch must contain the base branch; later stages check the build is ON it instead
fi

# ---- qa (push to staging branch) ----
if [ "$L" -ge 3 ]; then
  require_file releases.md
  dev_sha="$(resolve_sha "releases.md Dev" "$(first_word "$(field releases.md Dev)")")"
  require_file dev-check.md; expect dev-check.md Result pass; expect dev-check.md Environment dev
  [ "$(resolve_sha "dev-check.md Commit" "$(field dev-check.md Commit)")" = "$dev_sha" ] || fail "dev-check.md checked a different sha than dev runs ($dev_sha)"
  no_code_change_since "$dev_sha" "dev deploy"
  require_on_base "$dev_sha"
  deploy_sha="$dev_sha"
fi

# ---- staging (dispatch to staging env) ----
if [ "$L" -ge 4 ]; then
  qa_sha="$(resolve_sha "releases.md QA" "$(first_word "$(field releases.md QA)")")"
  [ "$qa_sha" = "$dev_sha" ] || fail "QA runs $qa_sha, not the dev-checked build $dev_sha"
  require_file qa-report.md; expect qa-report.md Result pass; expect qa-report.md Environment qa
  [ "$(resolve_sha "qa-report.md Commit" "$(field qa-report.md Commit)")" = "$qa_sha" ] || fail "qa-report.md tested a different sha than QA runs ($qa_sha)"
  x="$(rows_where '$2=="defect" && ($3=="dev" || $3=="qa") && $5!="verified" && $5!="wontfix"' | list_ids)"; [ -z "$x" ] || fail "QA-found defects not verified: $x"
  deploy_sha="$qa_sha"
fi

# ---- production (tag) ----
version=""
if [ "$L" -ge 5 ]; then
  st_sha="$(resolve_sha "releases.md Staging" "$(first_word "$(field releases.md Staging)")")"
  [ "$st_sha" = "$qa_sha" ] || fail "staging runs $st_sha, not the QA-tested build $qa_sha"
  require_file signoff.md; expect signoff.md Decision approved; expect signoff.md Environment staging
  [ "$(resolve_sha "signoff.md Commit" "$(field signoff.md Commit)")" = "$st_sha" ] || fail "signoff.md approved a different sha than staging runs ($st_sha)"
  x="$(rows_where '$2=="defect" && $5!="verified" && $5!="wontfix"' | list_ids)"; [ -z "$x" ] || fail "defects not verified: $x"
  x="$(rows_where '$2=="defect" && $5=="wontfix" && $4=="high"' | list_ids)"; [ -z "$x" ] || fail "High-severity defects cannot be wontfix: $x"
  case "$(field releases.md Go-live)" in approved*) ;; *) fail "releases.md Go-live is not approved (the owner must give the go)";; esac
  version="$(first_word "$(field releases.md Version)")"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "releases.md Version must be vMAJOR.MINOR.PATCH (got '$version')"
  existing="$(git -C "$root" rev-parse -q --verify "refs/tags/$version^{commit}" 2>/dev/null || true)"
  if [ -n "$existing" ] && [ "$existing" != "$st_sha" ]; then fail "tag $version already exists on $existing, not on $st_sha; bump the version"; fi
  deploy_sha="$st_sha"
fi

echo "PIPELINE GATE [$ticket/$stage]: PASS (type=$type, user-facing=$uf, deploy-envs=$(on_off "$has_deploy_envs")${ref:+, ref=$ref})"
echo "DEPLOY_SHA=$deploy_sha"
[ -n "$version" ] && echo "VERSION=$version"
exit 0
