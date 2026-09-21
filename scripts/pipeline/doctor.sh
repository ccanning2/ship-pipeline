#!/usr/bin/env bash
# Is this repository ready for /ship? Read-only: it changes no file, ref or setting.
# Usage: doctor.sh [--offline] [--with-tests]
#   --offline     skip everything that talks to the network (the remote, gh)
#   --with-tests  also run tests/pipeline/run-all.sh (slow)
# Prints one line per check: PASS | WARN | FAIL | TODO (a check only the tracker connector can do).
# Exits 1 when any check FAILs, else 0. PIPELINE_GH_CMD replaces gh (tests).
set -uo pipefail
offline=0; with_tests=0
while [ $# -gt 0 ]; do case "$1" in
  --offline) offline=1; shift;; --with-tests) with_tests=1; shift;;
  *) echo "usage: doctor.sh [--offline] [--with-tests]" >&2; exit 1;; esac; done
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "FAIL  git: not inside a git repository"; exit 1; }
cd "$root"
P=scripts/pipeline
npass=0; nwarn=0; nfail=0
pass() { npass=$((npass+1)); printf 'PASS  %s\n' "$*"; }
warn() { nwarn=$((nwarn+1)); printf 'WARN  %s\n' "$*"; }
fail() { nfail=$((nfail+1)); printf 'FAIL  %s\n' "$*"; }
todo() { printf 'TODO  %s\n' "$*"; }
# a finding that means "installed before v1.1.0": the fix is a change to a project-owned file, which /pipeline-init
# shows as a diff against the current template and applies only with the owner's yes
upg=" [upgrade: run /pipeline-init to review the change]"

# ---- files ----
missing=""
for f in $P/pipeline.env $P/gate.sh $P/promote.sh $P/intake.sh $P/status.sh $P/next-version.sh $P/ticket-id.sh $P/base-ref.sh \
         $P/enforcement.sh $P/tracker-schema.txt $P/hooks/guard-merge.sh $P/hooks/allow-paths.sh \
         docs/pipeline/CONTEXT.md docs/pipeline/TICKETS.md docs/pipeline/BRANCHING.md RELEASE_CHECKLIST.md \
         .github/workflows/pipeline-gate.yml .claude/settings.json tests/pipeline/run-all.sh; do
  [ -f "$f" ] || missing="$missing $f"
