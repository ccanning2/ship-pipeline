#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "tracker.sh write verbs: Linear, Jira and GitLab issues through fake CLIs"
# The GitHub Issues adapter is driven the same way in test_adapters.sh. Each fake logs what it was asked and answers
# like the real API, so these check the requests the adapters send, not only that they exit 0.
command -v jq >/dev/null 2>&1 || { echo "  (skipped: needs jq)"; summary; exit 0; }
new_repo
ST="$(mktemp -d)"; export ST
CF="$(mktemp -d)"; export PIPELINE_TRACKER_CONFIG="$CF"
trk() { (cd "$R" && bash scripts/pipeline/tracker.sh "$@" 2>&1); }
fake() { cat > "$ST/$1"; chmod +x "$ST/$1"; }
# last <log> <jq filter>: the filter applied to the last logged JSON request that matches it
last() { tac "$ST/$1" | while IFS= read -r l; do v="$(printf '%s' "$l" | jq -r "$2" 2>/dev/null)" && [ -n "$v" ] && [ "$v" != null ] && { printf '%s' "$v"; break; }; done; }

# ================================================================ Linear ====
use_tracker linear
export LINEAR_API_KEY=lin-key
fake curl-linear <<'FAKE'
#!/usr/bin/env bash
d=""; while [ $# -gt 0 ]; do case "$1" in --data) d="$2"; shift 2;; *) shift;; esac; done
printf '%s\n' "$d" >> "$ST/lin.log"
q="$(printf '%s' "$d" | jq -r .query)"
case "$q" in
  *"teams(filter"*) cat "$ST/lin.team";;
  *issueLabels*) cat "$ST/lin.labels";;
  *issueCreate*) echo '{"data":{"issueCreate":{"issue":{"identifier":"REP-43"}}}}';;
  *commentCreate*|*issueUpdate*) echo '{"data":{"r":{"success":true}}}';;
  *"issue(id:"*) cat "$ST/lin.issue";;
  *) echo '{"errors":[{"message":"unexpected query"}]}';;
esac
FAKE
export PIPELINE_CURL_CMD="$ST/curl-linear"
lin_team() { printf '{"data":{"teams":{"nodes":[{"id":"T1","name":"Ship","states":{"nodes":[%s]}}]}}}' "$1" > "$ST/lin.team"; }
all_states='{"id":"S-todo","name":"Todo","type":"unstarted"},{"id":"S-prog","name":"In Progress","type":"started"},{"id":"S-rev","name":"In Review","type":"started"},{"id":"S-done","name":"Done","type":"completed"},{"id":"S-can","name":"Canceled","type":"canceled"}'
lin_team "$all_states"
cat > "$ST/lin.labels" <<'J'
{"data":{"issueLabels":{"nodes":[
 {"id":"G-stage","name":"Stage","isGroup":true,"team":null,"parent":null},
 {"id":"G-owner","name":"Owner","isGroup":true,"team":null,"parent":null},
 {"id":"L-sp","name":"product","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-stage","name":"Stage"}},
 {"id":"L-sd","name":"dev","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-stage","name":"Stage"}},
 {"id":"L-sq","name":"qa","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-stage","name":"Stage"}},
 {"id":"L-opo","name":"product-owner","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-owner","name":"Owner"}},
 {"id":"L-oe","name":"engineer","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-owner","name":"Owner"}},
 {"id":"L-oq","name":"qa-tester","isGroup":false,"team":{"key":"REP"},"parent":{"id":"G-owner","name":"Owner"}},
 {"id":"L-eng","name":"eng","isGroup":false,"team":null,"parent":null},
 {"id":"L-other","name":"eng","isGroup":false,"team":{"key":"OPS"},"parent":null}]}}}
