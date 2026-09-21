#!/usr/bin/env bash
# Scaffold (or update) the pipeline in a project. Idempotent; never overwrites project-owned files.
# Usage: init.sh [--project-dir DIR] [--name NAME] [--team-key KEY] [--profile NAME] [--force-tooling]
#               [--base-branch NAME] [--staging-branch NAME] [--no-deploy-envs] [--no-marketing]
#   --base-branch     the trunk (merging here = dev). Default: BASE_BRANCH from an existing pipeline.env, else
#                     origin's default branch (origin/HEAD), else the current branch. Written into pipeline.env,
#                     the workflows and the docs; nothing assumes "master".
#   --staging-branch  default: STAGING_BRANCH from an existing pipeline.env, else "staging"
#   --force-tooling   also overwrite tooling files edited by hand since the last install (normally they are kept
#                     and the new version is written beside them as <file>.new), and refresh scripts/deploy/*
#   --no-deploy-envs  the project has no hosts/image/deploy workflow: no scripts/deploy/*, no deploy.yml,
#                     empty deploy keys, and PIPELINE_HAS_DEPLOY_ENVS="no" in a freshly created pipeline.env
#   --no-marketing    the project has no marketing function: PIPELINE_HAS_MARKETING="no"
#   Without --no-deploy-envs, an existing scripts/pipeline/pipeline.env is read (never written): a project
#   that already declares PIPELINE_HAS_DEPLOY_ENVS="no" is scaffolded as if the flag had been passed.
#   Neither flag ever deletes anything from an existing install; both default to "yes" (today's behaviour).
#   Project-owned (created once, then yours): docs/pipeline/CONTEXT.md, RELEASE_CHECKLIST.md, scripts/pipeline/pipeline.env,
#     .github/workflows/*.yml, scripts/deploy/*, .claude/settings.json
#   Tooling (refreshed on every run): scripts/pipeline/{gate,promote,intake,status,next-version,check-signoff,cloud-setup,
#     ticket-id,base-ref,enforcement,doctor}.sh, scripts/pipeline/tracker-schema.txt, scripts/pipeline/hooks/*, .claude/agents/*,
#     docs/pipeline/{TICKETS,BRANCHING,CLOUD}.md, docs/pipeline/_templates/*, tests/pipeline/*
#   scripts/pipeline/.install-manifest records a checksum of every tooling file as installed. A tooling file whose
#   content no longer matches its record was edited by hand: it is kept, and the new version goes to <file>.new.
#   .gitignore gains the pipeline's entries once, under "# ship-pipeline".
#   __BASE_BRANCH__ / __STAGING_BRANCH__ in any scaffolded file are replaced with the project's branch names.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(pwd)"; name=""; key=""; profile=""; force=0; deploy_envs=yes; marketing=yes; base=""; stg=""
while [ $# -gt 0 ]; do case "$1" in
  --project-dir) dir="$2"; shift 2;; --name) name="$2"; shift 2;; --team-key) key="$2"; shift 2;;
  --profile) profile="$2"; shift 2;; --force-tooling) force=1; shift;;
  --base-branch) base="${2:-}"; shift 2;; --staging-branch) stg="${2:-}"; shift 2;;
  --no-deploy-envs) deploy_envs=no; shift;; --no-marketing) marketing=no; shift;;
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
sed_esc() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }
base_esc="$(sed_esc "$base")"; stg_esc="$(sed_esc "$stg")"

declared_deploy_envs=""
if [ "$deploy_envs" = yes ]; then
  declared_deploy_envs="$(declared_capability scripts/pipeline/pipeline.env PIPELINE_HAS_DEPLOY_ENVS)"
  [ "$declared_deploy_envs" = no ] && deploy_envs=no || true
fi

