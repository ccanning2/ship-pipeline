#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "intake.sh / status.sh"
intake() { (cd "$R" && bash scripts/pipeline/intake.sh "$@" 2>&1); }

new_repo
out=$(intake); assert_exit "intake: no args fails" 1 $? "$out"
out=$(printf '   \n' | intake REP-70 -); assert_exit "intake: empty brief fails" 1 $? "$out"
out=$(printf 'Vendors want an embeddable badge.\n' | intake rep-70 -); assert_exit "intake: text on stdin" 0 $? "$out"
d="$(tdir REP-70)"
assert_contains "intake: brief has text" "$(cat "$d/brief.md")" "embeddable badge"
assert_contains "intake: brief source = chat" "$(cat "$d/brief.md")" "Source: text (chat)"
assert_contains "intake: STATUS created with ticket" "$(cat "$d/STATUS.md")" "REP-70 — Pipeline status"
[ -f "$d/clarifications.md" ] && [ -f "$d/releases.md" ] && ok "intake: clarifications + releases created" || bad "intake: clarifications + releases created"
[ -d "$d/source" ] && bad "intake: no empty source dir for text" || ok "intake: no empty source dir for text"
echo "custom" >> "$d/STATUS.md"
printf 'updated brief\n' | intake REP-70 - >/dev/null
assert_contains "intake: re-run keeps STATUS" "$(cat "$d/STATUS.md")" "custom"
assert_contains "intake: re-run refreshes brief" "$(cat "$d/brief.md")" "updated brief"
printf 'from tracker\n' | intake REP-70 - "https://linear.app/x/issue/REP-70" >/dev/null
assert_contains "intake: origin label recorded" "$(cat "$d/brief.md")" "Source: https://linear.app/x/issue/REP-70"

printf '# Req\nMust support badges.\n' > "$R/req.md"
out=$(intake REP-71 req.md); assert_exit "intake: markdown file" 0 $? "$out"
assert_contains "intake: md content" "$(cat "$(tdir REP-71)/brief.md")" "Must support badges"
[ -f "$(tdir REP-71)/source/req.md" ] && ok "intake: original copied to source/" || bad "intake: original copied to source/"

out=$(intake REP-72 missing.docx); assert_exit "intake: missing file fails" 1 $? "$out"
echo x > "$R/req.xlsx"; out=$(intake REP-72 req.xlsx); assert_exit "intake: unsupported type fails" 1 $? "$out"

# .docx support is optional in intake.sh (pandoc or python-docx); only test it when we can build one.
if $PY -c 'import docx' >/dev/null 2>&1; then
$PY - "$R/Req.DOCX" <<'PY'
import sys, docx
d = docx.Document(); d.add_heading("Reputation passport", 1); d.add_paragraph("Vendors embed a verified badge."); d.save(sys.argv[1])
PY
out=$(intake REP-73 Req.DOCX); assert_exit "intake: docx (uppercase ext)" 0 $? "$out"
assert_contains "intake: docx text extracted" "$(cat "$(tdir REP-73)/brief.md")" "Vendors embed a verified badge."
else
  ok "intake: docx (skipped — no python-docx to build a fixture)"
  ok "intake: docx text extracted (skipped — no python-docx to build a fixture)"
fi

if command -v pdftotext >/dev/null && command -v pandoc >/dev/null; then
  $PY - "$R/req.pdf" <<'PY'
import sys
from reportlab.pdfgen import canvas
c = canvas.Canvas(sys.argv[1]); c.drawString(72, 720, "Escrow release after event date"); c.save()
PY
  if [ -f "$R/req.pdf" ]; then
    out=$(intake REP-74 req.pdf); assert_exit "intake: pdf" 0 $? "$out"
    assert_contains "intake: pdf text extracted" "$(cat "$(tdir REP-74)/brief.md")" "Escrow release after event date"
  fi
fi

# status
new_repo; branch feature/REP-80; full_through REP-80 chore no staging
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_exit "status: exits 0" 0 $? "$out"
assert_contains "status: build cleared" "$out" "[x] build"
assert_contains "status: dev cleared" "$out" "[x] dev"
assert_contains "status: qa cleared" "$out" "[x] qa"
assert_contains "status: staging cleared" "$out" "[x] staging"
assert_contains "status: production pending" "$out" "[ ] production"
assert_contains "status: next gate" "$out" "Next gate to clear: production"
full_sha=$(dev_sha_of REP-80)
record REP-80 Staging "$full_sha"; signoff REP-80 approved "$full_sha"; golive REP-80
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "status: shipped" "$out" "none (shipped)"
out=$(cd "$R" && bash scripts/pipeline/status.sh 2>&1); assert_exit "status: no args fails" 1 $? "$out"

