#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "plugin layout / agents / commands / workflows"
cd "$REPO_SRC"
# Locate agents/commands whether we run in the plugin repo or an installed project.
if [ -d agents ] && [ -f .claude-plugin/plugin.json ]; then A=agents; C=commands; else A=.claude/agents; C=.claude/commands; fi
agents=(market-researcher product-owner business-analyst senior-engineer qa-tester app-specialist marketing-specialist)
fm() { awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f' "$1"; }
fmval() { fm "$1" | grep -m1 -E "^$2:" | sed -E "s/^$2:[[:space:]]*//"; }

[ "$(ls "$A"/*.md | wc -l | tr -d ' ')" = "${#agents[@]}" ] && ok "exactly ${#agents[@]} agents" || bad "exactly ${#agents[@]} agents"
for a in "${agents[@]}"; do
  f="$A/$a.md"; [ -f "$f" ] || { bad "$a: exists"; continue; }
  $PY -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]).read().split("\n---\n")[0].lstrip("---\n"))' "$f" 2>/dev/null && ok "$a: frontmatter parses" || bad "$a: frontmatter parses"
  [ "$(fmval "$f" name)" = "$a" ] && ok "$a: name matches file" || bad "$a: name matches file"
  case "$(fmval "$f" model)" in opus|sonnet|haiku|inherit) ok "$a: valid model";; *) bad "$a: valid model";; esac
  [ -z "$(fmval "$f" tools)" ] && ok "$a: no tools allowlist (keeps tracker MCP tools)" || bad "$a: no tools allowlist"
  grep -q "CONTEXT.md" "$f" && grep -q "TICKETS.md" "$f" && ok "$a: reads CONTEXT + TICKETS" || bad "$a: reads CONTEXT + TICKETS"
  if grep -qiwE "reputabill|curate|chris|paystack" "$f"; then bad "$a: project-agnostic"; else ok "$a: project-agnostic"; fi
done
d() { fmval "$A/$1.md" disallowedTools; }
denies() { case ", $(d "$1")," in *", $2,"*) return 0;; esac; return 1; }
denies app-specialist Write && denies app-specialist Edit && ok "app-specialist cannot write code" || bad "app-specialist cannot write code"
for a in product-owner business-analyst market-researcher marketing-specialist; do denies "$a" Bash && ok "$a has no Bash" || bad "$a has no Bash"; done
[ -z "$(d senior-engineer)" ] && ok "engineer unrestricted" || bad "engineer unrestricted"
for a in market-researcher product-owner business-analyst qa-tester marketing-specialist; do
  fm "$A/$a.md" | grep -q "allow-paths.sh" && ok "$a: write-boundary hook" || bad "$a: write-boundary hook"
done
grep -q "promote-dev" "$A/senior-engineer.md" && grep -q "dev-check.md" "$A/senior-engineer.md" && grep -qi "never write them yourself" "$A/senior-engineer.md" && ok "engineer: dev self-check, cannot self-approve go-live" || bad "engineer: dev self-check, cannot self-approve go-live"
grep -q "vX.Y.Z" "$A/senior-engineer.md" && grep -q "staging" "$A/senior-engineer.md" && ok "engineer knows branch/tag model" || bad "engineer knows branch/tag model"
grep -q "eng. child tickets" "$A/business-analyst.md" && ok "BA creates eng tickets" || bad "BA creates eng tickets"
for a in qa-tester app-specialist marketing-specialist; do grep -q "defect" "$A/$a.md" && ok "$a raises defect tickets" || bad "$a raises defect tickets"; done
grep -q "Launch content" "$A/marketing-specialist.md" && ok "marketing creates launch ticket" || bad "marketing creates launch ticket"
grep -qi "first" "$A/market-researcher.md" && ok "researcher goes first" || bad "researcher goes first"
# marketing is a project capability AND a per-ticket flag (AC-29, AC-30)
for a in senior-engineer app-specialist; do
  grep -q "marketing function" "$A/$a.md" && ok "$a: marketing is a project capability" || bad "$a: marketing is a project capability"
  grep -q "user-facing" "$A/$a.md" && ok "$a: and the ticket must be user-facing" || bad "$a: and the ticket must be user-facing"
