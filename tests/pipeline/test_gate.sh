#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "gate.sh"

new_repo
out=$(gate REP-1 build); assert_exit "missing folder fails" 1 $? "$out"; assert_contains "explains missing folder" "$out" "no pipeline folder"
out=$(gate REP-1); assert_exit "missing stage fails" 1 $? "$out"
out=$(gate REP-1 deploy); assert_exit "unknown stage fails" 1 $? "$out"
out=$(cd "$R" && bash scripts/pipeline/gate.sh 2>&1); assert_exit "no args fails" 1 $? "$out"

# ---- build ----
new_repo; ready_build REP-2 feature yes
out=$(gate REP-2 build); assert_exit "build: approved feature with eng ticket passes" 0 $? "$out"
assert_contains "prints DEPLOY_SHA" "$out" "DEPLOY_SHA="
assert_contains "AC-6: PASS line reports marketing capability" "$out" "marketing=on"
assert_contains "AC-6: PASS line reports deploy-envs capability" "$out" "deploy-envs=on"
assert_eq "AC-6: DEPLOY_SHA stays the parseable line promote.sh reads" "$(g rev-parse HEAD)" "$(echo "$out" | sed -n 's/^DEPLOY_SHA=//p')"
assert_eq "AC-6/AC-33: nothing on stderr for a passing gate" "" "$(cd "$R" && bash scripts/pipeline/gate.sh REP-2 build 2>&1 >/dev/null)"
set_capability PIPELINE_HAS_MARKETING '"no"'; set_capability PIPELINE_HAS_DEPLOY_ENVS '"no"'
out=$(gate REP-2 build); assert_exit "AC-11: build gate unaffected by capabilities" 0 $? "$out"
assert_contains "AC-6: PASS line reports marketing=off" "$out" "marketing=off"
assert_contains "AC-6: PASS line reports deploy-envs=off" "$out" "deploy-envs=off"
set_capability PIPELINE_HAS_MARKETING '"yes"'; set_capability PIPELINE_HAS_DEPLOY_ENVS '"yes"'
out=$(gate rep-2 build); assert_exit "build: lowercase id normalised" 0 $? "$out"
rm "$(tdir REP-2)/brief.md"; commit_all x
out=$(gate REP-2 build); assert_exit "build: missing brief fails" 1 $? "$out"; assert_contains "names brief" "$out" "brief.md"

new_repo; ready_build REP-3 feature no complete approved draft
out=$(gate REP-3 build); assert_exit "build: product draft fails" 1 $? "$out"
new_repo; ready_build REP-4 improvement no
out=$(gate REP-4 build); assert_exit "build: invalid Type fails" 1 $? "$out"
new_repo; ready_build REP-5 chore maybe
out=$(gate REP-5 build); assert_exit "build: invalid User-facing fails" 1 $? "$out"
new_repo; ready_build REP-6 feature no draft
out=$(gate REP-6 build); assert_exit "build: feature needs complete research" 1 $? "$out"
rm "$(tdir REP-6)/research.md"; commit_all x
out=$(gate REP-6 build); assert_exit "build: feature without research fails" 1 $? "$out"
new_repo; ready_build REP-7 bugfix no; rm "$(tdir REP-7)/research.md"; commit_all x
out=$(gate REP-7 build); assert_exit "build: bugfix needs no research" 0 $? "$out"
new_repo; ready_build REP-8 chore no complete needs-input
out=$(gate REP-8 build); assert_exit "build: requirements needs-input fails" 1 $? "$out"
new_repo; ready_build REP-9 chore no; tickets_header REP-9; commit_all x
out=$(gate REP-9 build); assert_exit "build: no eng tickets fails" 1 $? "$out"; assert_contains "explains BA tickets" "$out" "no eng tickets"
rm "$(tdir REP-9)/tickets.md"; commit_all x
out=$(gate REP-9 build); assert_exit "build: missing tickets.md fails" 1 $? "$out"
new_repo; ready_build REP-11 chore no; add_ticket REP-11 REP-1102 bug - - open; commit_all x
out=$(gate REP-11 build); assert_exit "build: unknown ticket kind fails" 1 $? "$out"; assert_contains "names bad row" "$out" "REP-1102"
new_repo; ready_build REP-12 chore no; add_ticket REP-12 REP-1202 defect qa High closed; commit_all x
out=$(gate REP-12 build); assert_exit "build: unknown ticket state fails" 1 $? "$out"
new_repo; ready_build REP-13 chore no
printf '| not-a-ticket | eng | - | - | open | x | ignored |\n' >> "$(tdir REP-13)/tickets.md"; commit_all x
out=$(gate REP-13 build); assert_exit "build: non-ticket rows ignored" 0 $? "$out"