done
[ -z "$missing" ] && pass "files: the pipeline is installed" || fail "files: missing$missing (run /pipeline-init)"
notx=""; for f in $P/*.sh $P/hooks/*.sh tests/pipeline/*.sh scripts/deploy/*.sh; do [ -f "$f" ] && [ ! -x "$f" ] && notx="$notx $f"; done
[ -z "$notx" ] && pass "files: scripts are executable" || fail "files: not executable:$notx (chmod +x them)"
if [ -f $P/.install-manifest ]; then
  custom=""
  while read -r sum size path; do
    [ -f "$path" ] || continue
    [ "$(cksum < "$path" | awk '{print $1" "$2}')" = "$sum $size" ] || custom="$custom $path"
  done < $P/.install-manifest
  [ -z "$custom" ] && pass "files: no installed tooling file was edited by hand" \
    || warn "files: edited by hand since install:$custom. /pipeline-init keeps these and writes the new version beside them as <file>.new; move project-specific rules into docs/pipeline/CONTEXT.md instead"
fi
[ -f .gitignore.pipeline ] && warn "files: .gitignore.pipeline is an installer leftover; delete it (its entries belong in .gitignore)"
grep -qx '# Append to .gitignore' .gitignore 2>/dev/null && warn "files: .gitignore contains the installer's instruction line '# Append to .gitignore'; replace it with '# ship-pipeline'"

# ---- pipeline.env ----
# shellcheck disable=SC1091
[ -f $P/pipeline.env ] && source $P/pipeline.env
remote="${PIPELINE_REMOTE:-origin}"
base="$(bash $P/base-ref.sh --branch 2>/dev/null || echo master)"; stg="$(bash $P/base-ref.sh --staging 2>/dev/null || echo staging)"
grep -q '__[A-Z_]*__' $P/pipeline.env 2>/dev/null && warn "pipeline.env: unfilled placeholders: $(grep -o '__[A-Z_]*__' $P/pipeline.env | sort -u | tr '\n' ' ')"
[ -n "${BASE_BRANCH:-}" ] && pass "pipeline.env: BASE_BRANCH=$base, STAGING_BRANCH=$stg, PIPELINE_REMOTE=$remote" \
  || warn "pipeline.env: BASE_BRANCH is not set; using '$base' from $remote/HEAD. Set it explicitly"
[ -n "${PIPELINE_REMOTE:-}" ] || warn "pipeline.env: PIPELINE_REMOTE is not set; using 'origin'. Add PIPELINE_REMOTE=\"origin\" (or the code host's remote name)$upg"
key="${TRACKER_TEAM_KEY:-}"
case "$key" in ""|__*) fail "pipeline.env: TRACKER_TEAM_KEY is not set (the tracker team key, e.g. ABC for ABC-12)";; *) pass "pipeline.env: TRACKER_TEAM_KEY=$key";; esac
regex="$(bash $P/ticket-id.sh --regex 2>/dev/null)"
leaky=""; for s in macos-14 utf-8 v1.45.0-jammy ubuntu-22 node-20; do bash $P/ticket-id.sh "$s" >/dev/null 2>&1 && leaky="$leaky $s"; done
if [ -n "$leaky" ]; then
  warn "pipeline.env: PIPELINE_TICKET_REGEX '$regex' also matches$leaky, so the hook and the PR gate can mistake them for tickets. Set PIPELINE_TICKET_REGEX=\"\${TRACKER_TEAM_KEY:-}-[0-9]+\"$upg"
else pass "pipeline.env: ticket ids match '$regex' only"; fi
case "$key" in ""|__*) ;; *) bash $P/ticket-id.sh "$key-12" >/dev/null 2>&1 || fail "pipeline.env: PIPELINE_TICKET_REGEX '$regex' does not match $key-12";; esac
for k in PIPELINE_HAS_DEPLOY_ENVS PIPELINE_HAS_MARKETING; do
  v="$(printf '%s' "${!k:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$v" in yes|no) ;; "") warn "pipeline.env: $k is not set (resolves to yes); state it explicitly";; *) warn "pipeline.env: $k='${!k}' is not yes or no (resolves to yes)";; esac
done

# ---- git ----
if url="$(git remote get-url "$remote" 2>/dev/null)"; then
  case "$url" in *github.com[:/]*) pass "git: $remote is $url";;
    *) warn "git: $remote is $url, which is not GitHub. The workflows, PR merges and gh calls assume GitHub and GitHub Actions; migrate first";; esac
  others="$(git remote | grep -vx "$remote" | tr '\n' ' ')"; [ -n "$others" ] && pass "git: other remotes ($others) are ignored; the pipeline uses $remote only"
  if [ "$offline" = 1 ]; then
    rb="$(git rev-parse -q --verify "refs/remotes/$remote/$base" 2>/dev/null || true)"
    rs="$(git rev-parse -q --verify "refs/remotes/$remote/$stg" 2>/dev/null || true)"
  else
    rb="$(git ls-remote --heads "$remote" "refs/heads/$base" 2>/dev/null | awk '{print $1}')"
    rs="$(git ls-remote --heads "$remote" "refs/heads/$stg" 2>/dev/null | awk '{print $1}')"
  fi
  if [ -z "$rb" ]; then
    fail "git: $remote has no branch '$base'. Push the base branch first (the owner runs it; the hook gates agent pushes to it)"
  elif ! git cat-file -e "$rb^{commit}" 2>/dev/null; then
    warn "git: $remote/$base ($rb) is not fetched; run 'git fetch $remote' and re-run the doctor to check history"
  elif ! git merge-base HEAD "$rb" >/dev/null 2>&1; then
    fail "git: local history and $remote/$base share no commit (typically a host-created README-only first commit). Nothing can merge until this is resolved; the owner decides between force-pushing local history and merging with --allow-unrelated-histories"
  else
    pass "git: $remote/$base shares history with the local repository"
  fi
  if [ -z "$rs" ]; then
    warn "git: $remote has no branch '$stg'. The owner creates it from the base branch: git push $remote $base:refs/heads/$stg"
  elif [ -n "$rb" ] && git cat-file -e "$rs^{commit}" 2>/dev/null && git cat-file -e "$rb^{commit}" 2>/dev/null; then
    git merge-base --is-ancestor "$rs" "$rb" && pass "git: $stg is on $base" \
      || warn "git: $remote/$stg ($rs) is not a $base commit; the staging branch should always equal some $base sha"
  fi
else
  fail "git: no remote named '$remote'. Add the code host as '$remote', or set PIPELINE_REMOTE in pipeline.env"
fi

# ---- host ----
if [ "$offline" = 1 ]; then warn "host: skipped (--offline)"
else
  gh_cmd="${PIPELINE_GH_CMD:-gh}"
  if ! command -v "${gh_cmd%% *}" >/dev/null 2>&1; then warn "host: gh is not installed; promote.sh and cloud sessions need it"
  elif ! $gh_cmd auth status >/dev/null 2>&1; then warn "host: gh is not signed in (gh auth login)"
  else pass "host: gh is signed in"; fi
  enf="$(bash $P/enforcement.sh 2>/dev/null)"; mode="$(printf '%s\n' "$enf" | sed -n 's/^ENFORCEMENT=//p')"; line="$(printf '%s\n' "$enf" | sed -n '2p')"
  case "$mode" in host) pass "host: $line";; *) warn "host: $line";; esac
fi

# ---- hooks and workflows ----
grep -q 'guard-merge.sh' .claude/settings.json 2>/dev/null && pass "hooks: guard-merge.sh is wired in .claude/settings.json" \
  || fail "hooks: guard-merge.sh is not wired in .claude/settings.json, so nothing gates agent merges and pushes"
wf=.github/workflows/pipeline-gate.yml
if [ -f $wf ]; then
  br="$(sed -n 's/^[[:space:]]*branches:[[:space:]]*\[\(.*\)\].*/\1/p' $wf | head -1 | tr -d ' "'"'")"
  case ",$br," in *",$base,"*) case ",$br," in *",$stg,"*) br=ok;; esac;; esac
  [ "$br" = ok ] && pass "workflows: pipeline-gate.yml gates PRs into $base and $stg" \
    || fail "workflows: pipeline-gate.yml gates PRs into [$br], not $base and $stg$upg"
  grep -q 'ticket-id.sh' $wf && grep -q "'infra'" $wf \
    && pass "workflows: pipeline-gate.yml reads the shared ticket id and honours the infra label" \
    || warn "workflows: pipeline-gate.yml predates v1.1.0: it carries its own broad ticket regex, has no route for infra PRs and reruns the self-test on every PR$upg"