done
grep -q "does not, by itself, decide whether any persona runs" "$A/product-owner.md" \
  && ok "product-owner: User-facing no longer decides which personas run" || bad "product-owner: User-facing no longer decides which personas run"
grep -qi "capabilit" "$A/marketing-specialist.md" && bad "marketing-specialist stays unaware of project capabilities" || ok "marketing-specialist stays unaware of project capabilities"

if [ "$A" = agents ]; then
s="$C/ship.md"; [ -f "$s" ] && ok "/ship exists" || bad "/ship exists"
for step in intake.sh "promote-dev" "promote-staging" "promote-production" "next-version.sh" "Version:" "Go-live: approved by" "argument-hint: <TICKET-ID>" "tracker connector" "CLAUDE_CODE_REMOTE" ".pipeline-ticket" "/pipeline-init"; do
  grep -qF "$step" "$s" && ok "/ship includes: $step" || bad "/ship includes: $step"
done
if grep -qiwE "reputabill|curate|chris" "$s"; then bad "/ship project-agnostic"; else ok "/ship project-agnostic"; fi
order=$($PY - "$s" <<'PY'
import sys; s=open(sys.argv[1]).read()
seq=["## 1. Research","`market-researcher`","`product-owner`","`business-analyst`","mode **build**","promote-dev","`qa-tester`","promote-staging","`app-specialist`","`marketing-specialist`","next-version.sh","Go-live: approved","promote-production"]
idx=[s.find(x) for x in seq]; print("yes" if all(i>=0 for i in idx) and idx==sorted(idx) else f"no {idx}")
PY
)
assert_eq "/ship stage order" "yes" "$order"
grep -q "marketing function" "$s" && ok "AC-29: /ship states the marketing condition as a project capability" || bad "AC-29: /ship states the marketing condition as a project capability"
grep -qF "skipped — this project has no marketing function" "$s" && ok "AC-29: /ship reports a skipped stage as configuration" || bad "AC-29: /ship reports a skipped stage as configuration"
for k in PIPELINE_HAS_DEPLOY_ENVS PIPELINE_HAS_MARKETING; do
  grep -qF "$k" "$s" && ok "/ship reads $k" || bad "/ship reads $k"