# ---- dev ----
new_repo; branch feature/REP-20; ready_build REP-20 chore no
out=$(gate REP-20 dev); assert_exit "dev: no impl-notes fails" 1 $? "$out"
printf 'Status: ready-for-dev\n' > "$(tdir REP-20)/impl-notes.md"; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: eng ticket still open fails" 1 $? "$out"; assert_contains "names open eng" "$out" "REP-2001"
set_ticket REP-20 REP-2001 in-progress; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: eng in-progress fails" 1 $? "$out"
set_ticket REP-20 REP-2001 done; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: ready build passes" 0 $? "$out"
assert_eq "dev: DEPLOY_SHA is HEAD" "DEPLOY_SHA=$(g rev-parse HEAD)" "$(echo "$out" | grep DEPLOY_SHA)"
printf 'Status: in-progress\n' > "$(tdir REP-20)/impl-notes.md"; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: impl in-progress fails" 1 $? "$out"
printf 'Status: ready-for-dev\n' > "$(tdir REP-20)/impl-notes.md"
add_ticket REP-20 REP-2002 defect qa High open; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: open defect blocks redeploy" 1 $? "$out"; assert_contains "names open defect" "$out" "REP-2002"
set_ticket REP-20 REP-2002 reopened; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: reopened defect blocks" 1 $? "$out"
set_ticket REP-20 REP-2002 fixed; commit_all x
out=$(gate REP-20 dev); assert_exit "dev: fixed defect allows redeploy" 0 $? "$out"
g checkout -q master; echo m > "$R/src/Main2.java"; commit_all "master moved"; g checkout -q feature/REP-20
out=$(gate REP-20 dev); assert_exit "dev: branch missing latest master fails" 1 $? "$out"; assert_contains "explains merge-master" "$out" "not up to date"
out=$(cd "$R" && PIPELINE_BASE_REF=HEAD~1 bash scripts/pipeline/gate.sh REP-20 dev 2>&1); assert_exit "dev: PIPELINE_BASE_REF honoured" 0 $? "$out"

# ---- qa ----
new_repo; full_through REP-30 chore no dev; dsha=$(g rev-parse HEAD)
out=$(gate REP-30 qa); assert_exit "qa: no dev deploy fails" 1 $? "$out"
record REP-30 Dev "$dsha"
out=$(gate REP-30 qa); assert_exit "qa: missing dev-check fails" 1 $? "$out"; assert_contains "names dev-check" "$out" "dev-check.md"
dev_check REP-30 fail "$dsha"
out=$(gate REP-30 qa); assert_exit "qa: dev-check fail blocks" 1 $? "$out"
dev_check REP-30 pass "$dsha" qa
out=$(gate REP-30 qa); assert_exit "qa: dev-check wrong env fails" 1 $? "$out"
dev_check REP-30 pass "$(g rev-parse "$dsha~1")"
out=$(gate REP-30 qa); assert_exit "qa: dev-check of other sha fails" 1 $? "$out"
dev_check REP-30 pass "${dsha:0:10}"
out=$(gate REP-30 qa); assert_exit "qa: dev-checked build passes (short sha)" 0 $? "$out"
assert_eq "qa: DEPLOY_SHA is dev sha" "DEPLOY_SHA=$dsha" "$(echo "$out" | grep DEPLOY_SHA)"
tip=$(g rev-parse HEAD); g checkout -qb feature/REP-30-x; g update-ref refs/heads/master "$(g rev-parse "$dsha~1")"
out=$(gate REP-30 qa); assert_exit "qa: build not on master fails" 1 $? "$out"; assert_contains "explains not on master" "$out" "not on master"
g update-ref refs/heads/master "$tip"; g checkout -q master
# CI shape: code at the build sha (predates the records), docs from master
out=$(gate REP-30 qa "$dsha"); assert_exit "qa: ref mode on bare build sha fails (records not there yet)" 1 $? "$out"
out=$(cd "$R" && PIPELINE_DOCS_REF=master bash scripts/pipeline/gate.sh REP-30 qa "$dsha" 2>&1); assert_exit "qa: PIPELINE_DOCS_REF=master + build sha passes" 0 $? "$out"
assert_eq "qa: docs-ref DEPLOY_SHA is build sha" "DEPLOY_SHA=$dsha" "$(echo "$out" | grep DEPLOY_SHA)"
out=$(cd "$R" && PIPELINE_DOCS_REF=nope bash scripts/pipeline/gate.sh REP-30 qa "$dsha" 2>&1); assert_exit "qa: unknown docs ref fails" 1 $? "$out"
echo note >> "$(tdir REP-30)/STATUS.md"; commit_all docs
out=$(gate REP-30 qa); assert_exit "qa: docs-only change keeps gate" 0 $? "$out"
echo "class Late {}" > "$R/src/Late.java"; commit_all late
out=$(gate REP-30 qa); assert_exit "qa: code change after dev deploy fails" 1 $? "$out"; assert_contains "explains redeploy" "$out" "code changed since dev deploy"