J
cat > "$ST/lin.issue" <<'J'
{"data":{"issue":{"id":"U7","identifier":"REP-7","title":"Health endpoint","description":"As an operator...","url":"https://linear.app/acme/issue/REP-7",
 "state":{"name":"Todo"},
 "labels":{"nodes":[{"id":"L-sp","name":"product","parent":{"name":"Stage"}},{"id":"L-opo","name":"product-owner","parent":{"name":"Owner"}},{"id":"L-x","name":"backend","parent":null}]},
 "children":{"nodes":[{"identifier":"REP-8","title":"health route","state":{"name":"In Progress"},"labels":{"nodes":[{"name":"eng","parent":null},{"name":"dev","parent":{"name":"Stage"}}]}}]},
 "comments":{"nodes":[{"body":"Looks good","createdAt":"2026-10-01T10:00:00Z","user":{"name":"Pat"}}]}}}}
J
out=$(trk check); assert_exit "linear: check" 0 $? "$out"; assert_contains "linear: check names the team" "$out" "Linear team Ship (REP)"
out=$(trk view REP-7); assert_exit "linear: view" 0 $? "$out"
for s in "Stage: product" "Owner: product-owner" "Labels: product, product-owner, backend" "Pat: Looks good" "REP-8 | eng | In Progress | health route"; do assert_contains "linear: view shows '$s'" "$out" "$s"; done
out=$(trk children REP-7); assert_eq "linear: children lists kind, state and title (no group labels)" "REP-8 | eng | In Progress | health route" "$out"

: > "$ST/lin.log"
out=$(trk set REP-7 stage=dev); assert_exit "linear: set Stage" 0 $? "$out"
assert_eq "linear: set swaps only the Stage label and keeps the rest" '["L-opo","L-x","L-sd"]' "$(last lin.log 'select(.query|test("issueUpdate")) | .variables.l | tostring')"
assert_eq "linear: on the issue's uuid" "U7" "$(last lin.log 'select(.query|test("issueUpdate")) | .variables.i')"

: > "$ST/lin.log"
out=$(trk handoff REP-7 qa qa-tester --body 'Handoff: engineer → qa'); assert_exit "linear: handoff" 0 $? "$out"
assert_contains "linear: handoff reports the move" "$out" "handoff: REP-7 -> Stage qa, Owner qa-tester"
assert_eq "linear: handoff sets the Owner label" '["L-sp","L-x","L-oq"]' "$(last lin.log 'select(.query|test("issueUpdate")) | .variables.l | tostring')"
assert_eq "linear: and posts the comment" "Handoff: engineer → qa" "$(last lin.log 'select(.query|test("commentCreate")) | .variables.b')"
assert_eq "linear: the labels are read once per call" 1 "$(grep -c issueLabels "$ST/lin.log")"

: > "$ST/lin.log"
out=$(trk create REP-7 eng 'Health route' --body 'FR-1, AC-1'); assert_exit "linear: create a child" 0 $? "$out"
assert_eq "linear: create prints the new id" "REP-43" "$out"
assert_eq "linear: the child has the team, parent, title, body and the team's kind label" "T1|U7|Health route|FR-1, AC-1|L-eng" \
  "$(last lin.log 'select(.query|test("issueCreate")) | .variables | "\(.t)|\(.p)|\(.ti)|\(.d)|\(.l)"')"
out=$(trk create REP-7 defect 'x' --body 'y'); assert_exit "linear: a kind label that does not exist yet is an error" 1 $? "$out"
assert_contains "linear: and says to run setup" "$out" "Linear has no 'defect' label (bash scripts/pipeline/tracker.sh setup)"