fi
de="$(printf '%s' "${PIPELINE_HAS_DEPLOY_ENVS:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
if [ -f .github/workflows/deploy.yml ]; then
  if ! grep -q 'PIPELINE_DEPLOY_ENABLED' .github/workflows/deploy.yml; then
    [ "$de" = no ] && warn "workflows: deploy.yml runs on every push but this project has no deployable environments; delete it or gate it on vars.PIPELINE_DEPLOY_ENABLED$upg" \
      || warn "workflows: deploy.yml runs on every push and fails until the environments exist; gate it on vars.PIPELINE_DEPLOY_ENABLED$upg"
  else
    pass "workflows: deploy.yml runs only when the repository variable PIPELINE_DEPLOY_ENABLED is 'true'"
    if [ "$offline" = 0 ] && [ "$de" != no ]; then
      v="$(${PIPELINE_GH_CMD:-gh} variable get PIPELINE_DEPLOY_ENABLED 2>/dev/null || true)"
      [ "$v" = true ] && pass "workflows: deploys are enabled (PIPELINE_DEPLOY_ENABLED=true)" \
        || warn "workflows: deploys are off (repository variable PIPELINE_DEPLOY_ENABLED is not 'true'), so promote.sh would wait on skipped runs. Set it once the environments exist, or set PIPELINE_HAS_DEPLOY_ENVS=\"no\""
    fi
  fi
fi

# ---- stale branch names ----
if [ "$base" != master ]; then
  stale="$(grep -rlw 'master' .claude/agents docs/pipeline/TICKETS.md docs/pipeline/BRANCHING.md docs/pipeline/CLOUD.md \
           docs/pipeline/_templates .github/workflows $P 2>/dev/null | grep -vE '(\.install-manifest|/base-ref\.sh|/doctor\.sh)$' | tr '\n' ' ')"
  [ -z "$stale" ] && pass "branches: no 'master' left in the installed tooling (base branch is $base)" \
    || warn "branches: 'master' still appears in: $stale(the base branch is $base)$upg"
fi

# ---- tests ----
if [ "$with_tests" = 1 ]; then
  bash tests/pipeline/run-all.sh >/dev/null 2>&1 && pass "tests: tests/pipeline/run-all.sh passes" || fail "tests: tests/pipeline/run-all.sh fails; run it to see why"
fi

# ---- tracker (only the connector can see it) ----
todo "tracker: $(printf '%s' "${TRACKER:-linear}") team '$key' must exist and the connector must answer a read call"
if [ -f $P/tracker-schema.txt ]; then
  grep -vE '^[[:space:]]*(#|$)' $P/tracker-schema.txt | while IFS='|' read -r type name values note; do
    case "$type" in
      label-group) todo "tracker: label group '$name' (single-select) with labels: $values";;
      labels)      todo "tracker: labels ($name): $values";;
      status)      todo "tracker: workflow status '$values' (for pipeline state '$name')${note:+, $note}";;
    esac
  done
fi

echo "doctor: $npass passed, $nwarn warnings, $nfail failed"
[ "$nfail" -eq 0 ]