new_repo; full_through REP-31 chore no dev; record REP-31 Dev deadbeefdeadbeef
out=$(gate REP-31 qa); assert_exit "qa: unknown dev sha fails" 1 $? "$out"
record REP-31 Dev not-a-sha
out=$(gate REP-31 qa); assert_exit "qa: malformed dev sha fails" 1 $? "$out"
g checkout -qb side; echo s > "$R/src/S.java"; commit_all side; ssha=$(g rev-parse HEAD); g checkout -q master
record REP-31 Dev "$ssha"
out=$(gate REP-31 qa); assert_exit "qa: dev sha outside history fails" 1 $? "$out"; assert_contains "explains ancestry" "$out" "not an ancestor"

# ---- staging ----
new_repo; full_through REP-40 chore no qa; sha=$(dev_sha_of REP-40)
out=$(gate REP-40 staging); assert_exit "staging: no QA deploy fails" 1 $? "$out"
record REP-40 QA "$(g rev-parse "$sha~1")"
out=$(gate REP-40 staging); assert_exit "staging: QA runs different build fails" 1 $? "$out"
record REP-40 QA "$sha"
out=$(gate REP-40 staging); assert_exit "staging: missing qa-report fails" 1 $? "$out"
qa_report REP-40 fail "$sha"
out=$(gate REP-40 staging); assert_exit "staging: QA fail blocks" 1 $? "$out"
qa_report REP-40 pass "$sha" staging
out=$(gate REP-40 staging); assert_exit "staging: qa-report wrong env fails" 1 $? "$out"
qa_report REP-40 pass "$(g rev-parse "$sha~1")"
out=$(gate REP-40 staging); assert_exit "staging: qa-report other sha fails" 1 $? "$out"
qa_report REP-40 pass "$sha"
out=$(gate REP-40 staging); assert_exit "staging: QA pass passes" 0 $? "$out"
assert_eq "staging: DEPLOY_SHA is QA sha" "DEPLOY_SHA=$sha" "$(echo "$out" | grep DEPLOY_SHA)"
add_ticket REP-40 REP-4002 defect qa Medium fixed; commit_all x
out=$(gate REP-40 staging); assert_exit "staging: QA defect fixed but unverified fails" 1 $? "$out"; assert_contains "names unverified" "$out" "REP-4002"
set_ticket REP-40 REP-4002 verified; commit_all x
out=$(gate REP-40 staging); assert_exit "staging: verified QA defect passes" 0 $? "$out"
add_ticket REP-40 REP-4003 defect dev Low wontfix; add_ticket REP-40 REP-4004 defect staging High fixed; commit_all x
out=$(gate REP-40 staging); assert_exit "staging: wontfix dev defect + fixed staging defect ok" 0 $? "$out"
add_ticket REP-40 REP-4005 defect staging High open; commit_all x
out=$(gate REP-40 staging); assert_exit "staging: open staging defect fails (dev gate rule)" 1 $? "$out"