: > "$ST/lin.log"
out=$(trk describe REP-7 --body 'New description'); assert_exit "linear: describe" 0 $? "$out"
assert_eq "linear: describe replaces the description" "U7|New description" "$(last lin.log 'select(.query|test("description:")) | .variables | "\(.i)|\(.d)"')"
out=$(trk state REP-7 fixed); assert_exit "linear: state fixed" 0 $? "$out"
assert_eq "linear: fixed is the In Review status" "S-rev" "$(last lin.log 'select(.query|test("stateId")) | .variables.s')"
printf 'state:fixed|Code Review\n' > "$R/scripts/pipeline/tracker.map"
lin_team "$all_states"',{"id":"S-cr","name":"Code Review","type":"started"}'
out=$(trk state REP-7 fixed); assert_exit "linear: state through tracker.map" 0 $? "$out"
assert_eq "linear: tracker.map renames the status" "S-cr" "$(last lin.log 'select(.query|test("stateId")) | .variables.s')"
rm -f "$R/scripts/pipeline/tracker.map"; lin_team '{"id":"S-todo","name":"Todo","type":"unstarted"}'
out=$(trk state REP-7 wontfix); assert_exit "linear: a status the team lacks is an error" 1 $? "$out"
assert_contains "linear: and names it" "$out" "the Linear team has no status 'Canceled'"
lin_team "$all_states"
cp "$ST/lin.issue" "$ST/lin.issue.ok"; echo '{"errors":[{"message":"Entity not found"}]}' > "$ST/lin.issue"
out=$(trk comment REP-7 --body 'x'); assert_exit "linear: an API error is an error" 1 $? "$out"
assert_contains "linear: with Linear's message" "$out" "Linear: Entity not found"
mv "$ST/lin.issue.ok" "$ST/lin.issue"
unset LINEAR_API_KEY PIPELINE_CURL_CMD

# ================================================================ Jira ====
use_tracker jira; set_capability TRACKER_URL '"https://acme.atlassian.net"'
export JIRA_API_TOKEN=jira-token JIRA_EMAIL=me@example.com
fake curl-jira <<'FAKE'
#!/usr/bin/env bash
m=GET u="" d=""; while [ $# -gt 0 ]; do case "$1" in -X) m="$2"; shift 2;; --data) d="$2"; shift 2;; -u|-H) shift 2;; http*) u="$1"; shift;; *) shift;; esac; done
p="${u#*/rest/api/3/}"; printf '%s\t%s\t%s\n' "$m" "$p" "$d" >> "$ST/jira.log"
case "$m $p" in
  "GET project/REP") echo '{"id":"10000","key":"REP"}';;
  "GET issue/REP-7?fields=labels") echo '{"fields":{"labels":["stage:product","owner:product-owner","backend"]}}';;
  "GET issue/REP-7?"*) cat "$ST/jira.issue";;
  "PUT issue/"*) ;;
  *) echo "fake-curl: unexpected $m $p" >&2; exit 22;;
esac
FAKE
fake acli <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ST/acli.log"
f=""; prev=""; for a in "$@"; do [ "$prev" = --description-file ] || [ "$prev" = --body-file ] && f="$a"; prev="$a"; done
[ -n "$f" ] && cat "$f" > "$ST/acli.body"
case "$2 $3" in
  "auth status") exit 0;;
  "workitem create") echo '{"key":"REP-44"}';;
  "workitem comment") ;;
  "workitem search") echo '{"issues":[{"key":"REP-9","fields":{"summary":"sub","status":{"name":"To Do"},"labels":["eng","stage:dev"]}}]}';;
  "workitem transition") [ -f "$ST/acli.no-transition" ] && { echo "no transition" >&2; exit 1; }; exit 0;;
  *) echo "fake-acli: unexpected $*" >&2; exit 1;;
esac
FAKE
export PIPELINE_CURL_CMD="$ST/curl-jira" PIPELINE_ACLI_CMD="$ST/acli"
cat > "$ST/jira.issue" <<'J'
{"key":"REP-7","fields":{"summary":"Health endpoint","status":{"name":"To Do"},"labels":["stage:product","owner:product-owner","backend"],
 "description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"As an operator"}]}]},
 "comment":{"comments":[{"created":"2026-10-01","author":{"displayName":"Pat"},"body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Looks good"}]}]}}]}}}
J
out=$(trk check); assert_exit "jira: check" 0 $? "$out"; assert_contains "jira: check names the project and site" "$out" "Jira project REP at https://acme.atlassian.net"
out=$(trk view REP-7); assert_exit "jira: view" 0 $? "$out"
for s in "Stage: product" "Owner: product-owner" "As an operator" "Pat: Looks good" "REP-9 | eng | To Do | sub" "URL: https://acme.atlassian.net/browse/REP-7"; do assert_contains "jira: view shows '$s'" "$out" "$s"; done

