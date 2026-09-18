#!/usr/bin/env bash
# Scaffold (or update) the pipeline in a project. Idempotent; never overwrites project-owned files.
# Usage: init.sh [--project-dir DIR] [--name NAME] [--team-key KEY] [--profile NAME] [--force-tooling]
#               [--no-deploy-envs] [--no-marketing]
#   --no-deploy-envs  the project has no hosts/image/deploy workflow: no scripts/deploy/*, no deploy.yml,
#                     empty deploy keys, and PIPELINE_HAS_DEPLOY_ENVS="no" in a freshly created pipeline.env
#   --no-marketing    the project has no marketing function: PIPELINE_HAS_MARKETING="no"
#   Neither flag ever deletes anything from an existing install; both default to "yes" (today's behaviour).
#   Project-owned (created once, then yours): docs/pipeline/CONTEXT.md, RELEASE_CHECKLIST.md, scripts/pipeline/pipeline.env,
#     .github/workflows/*.yml, scripts/deploy/*, .claude/settings.json
#   Tooling (replaced on every run): scripts/pipeline/{gate,promote,intake,status,next-version,check-signoff,cloud-setup}.sh,
#     scripts/pipeline/hooks/*, .claude/agents/*, docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md, docs/pipeline/_templates/*, tests/pipeline/*
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(pwd)"; name=""; key=""; profile=""; force=0; deploy_envs=yes; marketing=yes
while [ $# -gt 0 ]; do case "$1" in
  --project-dir) dir="$2"; shift 2;; --name) name="$2"; shift 2;; --team-key) key="$2"; shift 2;;
  --profile) profile="$2"; shift 2;; --force-tooling) force=1; shift;;
  --no-deploy-envs) deploy_envs=no; shift;; --no-marketing) marketing=no; shift;;
  *) echo "unknown arg $1" >&2; exit 1;; esac; done
cd "$dir"; git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "init: $dir is not a git repository" >&2; exit 1; }
[ -n "$name" ] || name="$(basename "$(git rev-parse --show-toplevel)")"
[ -n "$key" ] || key="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z' | cut -c1-4)"
[ -n "$key" ] || key="PROJ"
created=(); updated=(); kept=()
copy_tooling() { # src dst
  mkdir -p "$(dirname "$2")"
  if [ -f "$2" ] && cmp -s "$1" "$2"; then return; fi
  [ -f "$2" ] && updated+=("$2") || created+=("$2"); cp "$1" "$2"
}
copy_owned() { # src dst [subst...]
  if [ -f "$2" ]; then kept+=("$2"); return; fi
  mkdir -p "$(dirname "$2")"; cp "$1" "$2"; created+=("$2")
}