# ---- production ----
new_repo; full_through REP-50 feature yes staging; sha=$(dev_sha_of REP-50)
out=$(gate REP-50 production); assert_exit "prod: no staging deploy fails" 1 $? "$out"
record REP-50 Staging "$(g rev-parse "$sha~1")"
out=$(gate REP-50 production); assert_exit "prod: staging runs other build fails" 1 $? "$out"
record REP-50 Staging "$sha"
out=$(gate REP-50 production); assert_exit "prod: missing sign-off fails" 1 $? "$out"
signoff REP-50 blocked "$sha"
out=$(gate REP-50 production); assert_exit "prod: blocked sign-off fails" 1 $? "$out"
signoff REP-50 approved "$sha" qa
out=$(gate REP-50 production); assert_exit "prod: sign-off wrong env fails" 1 $? "$out"
signoff REP-50 approved "$(g rev-parse "$sha~1")"
out=$(gate REP-50 production); assert_exit "prod: sign-off other sha fails" 1 $? "$out"
signoff REP-50 approved "$sha"
add_ticket REP-50 REP-5002 defect staging Medium fixed; commit_all x
out=$(gate REP-50 production); assert_exit "prod: staging defect unverified fails" 1 $? "$out"
set_ticket REP-50 REP-5002 verified; add_ticket REP-50 REP-5003 defect staging High wontfix; commit_all x
out=$(gate REP-50 production); assert_exit "prod: High wontfix fails" 1 $? "$out"; assert_contains "explains High wontfix" "$out" "High-severity"
set_ticket REP-50 REP-5003 verified; commit_all x
out=$(gate REP-50 production); assert_exit "prod: user-facing without marketing fails" 1 $? "$out"
assert_contains "AC-9: today's missing-file message" "$out" "missing marketing.md"
marketing REP-50 changes-requested
out=$(gate REP-50 production); assert_exit "prod: marketing changes-requested fails" 1 $? "$out"
assert_contains "AC-9: today's status message" "$out" "marketing.md Status is not 'ready'"
marketing REP-50 ready
out=$(gate REP-50 production); assert_exit "prod: no launch ticket fails" 1 $? "$out"; assert_contains "explains launch ticket" "$out" "marketing launch ticket"
add_ticket REP-50 REP-5090 marketing - - open; commit_all x
out=$(gate REP-50 production); assert_exit "prod: launch ticket not done fails" 1 $? "$out"
set_ticket REP-50 REP-5090 done; commit_all x
out=$(gate REP-50 production); assert_exit "prod: no go-live fails" 1 $? "$out"; assert_contains "explains go-live" "$out" "Go-live"
golive REP-50 "no-go (waiting)"
out=$(gate REP-50 production); assert_exit "prod: no-go fails" 1 $? "$out"
golive REP-50 "approved by owner 2026-09-17" "1.2.3"
out=$(gate REP-50 production); assert_exit "prod: version without v prefix fails" 1 $? "$out"; assert_contains "explains version" "$out" "Version must be"
golive REP-50 "approved by owner 2026-09-17" "v1.2.3"
out=$(gate REP-50 production); assert_exit "prod: fully approved passes" 0 $? "$out"
assert_eq "prod: DEPLOY_SHA is staging sha" "DEPLOY_SHA=$sha" "$(echo "$out" | grep DEPLOY_SHA)"
assert_contains "prod: prints VERSION" "$out" "VERSION=v1.2.3"
g tag v1.2.3 "$sha"
out=$(gate REP-50 production v1.2.3); assert_exit "prod: tag alone fails (records live on master)" 1 $? "$out"
out=$(cd "$R" && PIPELINE_DOCS_REF=master bash scripts/pipeline/gate.sh REP-50 production v1.2.3 2>&1); assert_exit "prod: tag + docs from master passes (CI shape)" 0 $? "$out"
assert_contains "prod: CI shape VERSION" "$out" "VERSION=v1.2.3"
g tag -d v1.2.3 >/dev/null
g tag v1.2.3 "$(g rev-parse "$sha~1")"
out=$(gate REP-50 production); assert_exit "prod: version tag already used elsewhere fails" 1 $? "$out"; assert_contains "explains bump" "$out" "bump the version"
g tag -d v1.2.3 >/dev/null; g tag v1.2.3 "$sha"
out=$(gate REP-50 production); assert_exit "prod: tag already on this sha is fine (idempotent)" 0 $? "$out"
cur=$(g rev-parse --abbrev-ref HEAD); g checkout -qb tmp; g checkout -q "$cur"
echo z > "$R/src/Z.java"; g add -A; g commit -qm "other ticket on master"; g checkout -q tmp
out=$(gate REP-50 production); assert_exit "prod: other ticket merged to master since staging is fine (sha still on master)" 0 $? "$out"