: > "$ST/jira.log"
out=$(trk set REP-7 stage=dev); assert_exit "jira: set Stage (labels mode)" 0 $? "$out"
put="$(awk -F'\t' '$1=="PUT" {d=$3} END {print d}' "$ST/jira.log")"
assert_eq "jira: labels mode removes the old stage label and adds the new one" '[{"remove":"stage:product"},{"add":"stage:dev"}]' "$(printf '%s' "$put" | jq -c .update.labels)"
printf 'jira:groups|fields\njira:field:Stage|customfield_100\njira:field:Owner|customfield_101\n' > "$R/scripts/pipeline/tracker.map"
: > "$ST/jira.log"
out=$(trk set REP-7 owner=engineer); assert_exit "jira: set Owner (fields mode)" 0 $? "$out"
put="$(awk -F'\t' '$1=="PUT" {d=$3} END {print d}' "$ST/jira.log")"
assert_eq "jira: fields mode sets the single-select field" '{"fields":{"customfield_101":{"value":"engineer"}}}' "$put"

: > "$ST/acli.log"
out=$(trk create REP-7 eng 'Health route' --body 'FR-1, AC-1'); assert_exit "jira: create a child" 0 $? "$out"
assert_eq "jira: create prints the new key" "REP-44" "$out"
assert_contains "jira: as a sub-task of the parent with its kind label" "$(cat "$ST/acli.log")" "--type Subtask --parent REP-7 --summary Health route"
assert_contains "jira: with the kind label" "$(cat "$ST/acli.log")" "--label eng"
assert_eq "jira: the body goes through a file" "FR-1, AC-1" "$(cat "$ST/acli.body")"
printf 'jira:subtask-type|Sub-task\n' >> "$R/scripts/pipeline/tracker.map"
out=$(trk create REP-7 eng 'x' --body 'y'); assert_contains "jira: the sub-task type comes from tracker.map" "$(tail -1 "$ST/acli.log")" "--type Sub-task"
out=$(trk comment REP-7 --body 'line one

line two'); assert_exit "jira: comment" 0 $? "$out"
assert_contains "jira: comment on the right key" "$(tail -1 "$ST/acli.log")" "workitem comment create --key REP-7"
assert_eq "jira: the comment keeps its paragraphs" "line one

line two" "$(cat "$ST/acli.body")"
: > "$ST/jira.log"
out=$(trk describe REP-7 --body 'First

Second'); assert_exit "jira: describe" 0 $? "$out"
put="$(awk -F'\t' '$1=="PUT" {d=$3} END {print d}' "$ST/jira.log")"
assert_eq "jira: describe sends ADF, one paragraph per block" '["First","Second"]' "$(printf '%s' "$put" | jq -c '[.fields.description.content[].content[0].text]')"
out=$(trk state REP-7 fixed); assert_exit "jira: state fixed" 0 $? "$out"
assert_contains "jira: fixed transitions to In Review" "$(tail -1 "$ST/acli.log")" "workitem transition --key REP-7 --status In Review --yes"
printf 'state:fixed|Code Review\n' >> "$R/scripts/pipeline/tracker.map"
out=$(trk state REP-7 fixed); assert_contains "jira: tracker.map renames the status" "$(tail -1 "$ST/acli.log")" "--status Code Review"
touch "$ST/acli.no-transition"
out=$(trk state REP-7 done); assert_exit "jira: a refused transition is an error" 1 $? "$out"
assert_contains "jira: and names the status" "$out" "Jira has no transition to 'Done' for REP-7"
rm -f "$ST/acli.no-transition" "$R/scripts/pipeline/tracker.map"
unset JIRA_API_TOKEN JIRA_EMAIL PIPELINE_CURL_CMD PIPELINE_ACLI_CMD

# ================================================================ GitLab issues ====
use_tracker gitlab
fake glab <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ST/glab.log"
[ "$1" = auth ] && exit 0
shift   # api
m=GET; [ "$1" = -X ] && { m="$2"; shift 2; }
case "$m $1" in
  "GET projects/:id") echo '{"id":99,"path_with_namespace":"grp/proj"}';;
  "GET projects/:id/issues/7") echo '{"iid":7,"title":"Health endpoint","state":"opened","labels":["Stage::product","Owner::product-owner","backend","state::in-progress"],"web_url":"https://gitlab.com/grp/proj/-/issues/7","description":"As an operator"}';;
  "GET projects/:id/issues/7/notes"*) echo '[{"system":false,"created_at":"2026-10-01","author":{"username":"pat"},"body":"Looks good"},{"system":true,"created_at":"x","author":{"username":"bot"},"body":"changed label"}]';;
  "GET projects/:id/issues/7/links") echo '[{"iid":45,"title":"health route","state":"opened","labels":["eng","state::fixed"],"description":"Parent: REP-7\n\nFR-1"},{"iid":3,"title":"related","state":"opened","labels":[],"description":"something else"}]';;
  "POST projects/:id/issues") echo '{"iid":45}';;
  "POST projects/:id/issues/7/links"|"POST projects/:id/issues/7/notes"|"PUT projects/:id/issues/7") ;;
  *) echo "fake-glab: unexpected $m $1" >&2; exit 1;;