# status: the project capability (AC-32, AC-33)
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "status: capabilities line present" "$out" "Project capabilities:"
assert_contains "status: deploy-envs on by default" "$out" "deploy-envs=on"
case "$out" in *marketing*) bad "status: marketing is no longer a capability" "$out";; *) ok "status: marketing is no longer a capability";; esac
set_capability PIPELINE_HAS_DEPLOY_ENVS '"no"'
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_exit "AC-32: status still exits 0" 0 $? "$out"
assert_contains "AC-32: deploy-envs off" "$out" "deploy-envs=off"
assert_contains "AC-32: names what deploy-envs off disables" "$out" "deploy, dispatch and smoke steps are skipped; promotion still runs"
set_capability PIPELINE_HAS_DEPLOY_ENVS '"flase"'
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_exit "QA: status exits 0 with a typo in deploy-envs" 0 $? "$out"
assert_contains "AC-33: a typo resolves on, and the raw value is surfaced" "$out" "deploy-envs=on (unrecognised value 'flase'"
assert_eq "AC-33: gate.sh stderr stays empty on a passing run" "" "$(cd "$R" && bash scripts/pipeline/gate.sh REP-80 build 2>&1 >/dev/null)"
set_capability PIPELINE_HAS_DEPLOY_ENVS '" No "'
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_contains "QA: ' No ' trims and lowercases to off" "$out" "deploy-envs=off"
set_capability_crlf PIPELINE_HAS_DEPLOY_ENVS no
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_contains "QA: 'no' with a trailing CR shows off" "$out" "deploy-envs=off"
unset_capability PIPELINE_HAS_DEPLOY_ENVS
out=$(cd "$R" && PIPELINE_HAS_DEPLOY_ENVS=no bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "AC-33: the environment cannot flip the capability" "$out" "deploy-envs=on"
set_capability PIPELINE_HAS_DEPLOY_ENVS '"yes"'

# acceptance test 2: intake takes this team's ids only
printf 'brief\n' > "$R/b.md"
out=$(cd "$R" && bash scripts/pipeline/intake.sh REP-4242 b.md 2>&1); assert_exit "intake accepts REP-4242" 0 $? "$out"
for s in macos-14 UTF-8 v1.45.0-jammy ABC-12; do
  out=$(cd "$R" && bash scripts/pipeline/intake.sh "$s" b.md 2>&1); assert_exit "intake rejects $s" 1 $? "$out"
done
[ -d "$R/docs/pipeline/MACOS-14" ] && bad "a rejected id creates no folder" || ok "a rejected id creates no folder"

# ---- handover.sh: a ticket picked up at a later start level passes the same gates ----
ho() { (cd "$R" && bash scripts/pipeline/handover.sh "$@" 2>&1); }
new_repo; set_capability PIPELINE_START_LEVEL '"engineering"'; commit_all level
branch feature/REP-300-x; printf 'Analysed upstream: do X.\n' | (cd "$R" && bash scripts/pipeline/intake.sh REP-300 - https://t/REP-300 >/dev/null)
out=$(ho REP-300 --type bugfix --user-facing no --eng REP-301,rep-302); assert_exit "handover: engineering" 0 $? "$out"
assert_contains "handover: the level comes from pipeline.env" "$out" "at the engineering level"
assert_contains "handover: product.md is approved with the given type" "$(cat "$(tdir REP-300)/product.md")" "Type: bugfix"
assert_eq "handover: both eng rows, open" "2" "$(grep -cE '^\| REP-30[12] \| eng \|.*\| open \|' "$(tdir REP-300)/tickets.md")"
[ -e "$(tdir REP-300)/impl-notes.md" ] && bad "handover: engineering writes no impl-notes.md" || ok "handover: engineering writes no impl-notes.md"
commit_all handover
out=$(gate REP-300 build); assert_exit "handover: an engineering hand-over passes the build gate" 0 $? "$out"
out=$(gate REP-300 dev); assert_exit "handover: but not the dev gate (the engineer has not built it)" 1 $? "$out"
before="$(cat "$(tdir REP-300)/product.md")"; out=$(ho REP-300 --type feature)
assert_eq "handover: a re-run keeps every existing record" "$before" "$(cat "$(tdir REP-300)/product.md")"
assert_eq "handover: and adds no second row" "1" "$(grep -c '^| REP-300 ' "$(tdir REP-300)/tickets.md")"

new_repo; branch feature/REP-310-x; echo "class Built {}" > "$R/src/Built.java"; commit_all built
printf 'Built upstream.\n' | (cd "$R" && bash scripts/pipeline/intake.sh REP-310 - >/dev/null)
out=$(ho REP-310 --level devops); assert_exit "handover: devops" 0 $? "$out"; commit_all handover
assert_contains "handover: devops rows are done" "$(cat "$(tdir REP-310)/tickets.md")" "| REP-310 | eng | - | - | done |"
assert_contains "handover: impl-notes names the branch" "$(cat "$(tdir REP-310)/impl-notes.md")" "feature/REP-310-x"
out=$(gate REP-310 dev); assert_exit "handover: a devops hand-over passes the dev gate" 0 $? "$out"

new_repo; branch feature/REP-320-x; echo "class OnQa {}" > "$R/src/OnQa.java"; commit_all onqa
qa_sha=$(g rev-parse HEAD); g update-ref refs/heads/master "$qa_sha"; g update-ref refs/remotes/origin/master "$qa_sha"; g update-ref refs/remotes/origin/staging "$qa_sha"
printf 'On qa upstream.\n' | (cd "$R" && bash scripts/pipeline/intake.sh REP-320 - >/dev/null)
out=$(ho REP-320 --level qa); assert_exit "handover: qa" 0 $? "$out"
assert_contains "handover: qa takes the build from the staging branch" "$(cat "$(tdir REP-320)/releases.md")" "QA: $qa_sha"
commit_all handover
out=$(gate REP-320 qa); assert_exit "handover: a qa hand-over passes the qa gate" 0 $? "$out"
out=$(gate REP-320 staging); assert_exit "handover: but staging still needs QA's own report" 1 $? "$out"
qa_report REP-320 pass "$qa_sha"
out=$(gate REP-320 staging); assert_exit "handover: after QA passes, the staging gate passes" 0 $? "$out"
out=$(ho REP-320 --level nope); assert_exit "handover: an unknown level is refused" 1 $? "$out"
out=$(ho REP-999 --level engineering); assert_exit "handover: needs intake first" 1 $? "$out"
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-320 2>&1); assert_contains "status: prints the start level" "$out" "Start level: analysis"
summary