new_repo; full_through REP-51 bugfix no staging; sha=$(dev_sha_of REP-51)
record REP-51 Staging "$sha"; signoff REP-51 approved "$sha"; golive REP-51
out=$(gate REP-51 production); assert_exit "prod: non-user-facing needs no marketing" 0 $? "$out"
assert_contains "AC-10: marketing=yes + non-user-facing passes (unchanged)" "$out" "marketing=on"
set_capability PIPELINE_HAS_MARKETING '"no"'
out=$(gate REP-51 production); assert_exit "AC-10: marketing=no + non-user-facing also passes" 0 $? "$out"

new_repo; full_through REP-52 feature yes production
out=$(gate REP-52 production); assert_exit "prod: full_through fixture passes" 0 $? "$out"

# ---- project capabilities: the production marketing condition ----
new_repo; full_through REP-60 feature yes staging; sha=$(dev_sha_of REP-60)
record REP-60 Staging "$sha"; signoff REP-60 approved "$sha"; golive REP-60   # no marketing.md, no marketing row
unset_capability PIPELINE_HAS_MARKETING
out=$(gate REP-60 production); assert_exit "cap: key absent keeps today's marketing requirement" 1 $? "$out"
assert_contains "cap: key absent names marketing.md" "$out" "missing marketing.md"
set_capability PIPELINE_HAS_MARKETING '"no"'
out=$(gate REP-60 production); assert_exit "AC-1/AC-7: marketing=no + user-facing passes without marketing evidence" 0 $? "$out"
assert_contains "AC-1: PASS line shows marketing=off" "$out" "marketing=off"
assert_contains "AC-7: VERSION still printed" "$out" "VERSION=v1.0.0"
for v in '""' '"false"' '"0"' '"maybe"' '"Y"' '"off"' '"NO!"'; do
  set_capability PIPELINE_HAS_MARKETING "$v"
  out=$(gate REP-60 production); assert_exit "AC-2/AC-3: PIPELINE_HAS_MARKETING=$v resolves strict" 1 $? "$out"
  assert_contains "AC-2/AC-3: $v still demands marketing.md" "$out" "missing marketing.md"
done
set_capability PIPELINE_HAS_MARKETING '"  NO  "'
out=$(gate REP-60 production); assert_exit "AC-4: '  NO  ' trims and lowercases to no" 0 $? "$out"
set_capability_crlf PIPELINE_HAS_MARKETING no
out=$(gate REP-60 production); assert_exit "AC-4: 'no' written with a trailing CR resolves off" 0 $? "$out"
unset_capability PIPELINE_HAS_MARKETING
out=$(cd "$R" && PIPELINE_HAS_MARKETING=no bash scripts/pipeline/gate.sh REP-60 production 2>&1)
assert_exit "AC-5: the environment cannot relax a project that never set the key" 1 $? "$out"
assert_contains "AC-5: still demands marketing.md" "$out" "missing marketing.md"

# a project that declared no marketing function before it built: every other rule still applies (AC-8, AC-11)
new_repo; set_capability PIPELINE_HAS_MARKETING '"no"'
full_through REP-64 feature yes staging; sha=$(dev_sha_of REP-64)
for s in build dev qa staging; do
  out=$(gate REP-64 "$s"); assert_exit "AC-11: $s gate outcome unchanged with marketing off" 0 $? "$out"