esac
FAKE
export PIPELINE_GLAB_CMD="$ST/glab"
out=$(trk check); assert_exit "gitlab: check" 0 $? "$out"; assert_contains "gitlab: check names the project" "$out" "GitLab issues of grp/proj"
out=$(trk view REP-7); assert_exit "gitlab: view" 0 $? "$out"
for s in "Stage: product" "Owner: product-owner" "pat: Looks good" "REP-45 | eng | opened fixed | health route"; do assert_contains "gitlab: view shows '$s'" "$out" "$s"; done
case "$out" in *"changed label"*) bad "gitlab: view leaves out system notes" "$out";; *) ok "gitlab: view leaves out system notes";; esac
out=$(trk children REP-7); assert_eq "gitlab: children are only the linked issues that name this parent" "REP-45 | eng | opened fixed | health route" "$out"
: > "$ST/glab.log"
out=$(trk set REP-7 stage=dev); assert_exit "gitlab: set Stage" 0 $? "$out"
assert_contains "gitlab: set adds the new scoped label and removes the old one" "$(tail -1 "$ST/glab.log")" "-X PUT projects/:id/issues/7 -f add_labels=Stage::dev -f remove_labels=Stage::product"
out=$(trk state REP-7 fixed); assert_contains "gitlab: fixed keeps the issue open and swaps the state label" "$(tail -1 "$ST/glab.log")" "-f state_event=reopen -f add_labels=state::fixed -f remove_labels=state::in-progress"
out=$(trk state REP-7 done); assert_contains "gitlab: done closes the issue and drops the state label" "$(tail -1 "$ST/glab.log")" "-f state_event=close -f remove_labels=state::in-progress"
out=$(trk state REP-7 wontfix); assert_contains "gitlab: wontfix closes it with a wontfix label" "$(tail -1 "$ST/glab.log")" "-f state_event=close -f add_labels=state::wontfix"
: > "$ST/glab.log"
out=$(trk create REP-7 eng 'Health route' --body 'FR-1'); assert_exit "gitlab: create a child" 0 $? "$out"
assert_eq "gitlab: create prints the new id" "REP-45" "$out"
assert_contains "gitlab: the child names its parent and carries its kind label" "$(cat "$ST/glab.log")" "-X POST projects/:id/issues -f title=Health route -f description=Parent: REP-7"
assert_contains "gitlab: with the kind label" "$(cat "$ST/glab.log")" "-f labels=eng"
assert_contains "gitlab: and is linked to the parent" "$(cat "$ST/glab.log")" "-X POST projects/:id/issues/7/links -f target_project_id=99 -f target_issue_iid=45"
out=$(trk handoff REP-7 qa qa-tester --body 'Handoff: engineer → qa'); assert_exit "gitlab: handoff" 0 $? "$out"
assert_contains "gitlab: handoff posts the comment" "$(tail -1 "$ST/glab.log")" "-X POST projects/:id/issues/7/notes -f body=Handoff: engineer → qa"
unset PIPELINE_GLAB_CMD

summary