# --- tooling (always current) ---
for f in gate promote intake status next-version check-signoff cloud-setup; do copy_tooling "$here/scripts/pipeline/$f.sh" "scripts/pipeline/$f.sh"; done
copy_tooling "$here/scripts/pipeline/hooks/allow-paths.sh" "scripts/pipeline/hooks/allow-paths.sh"
copy_tooling "$here/scripts/pipeline/hooks/guard-merge.sh" "scripts/pipeline/hooks/guard-merge.sh"
for f in "$here"/agents/*.md; do copy_tooling "$f" ".claude/agents/$(basename "$f")"; done
for f in TICKETS BRANCHING CLOUD; do copy_tooling "$here/template/docs/pipeline/$f.md" "docs/pipeline/$f.md"; done
for f in "$here"/template/docs/pipeline/_templates/*.md; do copy_tooling "$f" "docs/pipeline/_templates/$(basename "$f")"; done
for f in "$here"/tests/pipeline/*.sh; do copy_tooling "$f" "tests/pipeline/$(basename "$f")"; done
copy_tooling "$here/template/.gitignore.pipeline" ".gitignore.pipeline"

# --- project-owned (created once) ---
src_ctx="$here/template/docs/pipeline/CONTEXT.md"; src_chk="$here/template/RELEASE_CHECKLIST.md"
if [ -n "$profile" ]; then
  [ -d "$here/profiles/$profile" ] || { echo "init: unknown profile '$profile' (see $here/profiles)" >&2; exit 1; }
  src_ctx="$here/profiles/$profile/CONTEXT.md"; src_chk="$here/profiles/$profile/RELEASE_CHECKLIST.md"
fi
copy_owned "$src_ctx" docs/pipeline/CONTEXT.md
copy_owned "$src_chk" RELEASE_CHECKLIST.md
copy_owned "$here/template/scripts/pipeline/pipeline.env" scripts/pipeline/pipeline.env
if [ "$deploy_envs" = yes ]; then
  for f in deploy rollback smoke; do copy_owned "$here/scripts/deploy/$f.sh" "scripts/deploy/$f.sh"; done
  copy_owned "$here/template/.github/workflows/deploy.yml" ".github/workflows/deploy.yml"
else
  # No deployable environments: don't create the deploy machinery — and never remove what an earlier
  # install created (it is project-owned; the owner decides). Report it as kept instead.
  for f in scripts/deploy/deploy.sh scripts/deploy/rollback.sh scripts/deploy/smoke.sh .github/workflows/deploy.yml; do
    if [ -f "$f" ]; then kept+=("$f"); fi
  done
fi
copy_owned "$here/template/.github/workflows/pipeline-gate.yml" ".github/workflows/pipeline-gate.yml"
copy_owned "$here/template/.claude/settings.json" .claude/settings.json
copy_owned "$here/template/docs/pipeline/README.md" docs/pipeline/README.md
if [ "$force" = 1 ] && [ "$deploy_envs" = yes ]; then
  for f in deploy rollback smoke; do copy_tooling "$here/scripts/deploy/$f.sh" "scripts/deploy/$f.sh"; done
fi

# fill placeholders in freshly created files only
# with no deployable environments the deploy keys are written present-but-empty (nothing points anywhere)
dev_url="https://dev.$name.example"; qa_url="https://qa.$name.example"
stg_url="https://staging.$name.example"; prod_url="https://$name.example"; health="/actuator/health"
if [ "$deploy_envs" = no ]; then dev_url=""; qa_url=""; stg_url=""; prod_url=""; health=""; fi
for f in scripts/pipeline/pipeline.env docs/pipeline/CONTEXT.md; do
  if printf '%s\n' "${created[@]}" | grep -qx "$f"; then
    sed -i.bak -e "s/__PROJECT_NAME__/$name/g" -e "s/__TEAM_KEY__/$key/g" \
      -e "s#__DEV_URL__#$dev_url#g" -e "s#__QA_URL__#$qa_url#g" \
      -e "s#__STAGING_URL__#$stg_url#g" -e "s#__PRODUCTION_URL__#$prod_url#g" \
      -e "s#__HEALTH_PATH__#$health#g" "$f" && rm -f "$f.bak"
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
  if [ "$marketing" = no ]; then
    mk_line='PIPELINE_HAS_MARKETING="no"    # this project has no marketing function: the marketing persona and the production marketing gate are skipped'
  else
    mk_line='PIPELINE_HAS_MARKETING="yes"   # yes | no - no skips the marketing persona and the production marketing gate'
  fi
  awk -v de="$de_line" -v mk="$mk_line" '
    /^PIPELINE_HAS_DEPLOY_ENVS=/ { print de; next }
    /^PIPELINE_HAS_MARKETING=/   { print mk; next }
    { print }' "$e" > "$e.new" && mv "$e.new" "$e"
fi
chmod +x scripts/pipeline/*.sh scripts/pipeline/hooks/*.sh scripts/deploy/*.sh tests/pipeline/*.sh 2>/dev/null || true
# gitignore
if [ -f .gitignore ] && grep -q '.claude/.pipeline-ticket' .gitignore; then :; else { echo; cat .gitignore.pipeline; } >> .gitignore; updated+=(.gitignore); fi

printf 'init: %s (team key %s)\n' "$name" "$key"
printf '  capabilities: deploy-envs=%s marketing=%s\n' "$deploy_envs" "$marketing"
[ ${#created[@]} -gt 0 ] && printf '  created %s\n' "${created[@]}"
[ ${#updated[@]} -gt 0 ] && printf '  updated %s\n' "${updated[@]}"
[ ${#kept[@]} -gt 0 ] && printf '  kept    %s\n' "${kept[@]}"
if [ "$deploy_envs" = no ] && printf '%s\n' "${kept[@]}" | grep -qx scripts/pipeline/pipeline.env; then
  echo 'This project declared no deployable environments. Existing deploy files were left untouched — set PIPELINE_HAS_DEPLOY_ENVS="no" in scripts/pipeline/pipeline.env yourself, and delete scripts/deploy/* and .github/workflows/deploy.yml if you no longer want them.'
fi
if [ "$marketing" = no ] && printf '%s\n' "${kept[@]}" | grep -qx scripts/pipeline/pipeline.env; then
  echo 'This project declared no marketing function. Set PIPELINE_HAS_MARKETING="no" in scripts/pipeline/pipeline.env yourself — an existing pipeline.env is yours and is never rewritten.'
fi
cat <<MSG
Next:
  1. Fill in docs/pipeline/CONTEXT.md (product, stack, test commands, rules, high-risk areas) and RELEASE_CHECKLIST.md.
  2. Set the URLs and TRACKER_TEAM_KEY in scripts/pipeline/pipeline.env, and check PIPELINE_HAS_DEPLOY_ENVS / PIPELINE_HAS_MARKETING describe this project.
  3. Create branches master + staging, GitHub environments dev/qa/staging/production, and the Linear label groups (docs/pipeline/TICKETS.md).
  4. Commit, then run: /ship <TICKET>
MSG