done
record REP-64 Staging "$sha"; signoff REP-64 approved "$sha"; golive REP-64
out=$(gate REP-64 production); assert_exit "AC-7: marketing off, everything else satisfied, passes" 0 $? "$out"
add_ticket REP-64 REP-6402 defect staging Medium fixed; commit_all x
out=$(gate REP-64 production); assert_exit "AC-8: unverified defect still blocks with marketing off" 1 $? "$out"
set_ticket REP-64 REP-6402 verified; add_ticket REP-64 REP-6403 defect staging High wontfix; commit_all x
out=$(gate REP-64 production); assert_exit "AC-8: High-severity wontfix still blocks with marketing off" 1 $? "$out"
set_ticket REP-64 REP-6403 verified; commit_all x
rm "$(tdir REP-64)/signoff.md"; commit_all x
out=$(gate REP-64 production); assert_exit "AC-8: missing sign-off still blocks with marketing off" 1 $? "$out"
signoff REP-64 approved "$sha"
golive REP-64 "no-go (waiting)"
out=$(gate REP-64 production); assert_exit "AC-8: unapproved go-live still blocks with marketing off" 1 $? "$out"
golive REP-64 "approved by owner 2026-09-17" "1.2.3"
out=$(gate REP-64 production); assert_exit "AC-8: malformed version still blocks with marketing off" 1 $? "$out"
golive REP-64 "approved by owner 2026-09-17" "v1.2.3"
out=$(gate REP-64 production); assert_exit "AC-8: with everything else satisfied, marketing off passes again" 0 $? "$out"

# ---- backwards compatibility: a pipeline.env with none of the new keys (AC-12, release blocker) ----
new_repo; legacy_env
assert_eq "AC-12: the legacy fixture really carries neither new key" "0" "$(grep -c '^PIPELINE_HAS_' "$(env_file)")"
full_through REP-62 feature yes staging; sha=$(dev_sha_of REP-62)
for s in build dev qa staging; do
  out=$(gate REP-62 "$s"); assert_exit "AC-12: legacy env, user-facing, $s gate passes" 0 $? "$out"
done
record REP-62 Staging "$sha"; signoff REP-62 approved "$sha"; golive REP-62
out=$(gate REP-62 production); assert_exit "AC-12 anchor: legacy + user-facing + no marketing.md fails" 1 $? "$out"
assert_contains "AC-12 anchor: today's missing-file message" "$out" "missing marketing.md"
marketing REP-62 ready
out=$(gate REP-62 production); assert_exit "AC-12 anchor: legacy + ready marketing.md + no done row fails" 1 $? "$out"
assert_contains "AC-12 anchor: today's launch-ticket message" "$out" "no completed marketing launch ticket"
add_ticket REP-62 REP-6290 marketing - - done; commit_all x
out=$(gate REP-62 production); assert_exit "AC-12 anchor: legacy + full marketing evidence passes" 0 $? "$out"
assert_contains "AC-12: legacy resolves marketing on" "$out" "marketing=on"
assert_contains "AC-12: legacy resolves deploy-envs on" "$out" "deploy-envs=on"

new_repo; legacy_env; full_through REP-63 bugfix no staging; sha=$(dev_sha_of REP-63)
for s in build dev qa staging; do
  out=$(gate REP-63 "$s"); assert_exit "AC-12: legacy env, non-user-facing, $s gate passes" 0 $? "$out"
done
record REP-63 Staging "$sha"; signoff REP-63 approved "$sha"; golive REP-63
out=$(gate REP-63 production); assert_exit "AC-12 anchor: legacy + non-user-facing + no marketing evidence passes" 0 $? "$out"

# ---- ref mode ----
new_repo; m0=$(g rev-parse master); branch feature/REP-70-x; full_through REP-70 chore no production; g checkout -q "$m0" 2>/dev/null
out=$(gate REP-70 dev); assert_exit "ref: working tree without ticket folder fails" 1 $? "$out"
out=$(gate REP-70 dev feature/REP-70-x); assert_exit "ref: branch being merged passes dev" 0 $? "$out"; assert_contains "ref reported" "$out" "ref=feature/REP-70-x"
out=$(gate REP-70 production feature/REP-70-x); assert_exit "ref: production gate on branch" 0 $? "$out"
out=$(gate REP-70 dev no/such-ref); assert_exit "ref: unknown ref fails" 1 $? "$out"
out=$(cd "$R" && bash scripts/pipeline/check-signoff.sh REP-70 feature/REP-70-x 2>&1); assert_exit "check-signoff wrapper = production gate" 0 $? "$out"
out=$(gate REP-70 merge feature/REP-70-x); assert_exit "merge alias = production gate" 0 $? "$out"

summary
