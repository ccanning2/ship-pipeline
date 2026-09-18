#!/usr/bin/env bash
# Minimal test harness + fixtures for pipeline tooling.
set -uo pipefail
REPO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# In an installed project there is no scripts/init.sh; build fixtures by copying the project's own tooling instead.
if [ ! -f "$REPO_SRC/scripts/init.sh" ]; then
  INIT_MODE=copy
else
  INIT_MODE=init
fi
# A bare `python3` on PATH can be a non-functional stub (Windows), so probe for a real one.
PY=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { PY="$c"; break; }; done

PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
assert_exit()     { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected exit $2, got $3. ${4:-}"; }
assert_contains() { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "output missing '$3': $2";; esac; }
assert_eq()       { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$2', got '$3'"; }
summary() { echo "  -- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }

g() { git -C "$R" "$@"; }
commit_all() { g add -A; g commit -qm "${1:-wip}"; }

# new_repo: temp git repo (branch master) scaffolded with scripts/init.sh; sets R
new_repo() {
  R="$(mktemp -d)"
  git -C "$R" init -q -b master
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  mkdir -p "$R/src"; echo "class App {}" > "$R/src/App.java"
  git -C "$R" add -A; git -C "$R" commit -qm init
  if [ "$INIT_MODE" = init ]; then
    bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name demo --team-key REP >/dev/null
  else
    mkdir -p "$R/scripts" "$R/docs/pipeline" "$R/.claude" "$R/tests"
    cp -r "$REPO_SRC/scripts/pipeline" "$R/scripts/"
    [ -d "$REPO_SRC/scripts/deploy" ] && cp -r "$REPO_SRC/scripts/deploy" "$R/scripts/"
    cp -r "$REPO_SRC/docs/pipeline/_templates" "$R/docs/pipeline/"
    cp -r "$REPO_SRC/.claude/agents" "$R/.claude/"; cp "$REPO_SRC/.claude/settings.json" "$R/.claude/"
  fi
  # Fixtures always start from the default (strict) shape, whatever the hosting project declares.
  set_capability PIPELINE_HAS_DEPLOY_ENVS '"yes"'; set_capability PIPELINE_HAS_MARKETING '"yes"'
  git -C "$R" add -A; git -C "$R" commit -qm "install pipeline"
}

# --- project capability fixtures (scripts/pipeline/pipeline.env) ---
# None of these commit. gate.sh reads pipeline.env from the working tree, so an uncommitted change
# takes effect without counting as a code change since the dev deploy (gate.sh no_code_change_since).
# Call them before ready_build when the fixture must carry the value into its commits.
env_file() { echo "$R/scripts/pipeline/pipeline.env"; }
drop_env_key() { local f; f="$(env_file)"; sed -i.bak -E "/^$1=/d" "$f" && rm -f "$f.bak"; }
# set_capability <KEY> <verbatim RHS>   e.g. set_capability PIPELINE_HAS_MARKETING '"no"'
set_capability() { drop_env_key "$1"; printf '%s=%s\n' "$1" "$2" >> "$(env_file)"; }
# as a Windows editor would write it: the value line ends with CR
set_capability_crlf() { drop_env_key "$1"; printf '%s="%s"\r\n' "$1" "$2" >> "$(env_file)"; }
unset_capability() { drop_env_key "$1"; }
# blank_deploy_keys: the shape init.sh writes for a project with no deployable environments
blank_deploy_keys() {
  local f k; f="$(env_file)"
  for k in DEPLOY_WORKFLOW HEALTH_PATH DEV_URL QA_URL STAGING_URL PRODUCTION_URL; do
    drop_env_key "$k"; printf '%s=""\n' "$k" >> "$f"
  done
}
# legacy_env: a pre-1.1.0 pipeline.env — the ten v1.0.0 keys and neither capability key (BR-5 / AC-12)
legacy_env() {
  cat > "$(env_file)" <<'LEGACY'
# Pipeline configuration for THIS project (sourced by pipeline scripts). No secrets here.
PROJECT_NAME="demo"
BASE_BRANCH="master"
STAGING_BRANCH="staging"
DEPLOY_WORKFLOW="deploy.yml"
DEV_URL="https://dev.demo.example"
QA_URL="https://qa.demo.example"
STAGING_URL="https://staging.demo.example"
PRODUCTION_URL="https://demo.example"
HEALTH_PATH="/actuator/health"
TRACKER="linear"
TRACKER_TEAM_KEY="REP"
PIPELINE_TICKET_REGEX="${PIPELINE_TICKET_REGEX:-[A-Z][A-Z0-9]+-[0-9]+}"
LEGACY
}
branch() { g checkout -qb "$1"; }
tdir() { echo "$R/docs/pipeline/$1"; }

# set_field <file> <Key> <value>  (replace or append "Key: value")
set_field() {
  if grep -qE "^$2:" "$1" 2>/dev/null; then sed -i -E "s|^$2:.*|$2: $3|" "$1"; else echo "$2: $3" >> "$1"; fi
}

# add_ticket <T> <ID> <kind> <found> <sev> <state> [title]   (no commit)
add_ticket() {
  printf '| %s | %s | %s | %s | %s | x | %s |\n' "$2" "$3" "$4" "$5" "$6" "${7:-t}" >> "$(tdir "$1")/tickets.md"
}
# set_ticket <T> <ID> <state>   (no commit)
set_ticket() { sed -i -E "s/^(\| $2 \|([^|]*\|){3}) *[a-z-]+ *\|/\1 $3 |/" "$(tdir "$1")/tickets.md"; }
tickets_header() {
  printf '| Ticket | Kind | Found-in | Severity | State | Owner | Title |\n|---|---|---|---|---|---|---|\n' > "$(tdir "$1")/tickets.md"
}

# ready_build <T> <type> <uf> [research_status] [req_status] [product_status]
ready_build() {
  local d n; d="$(tdir "$1")"; mkdir -p "$d"; n="${1#*-}"
  printf '# brief\nsomething\n' > "$d/brief.md"
  printf 'Status: %s\nType: %s\nUser-facing: %s\n' "${6:-approved}" "$2" "$3" > "$d/product.md"
  printf 'Status: %s\n' "${4:-complete}" > "$d/research.md"
  printf 'Status: %s\n' "${5:-approved}" > "$d/requirements.md"
  cp "$R/docs/pipeline/_templates/releases.md" "$d/releases.md"; sed -i '/^Version:/d' "$d/releases.md"
  tickets_header "$1"; add_ticket "$1" "REP-${n}01" eng - - open "eng work"
  commit_all "requirements $1"
}
# built <T> [impl_status]: code change, eng tickets done, impl notes
built() {
  echo "class Feature$RANDOM {}" > "$R/src/Feature$RANDOM.java"
  sed -i -E 's/^(\| [A-Z]+-[0-9]+ \| eng \|([^|]*\|){2}) *[a-z-]+ *\|/\1 done |/' "$(tdir "$1")/tickets.md"
  printf 'Status: %s\n' "${2:-ready-for-dev}" > "$(tdir "$1")/impl-notes.md"
  commit_all "build $1"
}
# record <T> <Label> <sha>
record() { set_field "$(tdir "$1")/releases.md" "$2" "$3 2026-09-17T00:00:00Z"; commit_all "record $2"; }
dev_check() { printf 'Result: %s\nEnvironment: %s\nCommit: %s\n' "$2" "${4:-dev}" "$3" > "$(tdir "$1")/dev-check.md"; commit_all "devcheck $1"; }
qa_report() { printf 'Result: %s\nEnvironment: %s\nCommit: %s\n' "$2" "${4:-qa}" "$3" > "$(tdir "$1")/qa-report.md"; commit_all "qa $1"; }
signoff()   { printf 'Decision: %s\nEnvironment: %s\nCommit: %s\n' "$2" "${4:-staging}" "$3" > "$(tdir "$1")/signoff.md"; commit_all "signoff $1"; }
marketing() { printf 'Status: %s\n' "$2" > "$(tdir "$1")/marketing.md"; commit_all "mkt $1"; }
golive()    { set_field "$(tdir "$1")/releases.md" Go-live "${2:-approved by owner 2026-09-17T00:00:00Z}"; set_field "$(tdir "$1")/releases.md" Version "${3:-v1.0.0}"; commit_all "golive $1"; }

# full_through <T> <type> <uf> <stage>: make the ticket ready for <stage>'s gate
full_through() {
  local t="$1" type="$2" uf="$3" stage="$4" sha n="${1#*-}"
  ready_build "$t" "$type" "$uf"; [ "$stage" = build ] && return
  built "$t"; [ "$stage" = dev ] && return
  sha="$(g rev-parse HEAD)"; record "$t" Dev "$sha"; dev_check "$t" pass "$sha"
  git -C "$R" merge-base --is-ancestor "$sha" master 2>/dev/null || git -C "$R" update-ref refs/heads/master "$sha"   # promote dev = merged to master
  [ "$stage" = qa ] && return
  record "$t" QA "$sha"; qa_report "$t" pass "$sha"; [ "$stage" = staging ] && return
  record "$t" Staging "$sha"; signoff "$t" approved "$sha"; marketing "$t" ready
  add_ticket "$t" "REP-${n}90" marketing - - done "launch"; commit_all mkt-ticket
  golive "$t"; [ "$stage" = production ] && return
  record "$t" Production "$sha v1.0.0"
}
dev_sha_of() { sed -n 's/^Dev: \([0-9a-f]*\).*/\1/p' "$(tdir "$1")/releases.md"; }
qa_sha_of() { sed -n 's/^QA: \([0-9a-f]*\).*/\1/p' "$(tdir "$1")/releases.md"; }
gate() { (cd "$R" && bash scripts/pipeline/gate.sh "$@" 2>&1); }