done
grep -qF 'marketing function **and** User-facing: yes' "$s" && ok "AC-29: /ship step 7 names both conditions (project capability AND User-facing: yes)" || bad "AC-29: /ship step 7 names both conditions (project capability AND User-facing: yes)"
# AC-31 / NFR-10: no vendor, product or person name in ANY persona or command file (the persona loop above only sees agents/)
# "curate" is matched as a whole word only, so ordinary words such as "accurate" are not flagged; the
# distinctive names are still matched anywhere, so a compound like "HetznerCloud" is caught too.
leak=$( { grep -niE "hetzner|reputabill|paystack|ship-pipeline" "$A"/*.md "$C"/*.md; grep -niwE "curate" "$A"/*.md "$C"/*.md; } || true)
[ -z "$leak" ] && ok "AC-31: no vendor/product name in agents/*.md or commands/*.md" || bad "AC-31: no vendor/product name in agents/*.md or commands/*.md" "$leak"
[ -f "$C/pipeline-status.md" ] && ok "/pipeline-status exists" || bad "/pipeline-status exists"
fi
if [ "$A" = agents ]; then
  [ -f "$C/pipeline-init.md" ] && grep -q 'CLAUDE_PLUGIN_ROOT' "$C/pipeline-init.md" && ok "/pipeline-init uses plugin root" || bad "/pipeline-init uses plugin root"
  # commands/ and agents/ are the plugin's default locations; plugin.json only needs to name and version it.
  $PY -c 'import json,re; d=json.load(open(".claude-plugin/plugin.json")); assert d["name"]=="ship-pipeline" and re.match(r"^\d+\.\d+\.\d+$", d["version"])' \
    && [ -d commands ] && [ -d agents ] && ok "plugin.json valid" || bad "plugin.json valid"
  $PY -c 'import json; d=json.load(open(".claude-plugin/marketplace.json")); assert d["plugins"][0]["name"]=="ship-pipeline"' && ok "marketplace.json valid" || bad "marketplace.json valid"
  [ -d profiles/reputabill ] && [ -f profiles/reputabill/CONTEXT.md ] && ok "reputabill profile present" || bad "reputabill profile present"
  T=template
else
  T=.
fi
# the plugin ships placeholders; an installed project has its own branch names (pipeline.env)
if [ "$A" = agents ]; then WB="__BASE_BRANCH__"; WS="__STAGING_BRANCH__"; else WB="$(bash scripts/pipeline/base-ref.sh --branch)"; WS="$(bash scripts/pipeline/base-ref.sh --staging)"; fi
export WB WS
$PY -c "import yaml; yaml.safe_load(open('$T/.github/workflows/pipeline-gate.yml'))" && ok "pipeline-gate.yml valid yaml" || bad "pipeline-gate.yml valid yaml"
# deploy.yml is absent in a project installed with --no-deploy-envs; the gate workflow is always there.
if [ ! -f "$T/.github/workflows/deploy.yml" ]; then
  ok "deploy.yml absent (project has no deployable environments)"
else
$PY -c "import yaml; yaml.safe_load(open('$T/.github/workflows/deploy.yml'))" && ok "deploy.yml valid yaml" || bad "deploy.yml valid yaml"
$PY - "$T/.github/workflows/deploy.yml" <<'PY' && ok "deploy.yml: branch/tag triggers, build on dev, tag-image on production" || bad "deploy.yml: branch/tag triggers, build on dev, tag-image on production"
import yaml,sys,os
w=yaml.safe_load(open(sys.argv[1])); on=w.get("on") or w.get(True); j=w["jobs"]
ok = on["push"]["branches"]==[os.environ["WB"],os.environ["WS"]] and any("v[0-9]" in t for t in on["push"]["tags"]) \
  and "docs/pipeline/**" in on["push"]["paths-ignore"] \
  and j["build"]["if"]=="needs.resolve.outputs.env == 'dev'" and j["tag-image"]["if"]=="needs.resolve.outputs.env == 'production'" \
  and any("imagetools create" in s.get("run","") for s in j["tag-image"]["steps"]) \
  and any("gate.sh" in s.get("run","") for s in j["resolve"]["steps"]) \
  and any("rollback.sh" in s.get("run","") for s in j["deploy"]["steps"])
sys.exit(0 if ok else 1)
PY
fi
$PY - "$T/.github/workflows/pipeline-gate.yml" <<'PY' && ok "pipeline-gate.yml: PRs to the base/staging branches gated" || bad "pipeline-gate.yml: PRs to the base/staging branches gated"
import yaml,sys,os
w=yaml.safe_load(open(sys.argv[1])); on=w.get("on") or w.get(True)
sys.exit(0 if on["pull_request"]["branches"]==[os.environ["WB"],os.environ["WS"]] and any("gate.sh" in s.get("run","") and "stage" in s.get("run","") for s in w["jobs"]["gate"]["steps"]) else 1)
PY
if [ "$A" = agents ]; then
  G="$T/.github/workflows/pipeline-gate.yml"; D="$T/.github/workflows/deploy.yml"
  grep -q "ticket-id.sh" "$G" && ! grep -q "grep -oiE" "$G" && ok "item 3: PR gate reads the one ticket-id definition" || bad "item 3: PR gate reads the one ticket-id definition"
  grep -q "ticket-id.sh" "$D" && ! grep -q "grep -oiE" "$D" && ok "item 3: deploy.yml reads the one ticket-id definition" || bad "item 3: deploy.yml reads the one ticket-id definition"
  grep -q "labels.\*.name, 'infra'" "$G" && grep -q "labeled" "$G" && ok "item 10: PR gate honours the infra label" || bad "item 10: PR gate honours the infra label"
  grep -q 'git diff --name-only' "$G" && ok "item 10: self-test runs only when the tooling changed" || bad "item 10: self-test runs only when the tooling changed"
  $PY - "$D" <<'PY' && ok "item 8: every deploy.yml job waits for PIPELINE_DEPLOY_ENABLED" || bad "item 8: every deploy.yml job waits for PIPELINE_DEPLOY_ENABLED"
import yaml,sys
j=yaml.safe_load(open(sys.argv[1]))["jobs"]
sys.exit(0 if j["resolve"]["if"]=="vars.PIPELINE_DEPLOY_ENABLED == 'true'" and all("resolve" in (v.get("needs") or []) for k,v in j.items() if k!="resolve") else 1)
PY
  grep -q "PIPELINE_BASE_REF=\"origin/master\"\|origin/master" "$G" "$D" && bad "item 2: workflows name no origin/master" || ok "item 2: workflows name no origin/master"
fi
for tpl in STATUS product requirements clarifications research impl-notes dev-check qa-report signoff marketing releases tickets; do
  [ -f "$T/docs/pipeline/_templates/$tpl.md" ] && ok "template $tpl.md" || bad "template $tpl.md"
done
grep -q '^Version:' "$T/docs/pipeline/_templates/releases.md" && ok "releases template has Version" || bad "releases template has Version"
for f in TICKETS BRANCHING CLOUD; do [ -f "$T/docs/pipeline/$f.md" ] && ok "doc $f.md" || bad "doc $f.md"; done
if [ "$A" = agents ]; then
  grep -q "__PROJECT_NAME__" template/docs/pipeline/CONTEXT.md && grep -q "__TEAM_KEY__" template/scripts/pipeline/pipeline.env && ok "templates have placeholders" || bad "templates have placeholders"
  E=template/scripts/pipeline/pipeline.env
  for k in PIPELINE_HAS_DEPLOY_ENVS PIPELINE_HAS_MARKETING; do
    grep -q "^$k=\"yes\"" "$E" && ok "pipeline.env template: $k defaults to yes" || bad "pipeline.env template: $k defaults to yes"
  done
  grep -q 'yes | no' "$E" && ok "pipeline.env template documents the allowed values" || bad "pipeline.env template documents the allowed values"
  for sec in "Domain risks" "Security" "Data & migrations" "Tickets"; do grep -q "^## .*$sec" template/RELEASE_CHECKLIST.md && ok "generic checklist: $sec" || bad "generic checklist: $sec"; done
  # AC-34: the settings are documented, and the repo copy and the shipped template copy agree
  for d in README.md docs/pipeline/TICKETS.md docs/pipeline/BRANCHING.md docs/pipeline/CLOUD.md \
           template/docs/pipeline/TICKETS.md template/docs/pipeline/BRANCHING.md template/docs/pipeline/CLOUD.md \
           template/docs/pipeline/CONTEXT.md template/RELEASE_CHECKLIST.md; do
    grep -q "PIPELINE_HAS_" "$d" && ok "AC-34: $d documents the capability settings" || bad "AC-34: $d documents the capability settings"
  done
  rb="$(bash scripts/pipeline/base-ref.sh --branch)"; rs="$(bash scripts/pipeline/base-ref.sh --staging)"
  for d in TICKETS BRANCHING CLOUD; do
    diff -q <(tr -d '\r' < "docs/pipeline/$d.md") <(tr -d '\r' < "template/docs/pipeline/$d.md" | sed -e "s:__BASE_BRANCH__:$rb:g" -e "s:__STAGING_BRANCH__:$rs:g") >/dev/null \
      && ok "AC-34: $d.md repo copy and template copy agree" || bad "AC-34: $d.md repo copy and template copy agree"
  done
  grep -q 'behaves exactly as it did before' README.md && ok "AC-34: README states existing installs are unaffected" || bad "AC-34: README states existing installs are unaffected"
  # AC-35: each release has exactly one release-notes section; plugin.json carries the newest (v1.2.0)
  $PY -c 'import json,sys; sys.exit(0 if json.load(open(".claude-plugin/plugin.json"))["version"]=="1.2.0" else 1)' \
    && ok "plugin.json version is 1.2.0" || bad "plugin.json version is 1.2.0"
  assert_eq "AC-35: exactly one '### v1.0.0' release-notes heading" "1" "$(grep -c '^### v1.0.0' README.md || true)"
  assert_eq "exactly one '### v1.1.0' release-notes heading" "1" "$(grep -c '^### v1.1.0' README.md || true)"
  assert_eq "exactly one '### v1.2.0' release-notes heading" "1" "$(grep -c '^### v1.2.0' README.md || true)"
  assert_eq "no 'Unreleased' release-notes heading" "0" "$(grep -c '^### Unreleased' README.md || true)"
  grep -q '^#### Upgrading from v1.0.0' README.md && ok "v1.1.0 notes explain the upgrade" || bad "v1.1.0 notes explain the upgrade"
  RELNOTES="$(sed -n '/^### v1.0.0/,$p' README.md | sed -n '/^## /q;p')"
  for tok in PIPELINE_HAS_DEPLOY_ENVS PIPELINE_HAS_MARKETING --no-deploy-envs; do
    assert_contains "AC-35: v1.0.0 release notes mention $tok" "$RELNOTES" "$tok"
  done
  # AC-36: this repo dogfoods the settings, and the four workaround texts are gone
  assert_contains "AC-36: this repo declares no deployable environments" "$(cat scripts/pipeline/pipeline.env)" 'PIPELINE_HAS_DEPLOY_ENVS="no"'
  assert_contains "AC-36: this repo declares no marketing function" "$(cat scripts/pipeline/pipeline.env)" 'PIPELINE_HAS_MARKETING="no"'
  assert_eq "AC-36: no 'n/a' apology left in pipeline.env" "0" "$(grep -ci 'n/a' scripts/pipeline/pipeline.env || true)"
  assert_eq "AC-36: no 'N/A — no image, no host' in RELEASE_CHECKLIST.md" "0" "$(grep -c 'N/A — no image, no host' RELEASE_CHECKLIST.md || true)"
  assert_eq "AC-36: no hand-narrowed User-facing parenthetical" "0" "$(grep -c 'only for changes visible to the installing developer' RELEASE_CHECKLIST.md || true)"
  assert_eq "AC-36: CONTEXT.md no longer tells readers to ignore the generic docs" "0" "$(grep -c 'ignore .build once' docs/pipeline/CONTEXT.md || true)"
  assert_eq "AC-36: the SHI-5 open question is gone from CONTEXT.md" "0" "$(grep -c 'marketing-specialist persona should be opt-out' docs/pipeline/CONTEXT.md || true)"
  assert_eq "AC-36: no reference to the non-existent template/agents path" "0" "$(grep -rc 'template/agents' docs/pipeline/CONTEXT.md RELEASE_CHECKLIST.md | awk -F: '{s+=$2} END {print s+0}')"
fi
for f in scripts/pipeline/{gate,check-signoff,promote,intake,status,next-version,cloud-setup,ticket-id,base-ref,enforcement,doctor}.sh scripts/pipeline/hooks/{allow-paths,guard-merge}.sh; do
  [ -x "$f" ] && bash -n "$f" && ok "$f executable + syntax" || bad "$f executable + syntax"
done
# scripts/deploy/* is absent in a project installed with --no-deploy-envs
if [ -d scripts/deploy ]; then
  for f in scripts/deploy/{deploy,rollback,smoke}.sh; do
    [ -x "$f" ] && bash -n "$f" && ok "$f executable + syntax" || bad "$f executable + syntax"
  done
else
  ok "scripts/deploy absent (project has no deployable environments)"
fi
# item 5: the tracker list is data, and TICKETS.md agrees with it
SCH=scripts/pipeline/tracker-schema.txt; TK="$T/docs/pipeline/TICKETS.md"
if [ -f "$SCH" ]; then
  for g in Stage Owner; do
    want="$(awk -F'|' -v g="$g" '$1=="label-group" && $2==g {print $3}' "$SCH" | tr -d ' ')"
    have="$(grep -E "^\| \`$g\` \|" "$TK" | awk -F'|' '{print $3}' | tr -d ' ')"
    assert_eq "item 5: TICKETS.md $g labels match tracker-schema.txt" "$want" "$have"
  done
  for st in $(awk -F'|' '$1=="status" {print $2"="$3}' "$SCH" | tr ' ' '_'); do
    k="${st%%=*}"; v="${st#*=}"; v="${v//_/ }"
    grep -qE "(^|[ /])$k[a-z/]* → $v" "$TK" && ok "item 5: TICKETS.md maps $k to $v" || bad "item 5: TICKETS.md maps $k to $v"
  done
  grep -q "single-select" "$TK" && ok "item 5: TICKETS.md says the label groups are single-select" || bad "item 5: TICKETS.md says the label groups are single-select"
else bad "item 5: tracker-schema.txt exists"; fi
if [ "$A" = agents ]; then
  [ -f "$C/pipeline-doctor.md" ] && grep -q 'doctor.sh' "$C/pipeline-doctor.md" && ok "item 1: /pipeline-doctor exists" || bad "item 1: /pipeline-doctor exists"
  grep -q 'doctor' "$C/pipeline-init.md" && grep -q -- '--base-branch' "$C/pipeline-init.md" && ok "item 1/2: /pipeline-init asks for the base branch and ends with the doctor" || bad "item 1/2: /pipeline-init asks for the base branch and ends with the doctor"
  grep -q 'enforcement.sh' "$C/pipeline-status.md" && ok "item 6: /pipeline-status reports the enforcement mode" || bad "item 6: /pipeline-status reports the enforcement mode"
  lit="$(grep -rnw 'master' "$A" "$C" template | grep -v '^template/profiles' || true)"
  assert_eq "item 2: no 'master' literal in agents, commands or template" "" "$lit"
  grep -qF 'PIPELINE_TICKET_REGEX="${TRACKER_TEAM_KEY:-}-[0-9]+"' template/scripts/pipeline/pipeline.env && ok "item 3: the template regex is the team key" || bad "item 3: the template regex is the team key"
  grep -q '^PIPELINE_REMOTE="origin"' template/scripts/pipeline/pipeline.env && ok "item 9: the template declares PIPELINE_REMOTE" || bad "item 9: the template declares PIPELINE_REMOTE"
  grep -q 'local hook only' template/docs/pipeline/BRANCHING.md && ok "item 6: BRANCHING.md states both enforcement modes" || bad "item 6: BRANCHING.md states both enforcement modes"
  grep -q 'Supported hosts' template/docs/pipeline/BRANCHING.md && grep -q 'Supported hosts' README.md && ok "item 9: supported hosts are stated" || bad "item 9: supported hosts are stated"
  grep -q '^## Persona notes' template/docs/pipeline/CONTEXT.md && ok "item 11: CONTEXT.md has a Persona notes section" || bad "item 11: CONTEXT.md has a Persona notes section"
  for a in "${agents[@]}"; do grep -q "Persona notes" "$A/$a.md" && ok "item 11: $a reads its Persona notes" || bad "item 11: $a reads its Persona notes"; done
fi
[ -f scripts/pipeline/merge.sh ] && bad "merge.sh removed (promote.sh dev merges)" || ok "merge.sh removed (promote.sh dev merges)"
summary
