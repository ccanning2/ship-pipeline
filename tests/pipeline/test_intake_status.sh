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

# status: project capabilities (AC-32, AC-33)
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "status: capabilities line present" "$out" "Project capabilities:"
assert_contains "status: deploy-envs on by default" "$out" "deploy-envs=on"
assert_contains "status: marketing on by default" "$out" "marketing=on"
set_capability PIPELINE_HAS_DEPLOY_ENVS '"no"'; set_capability PIPELINE_HAS_MARKETING '"no"'
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1); assert_exit "AC-32: status still exits 0" 0 $? "$out"
assert_contains "AC-32: deploy-envs off" "$out" "deploy-envs=off"
assert_contains "AC-32: names what deploy-envs off disables" "$out" "deploy, dispatch and smoke steps are skipped; promotion still runs"
assert_contains "AC-32: marketing off" "$out" "marketing=off"
assert_contains "AC-32: names what marketing off disables" "$out" "marketing-specialist and the production marketing requirement are skipped"
set_capability PIPELINE_HAS_MARKETING '"flase"'
out=$(cd "$R" && bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "AC-33: an unrecognised value resolves strict" "$out" "marketing=on"
assert_contains "AC-33: the raw value is surfaced here and nowhere else" "$out" "unrecognised value 'flase'"
assert_eq "AC-33: gate.sh stderr stays empty on a passing run" "" "$(cd "$R" && bash scripts/pipeline/gate.sh REP-80 build 2>&1 >/dev/null)"
unset_capability PIPELINE_HAS_MARKETING
out=$(cd "$R" && PIPELINE_HAS_MARKETING=no bash scripts/pipeline/status.sh REP-80 2>&1)
assert_contains "AC-33: the environment cannot flip a capability" "$out" "marketing=on"

summary