created=(); updated=(); kept=(); customised=(); removed=()
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
render() { # src dst -> the file to install (echoes its path). Only docs, workflows, the checklist and pipeline.env
  # get the branch placeholders filled; scripts, tests and agents are copied verbatim (they may name a placeholder)
  case "$2" in
    docs/*|.github/*|RELEASE_CHECKLIST.md|scripts/pipeline/pipeline.env)
      sed -e "s:__BASE_BRANCH__:$base_esc:g" -e "s:__STAGING_BRANCH__:$stg_esc:g" "$1" > "$tmpd/r"; echo "$tmpd/r";;
    *) echo "$1";;
  esac
}
manifest=scripts/pipeline/.install-manifest; had_manifest=0; [ -f "$manifest" ] && had_manifest=1
manifest_lines=()
sum_of() { cksum < "$1" | awk '{print $1" "$2}'; }
recorded() { [ -f "$manifest" ] && awk -v p="$1" '$3==p {print $1" "$2}' "$manifest" || true; }
copy_tooling() { # src dst
  local r rec; r="$(render "$1" "$2")"; mkdir -p "$(dirname "$2")"
  if [ -f "$2" ] && cmp -s "$r" "$2"; then
    rm -f "$2.new"; manifest_lines+=("$(sum_of "$2") $2"); return
  fi
  if [ -f "$2" ] && [ "$force" != 1 ]; then
    rec="$(recorded "$2")"
    if [ -n "$rec" ] && [ "$rec" != "$(sum_of "$2")" ]; then   # edited by hand since the last install: keep it
      cat "$r" > "$2.new"; customised+=("$2"); manifest_lines+=("$rec $2"); return
    fi
  fi
  if [ -f "$2" ]; then updated+=("$2"); else created+=("$2"); fi
  cat "$r" > "$2"; rm -f "$2.new"; manifest_lines+=("$(sum_of "$2") $2")
}
copy_owned() { # src dst
  if [ -f "$2" ]; then kept+=("$2"); return; fi
  mkdir -p "$(dirname "$2")"; cat "$(render "$1" "$2")" > "$2"; created+=("$2")
}

# --- tooling (always current) ---
for f in gate promote intake status next-version check-signoff cloud-setup ticket-id base-ref enforcement doctor; do
  copy_tooling "$here/scripts/pipeline/$f.sh" "scripts/pipeline/$f.sh"
done
copy_tooling "$here/scripts/pipeline/tracker-schema.txt" "scripts/pipeline/tracker-schema.txt"
copy_tooling "$here/scripts/pipeline/hooks/allow-paths.sh" "scripts/pipeline/hooks/allow-paths.sh"
copy_tooling "$here/scripts/pipeline/hooks/guard-merge.sh" "scripts/pipeline/hooks/guard-merge.sh"
for f in "$here"/agents/*.md; do copy_tooling "$f" ".claude/agents/$(basename "$f")"; done
for f in TICKETS BRANCHING CLOUD; do copy_tooling "$here/template/docs/pipeline/$f.md" "docs/pipeline/$f.md"; done
for f in "$here"/template/docs/pipeline/_templates/*.md; do copy_tooling "$f" "docs/pipeline/_templates/$(basename "$f")"; done
for f in "$here"/tests/pipeline/*.sh; do copy_tooling "$f" "tests/pipeline/$(basename "$f")"; done

# --- project-owned (created once) --- (src_ctx / src_chk were resolved during argument validation)
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

printf 'init: %s (team key %s)\n' "$name" "$key"
printf '  branches: base=%s (from %s) staging=%s\n' "$base" "$base_from" "$stg"
printf '  capabilities: deploy-envs=%s marketing=%s\n' "$deploy_envs" "$marketing"
[ ${#created[@]} -gt 0 ] && printf '  created %s\n' "${created[@]}"
[ ${#updated[@]} -gt 0 ] && printf '  updated %s\n' "${updated[@]}"
[ ${#kept[@]} -gt 0 ] && printf '  kept    %s\n' "${kept[@]}"
[ ${#removed[@]} -gt 0 ] && printf '  removed %s (installer leftover)\n' "${removed[@]}"
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
if [ "$marketing" = no ] && printf '%s\n' "${kept[@]}" | grep -qx scripts/pipeline/pipeline.env; then
  echo 'This project declared no marketing function. Set PIPELINE_HAS_MARKETING="no" in scripts/pipeline/pipeline.env yourself — an existing pipeline.env is yours and is never rewritten.'
fi
cat <<MSG
Next:
  1. Fill in docs/pipeline/CONTEXT.md (product, stack, test commands, rules, high-risk areas) and RELEASE_CHECKLIST.md.
  2. Set the URLs and TRACKER_TEAM_KEY in scripts/pipeline/pipeline.env (ticket ids are <TEAM KEY>-<number>), and check
     PIPELINE_HAS_DEPLOY_ENVS / PIPELINE_HAS_MARKETING describe this project.
  3. Make sure branches $base + $stg exist on the code host, then the GitHub environments and the tracker labels and statuses
     (docs/pipeline/TICKETS.md; the list is scripts/pipeline/tracker-schema.txt).
  4. Run /pipeline-doctor (or: bash scripts/pipeline/doctor.sh) and work through anything it reports.
  5. Commit, then run: /ship <TICKET>
MSG
