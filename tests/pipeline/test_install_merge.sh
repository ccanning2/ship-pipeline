#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "install-merge.sh (the install route: push, open, pinned merge, refusal, cleanup)"
[ "$INIT_MODE" = init ] || { echo "  (skipped: not running from the plugin repo)"; summary; exit 0; }
export PIPELINE_PLUGIN_ROOT="$REPO_SRC" PIPELINE_WAIT_TRIES=1
FK="$(mktemp -d)"; export FK
# One fake per host. Each logs every call, keeps "is a request open" in $FK/open, answers the source commit from
# $FK/src, and on a merge moves the remote trunk to the merged sha ($FK/refuse makes it refuse instead).
mkdir -p "$FK/bin"
cat > "$FK/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >> "$FK/log"
case "$*" in
  "repo view"*) echo o/r;;
  "api repos/o/r/pulls?head="*) [ -f "$FK/open" ] && echo "5 https://github.com/o/r/pull/5"; exit 0;;
  "api -X POST repos/o/r/pulls "*) touch "$FK/open"; echo "5 https://github.com/o/r/pull/5";;
  "api repos/o/r/branches/"*) exec bash "$FK/bin/tip" "%s";;
  "api repos/o/r/pulls/5 "*) echo "$(cat "$FK/src") ready $(cat "$FK/target" 2>/dev/null || echo master)";;
  "api -X PUT repos/o/r/pulls/5/merge"*)
    [ -f "$FK/refuse" ] && { echo 'gh: Required status check "gate" is expected. (HTTP 405)' >&2; exit 1; }
    for a in "$@"; do case "$a" in sha=*) git -C "$ORIGIN" update-ref refs/heads/master "${a#sha=}";; esac; done;;
  *) echo "fake gh: unexpected: $*" >&2; exit 1;;
esac
FAKE
cat > "$FK/bin/glab" <<'FAKE'
#!/usr/bin/env bash
echo "glab $*" >> "$FK/log"
case "$*" in
  "api projects/"*"/merge_requests?state=opened"*) if [ -f "$FK/open" ]; then echo '[{"iid":7,"web_url":"https://gitlab.com/g/p/-/merge_requests/7"}]'; else echo '[]'; fi;;
  "api -X POST projects/"*"/merge_requests "*) touch "$FK/open"; echo '{"iid":7,"web_url":"https://gitlab.com/g/p/-/merge_requests/7"}';;
  "api projects/"*"/repository/branches/"*) exec bash "$FK/bin/tip" '{"commit":{"id":"%s"}}';;
  "api projects/"*"/merge_requests/7") printf '{"sha":"%s","detailed_merge_status":"mergeable","target_branch":"%s"}\n' "$(cat "$FK/src")" "$(cat "$FK/target" 2>/dev/null || echo master)";;
  "api -X PUT projects/"*"/merge_requests/7/merge"*)
    [ -f "$FK/refuse" ] && { echo 'glab: 405 Method Not Allowed' >&2; exit 1; }
    for a in "$@"; do case "$a" in sha=*) git -C "$ORIGIN" update-ref refs/heads/master "${a#sha=}";; esac; done; echo '{}';;
  *) echo "fake glab: unexpected: $*" >&2; exit 1;;
esac
FAKE
cat > "$FK/bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "curl $*" >> "$FK/log"
case "$*" in
  *"-X GET "*"/pullrequests?state=OPEN"*) if [ -f "$FK/open" ]; then echo '{"values":[{"id":3,"links":{"html":{"href":"https://bitbucket.org/w/r/pull-requests/3"}}}]}'; else echo '{"values":[]}'; fi;;
  *"-X POST "*"/pullrequests "*) touch "$FK/open"; echo '{"id":3,"links":{"html":{"href":"https://bitbucket.org/w/r/pull-requests/3"}}}';;
  *"-X GET "*"/refs/branches/"*) exec bash "$FK/bin/tip" '{"target":{"hash":"%s"}}';;
  *"-X GET "*"/pullrequests/3") printf '{"source":{"commit":{"hash":"%s"}},"destination":{"branch":{"name":"%s"}}}\n' "$(cut -c1-12 "$FK/src")" "$(cat "$FK/target" 2>/dev/null || echo master)";;
  *"-X POST "*"/pullrequests/3/merge"*)
    [ -f "$FK/refuse" ] && { echo 'curl: (22) The requested URL returned error: 400' >&2; exit 22; }
    git -C "$ORIGIN" update-ref refs/heads/master "$(cat "$FK/merge-to")"; echo '{}';;
  *) echo "fake curl: unexpected: $*" >&2; exit 22;;
esac
FAKE
# The trunk head every fake reports (host.sh branch-head): the bare origin's master, unless a case sets $FK/tip (every
# read), $FK/tip2 (the second read on: the trunk moved) or $FK/tipfail (the read fails with that text). $FK/tipn counts.
cat > "$FK/bin/tip" <<'FAKE'
#!/usr/bin/env bash
n=$(( $(cat "$FK/tipn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FK/tipn"
[ -f "$FK/tipfail" ] && { cat "$FK/tipfail" >&2; exit 1; }
if [ "$n" -ge 2 ] && [ -f "$FK/tip2" ]; then s="$(cat "$FK/tip2")"
elif [ -f "$FK/tip" ]; then s="$(cat "$FK/tip")"
else s="$(git -C "$ORIGIN" rev-parse refs/heads/master)"; fi
printf "$1\n" "$s"
FAKE
chmod +x "$FK/bin/"*
export PIPELINE_GH_CMD="$FK/bin/gh" PIPELINE_GLAB_CMD="$FK/bin/glab" PIPELINE_CURL_CMD="$FK/bin/curl" BITBUCKET_API_TOKEN=x BITBUCKET_EMAIL=a@b.c
fresh() { # [init flags]: a new fixture on the install branch, and a clean fake host
  rm -f "$FK/log" "$FK/open" "$FK/refuse"; : > "$FK/log"
  rm -f "$FK/tip" "$FK/tip2" "$FK/tipn" "$FK/tipfail" "$FK/target"
  origin_repo; export ORIGIN; install_branch "$@"; g rev-parse HEAD > "$FK/src"; g rev-parse HEAD > "$FK/merge-to"
}
route() { (cd "$R" && bash scripts/pipeline/install-merge.sh "$@" 2>&1); }
# every logged host call that is not part of reading the trunk head (gh resolves the repository with 'repo view')
host_calls_but_tip() { grep -vE '^gh repo view|/branches/' "$FK/log" || true; }
pushed() { git -C "$ORIGIN" rev-parse -q --verify refs/heads/ship-pipeline/install >/dev/null 2>&1 && echo yes || echo no; }
forbidden() { grep -E 'protection|rulesets|protected_branches|branch-restrictions|labels|--admin|bypass|staging|refs/tags|--force' "$FK/log" || true; }

# ---- AC-31, AC-39: GitHub, the whole way ----
fresh; sha="$(g rev-parse HEAD)"
out=$(route); assert_exit "AC-31: github: merged" 0 $? "$out"
assert_contains "AC-31: prints MERGED and the request" "$out" "MERGED https://github.com/o/r/pull/5"
assert_eq "AC-31: the install branch was pushed (not forced) and then deleted" "no" "$(git -C "$ORIGIN" rev-parse -q --verify refs/heads/ship-pipeline/install >/dev/null && echo yes || echo no)"
assert_contains "AC-31: the request is from the install branch into master" "$(cat "$FK/log")" "-f head=ship-pipeline/install -f base=master"
assert_contains "AC-31: with the first-install title" "$(cat "$FK/log")" "-f title=chore: install ship pipeline"
assert_contains "AC-31: and the body says there was no human review" "$(cat "$FK/log")" "without a human review"
assert_contains "AC-31: the merge is pinned to the install commit" "$(cat "$FK/log")" "pulls/5/merge -f merge_method=merge -f sha=$sha"
assert_eq "AC-31: exactly one merge call" 1 "$(grep -c 'pulls/5/merge' "$FK/log")"
assert_eq "AC-35/AC-41: no protection, ruleset, label, admin, staging, tag or force call" "" "$(forbidden)"
assert_eq "AC-39: the working tree is on master" master "$(g symbolic-ref --short HEAD)"
assert_eq "AC-39: at the remote trunk" "$(git -C "$ORIGIN" rev-parse master)" "$(g rev-parse HEAD)"
assert_eq "AC-39: the remote trunk has the install" "$sha" "$(git -C "$ORIGIN" rev-parse master)"
assert_eq "AC-39: the local install branch is gone" "no" "$(g rev-parse -q --verify refs/heads/ship-pipeline/install >/dev/null && echo yes || echo no)"
: > "$FK/log"
out=$(route); assert_exit "AC-42: a second run exits 1" 1 $? "$out"; assert_contains "AC-42: nothing to merge" "$out" "nothing to merge"
assert_eq "AC-42: and calls no host" "" "$(cat "$FK/log")"

# ---- AC-33, AC-34: an open request is reused; an upgrade has its own title ----
fresh; touch "$FK/open"
out=$(route); assert_exit "AC-33: merged through the open request" 0 $? "$out"
grep -q -- "-X POST repos/o/r/pulls " "$FK/log" && bad "AC-33: no second request is opened" "$(cat "$FK/log")" || ok "AC-33: no second request is opened"
ver="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_SRC/.claude-plugin/plugin.json")"
rm -f "$FK/open"; : > "$FK/log"
origin_repo; export ORIGIN; bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name demo --team-key REP --base-branch master --staging-branch staging >/dev/null
echo "# old" > "$R/scripts/pipeline/gate.sh"; commit_all "older install"; g push -q origin master; g fetch -q origin
install_branch; g rev-parse HEAD > "$FK/src"
out=$(route); assert_exit "AC-34: an upgrade is merged" 0 $? "$out"
assert_contains "AC-34: with the upgrade title" "$(cat "$FK/log")" "-f title=chore: update ship pipeline to v$ver"

# ---- AC-35: a refusal is final, reported once, and changes nothing on the host ----
fresh; touch "$FK/refuse"
out=$(route); assert_exit "AC-35: github refusal exits 3" 3 $? "$out"
assert_eq "AC-35: exactly one REFUSED line" 1 "$(printf '%s\n' "$out" | grep -c '^REFUSED ')"
assert_contains "AC-35: with the request and the host's reason" "$out" 'REFUSED https://github.com/o/r/pull/5 GitHub refused to merge PR #5: Required status check "gate" is expected. (HTTP 405)'
assert_eq "AC-35: one merge call, never retried" 1 "$(grep -c 'pulls/5/merge' "$FK/log")"
assert_eq "AC-35: no protection, ruleset, label, admin or bypass call" "" "$(forbidden)"
assert_eq "AC-35: the working tree stays on the install branch" ship-pipeline/install "$(g symbolic-ref --short HEAD)"

# ---- AC-37: a rejected push stops everything ----
fresh; printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
out=$(route); assert_exit "AC-37: a rejected push exits 3" 3 $? "$out"; assert_contains "AC-37: REFUSED, naming the push" "$out" "the push of ship-pipeline/install was rejected"
grep -qE 'pulls|merge' "$FK/log" && bad "AC-37: no request and no merge call after a rejected push" "$(cat "$FK/log")" || ok "AC-37: no request and no merge call after a rejected push"

# ---- AC-38: not the install: refused before any push or host call ----
fresh; echo x > "$R/src/app.js"; commit_all "app"
out=$(route); assert_exit "AC-38: exit 4" 4 $? "$out"; assert_contains "AC-38: NOT-INSTALL names the file" "$out" "NOT-INSTALL src/app.js: src/app.js is not part of the install"
assert_eq "AC-38: the only host calls are the trunk-head read" "" "$(host_calls_but_tip)"
assert_eq "AC-38: nothing pushed" "no" "$(git -C "$ORIGIN" rev-parse -q --verify refs/heads/ship-pipeline/install >/dev/null && echo yes || echo no)"
out=$(env -u PIPELINE_PLUGIN_ROOT bash -c "cd '$R' && bash scripts/pipeline/install-merge.sh" 2>&1); assert_exit "no plugin copy: exit 4" 4 $? "$out"
assert_contains "no plugin copy: says so" "$out" "the plugin's installed copy could not be found"

# ---- AC-39: a failed delete is only a note ----
fresh; printf '#!/bin/sh\nwhile read o n r; do case "$n" in 0000000000000000000000000000000000000000) exit 1;; esac; done\nexit 0\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
out=$(route); assert_exit "AC-39: merged although the branch could not be deleted" 0 $? "$out"
assert_contains "AC-39: a NOTE says so" "$out" "NOTE could not delete ship-pipeline/install on origin"

# ---- AC-40: --open-only never merges ----
fresh
out=$(route --open-only); assert_exit "AC-40: --open-only exits 0" 0 $? "$out"; assert_eq "AC-40: prints OPENED" "OPENED https://github.com/o/r/pull/5" "$out"
grep -q '/merge' "$FK/log" && bad "AC-40: no merge call" "$(cat "$FK/log")" || ok "AC-40: no merge call"
assert_eq "AC-40: the install branch is on the remote" "$(g rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse refs/heads/ship-pipeline/install)"

# ---- AC-41, FR-1, FR-2: two forms only; the install branch only ----
for a in "--force" "master" "--open-only x" "--merge"; do
  : > "$FK/log"; out=$(route $a); assert_exit "AC-41: '$a' is a usage error" 1 $? "$out"; assert_eq "AC-41: '$a' calls nothing" "" "$(cat "$FK/log")"
done
g checkout -q -b chore/install; : > "$FK/log"
out=$(route); assert_exit "FR-2: another branch is refused" 1 $? "$out"; assert_contains "FR-2: and named" "$out" "not 'ship-pipeline/install'"
assert_eq "FR-2: before any call" "" "$(cat "$FK/log")"

# ---- AC-32, AC-35, AC-36: GitLab and Bitbucket ----
if command -v jq >/dev/null 2>&1; then
  fresh --git-host gitlab; sha="$(g rev-parse HEAD)"
  out=$(route); assert_exit "AC-32: gitlab: merged" 0 $? "$out"; assert_contains "AC-32: gitlab: MERGED" "$out" "MERGED https://gitlab.com/g/p/-/merge_requests/7"
  assert_contains "AC-32: gitlab: the MR merge is pinned to the sha" "$(cat "$FK/log")" "merge_requests/7/merge -f sha=$sha"
  assert_eq "AC-32: gitlab: the trunk has the install" "$sha" "$(git -C "$ORIGIN" rev-parse master)"
  assert_eq "AC-41: gitlab: no forbidden call" "" "$(forbidden)"
  fresh --git-host gitlab; touch "$FK/refuse"
  out=$(route); assert_exit "AC-35: gitlab refusal exits 3" 3 $? "$out"; assert_contains "AC-35: gitlab: the reason" "$out" "REFUSED https://gitlab.com/g/p/-/merge_requests/7 GitLab refused to merge !7: 405 Method Not Allowed"
  assert_eq "AC-35: gitlab: one merge call" 1 "$(grep -c 'merge_requests/7/merge' "$FK/log")"; assert_eq "AC-35: gitlab: nothing forbidden" "" "$(forbidden)"
  fresh --git-host bitbucket; sha="$(g rev-parse HEAD)"
  out=$(route); assert_exit "AC-32: bitbucket: merged" 0 $? "$out"; assert_contains "AC-32: bitbucket: MERGED" "$out" "MERGED https://bitbucket.org/w/r/pull-requests/3"
  l_info=$(grep -n -- '-X GET .*/pullrequests/3$' "$FK/log" | head -n1 | cut -d: -f1); l_merge=$(grep -n '/pullrequests/3/merge' "$FK/log" | head -n1 | cut -d: -f1)
  [ -n "$l_info" ] && [ -n "$l_merge" ] && [ "$l_info" -lt "$l_merge" ] && ok "AC-32: bitbucket: the source commit is re-read before the merge" || bad "AC-32: bitbucket: the source commit is re-read before the merge" "$(cat "$FK/log")"
  assert_eq "AC-41: bitbucket: nothing forbidden" "" "$(forbidden)"
  fresh --git-host bitbucket; touch "$FK/refuse"
  out=$(route); assert_exit "AC-35: bitbucket refusal exits 3" 3 $? "$out"; assert_contains "AC-35: bitbucket: the reason" "$out" "REFUSED https://bitbucket.org/w/r/pull-requests/3 Bitbucket refused to merge PR #3"
  assert_eq "AC-35: bitbucket: one merge call" 1 "$(grep -c 'pullrequests/3/merge' "$FK/log")"
  fresh --git-host bitbucket; echo 0123456789abcdef0123456789abcdef01234567 > "$FK/src"
  out=$(route); assert_exit "AC-36: bitbucket: another source commit exits 3" 3 $? "$out"; assert_contains "AC-36: and says so" "$out" "not the install commit"
  grep -q 'pullrequests/3/merge' "$FK/log" && bad "AC-36: no merge call" "$(cat "$FK/log")" || ok "AC-36: no merge call"
fi
# a GitHub request that no longer carries the install commit is not merged either
fresh; echo 0123456789abcdef0123456789abcdef01234567 > "$FK/src"
out=$(route); assert_exit "FR-7: github: another source commit exits 3" 3 $? "$out"
grep -q '/merge' "$FK/log" && bad "FR-7: github: no merge call" || ok "FR-7: github: no merge call"

# ==== SHI-55: the route anchors its proof to the trunk as the host reports it (FR-17, FR-18) ====
ENVF=scripts/pipeline/pipeline.env; MK="$(mktemp -d)/marker"
hosts=github; command -v jq >/dev/null 2>&1 && hosts="github gitlab bitbucket"
ghook() { # the guard hook on <command>, with the reference in the hook's own environment
  local json; json=$($PY -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1")
  (cd "$R" && printf '%s' "$json" | PIPELINE_PLUGIN_ROOT="$REPO_SRC" CLAUDE_PROJECT_DIR="$R" bash scripts/pipeline/hooks/guard-merge.sh 2>&1)
}
requests() { grep -E 'pulls|merge_requests|pullrequests' "$FK/log" || true; }   # any request call (open, read, merge)
rearm() { # the same fixture again, with a clean fake host and no install branch on the remote
  git -C "$ORIGIN" update-ref -d refs/heads/ship-pipeline/install 2>/dev/null
  rm -f "$FK/open" "$FK/refuse" "$FK/tip" "$FK/tip2" "$FK/tipn" "$FK/tipfail" "$FK/target"; : > "$FK/log"
}
rewind() { # <install commit>: undo a merge: the remote trunk back at A0, the install branch checked out again
  git -C "$ORIGIN" update-ref refs/heads/master "$A0"; rearm
  g checkout -q -f -B ship-pipeline/install "$1"; g update-ref refs/heads/master "$A0"; g update-ref refs/remotes/origin/master "$A0"
}
fixture() { fresh "$@"; A0="$(git -C "$ORIGIN" rev-parse master)"; }
put_line() { L="$2" awk -v k="$1" 'index($0, k "=") == 1 && !d { print ENVIRON["L"]; d = 1; next } { print }' "$ENVF" > "$ENVF.t" && mv "$ENVF.t" "$ENVF"; }
add_line() { printf '%s\n' "$@" >> "$ENVF"; }
# env_route <label> <exit> <text or ""> <command and args, run in $R>: the change reaches the COMMITTED pipeline.env
# only (the working tree stays as rendered, NFR-6); the route is run directly. A refusal (4) must come before any push
# or request call; a merge (0) is undone afterwards
env_route() {
  local at l="$1" x="$2" t="$3"; shift 3; at="$(g rev-parse HEAD)"
  (cd "$R" && "$@"); g add -A; g commit -qm env --allow-empty; g rev-parse HEAD > "$FK/src"; g rev-parse HEAD > "$FK/merge-to"
  g show "$at:$ENVF" > "$R/$ENVF"; rearm
  out=$(route); assert_exit "$l" "$x" $? "$out"; [ -z "$t" ] || assert_contains "$l: says why" "$out" "$t"
  if [ "$x" = 4 ]; then
    assert_eq "$l: the trunk-head read is the only host call" "" "$(host_calls_but_tip)"; assert_eq "$l: nothing pushed" no "$(pushed)"
  fi
  rewind "$at"
}
# evil_fixture [init flags]: the SHI-55 repro. The bare origin's master is A; a branch evil from A adds
# src/Backdoor.java; origin/master is forged to evil (git update-ref); the install is committed on top of evil
evil_fixture() {
  rm -f "$FK/open" "$FK/refuse" "$FK/tip" "$FK/tip2" "$FK/tipn" "$FK/tipfail" "$FK/target"; : > "$FK/log"
  origin_repo; export ORIGIN; A0="$(g rev-parse HEAD)"
  g checkout -q -b evil; echo "class Backdoor {}" > "$R/src/Backdoor.java"; commit_all "evil"; g checkout -q master
  g update-ref refs/remotes/origin/master evil
  install_branch "$@"; g rev-parse HEAD > "$FK/src"; g rev-parse HEAD > "$FK/merge-to"
}
evil_refused() { # <label> <route output> <route exit>
  assert_exit "$1: exit 4" 4 "$3" "$2"
  assert_contains "$1: NOT-INSTALL names the backdoor" "$2" "NOT-INSTALL src/Backdoor.java: src/Backdoor.java is not part of the install"
  assert_eq "$1: the trunk-head read is the only host call" "" "$(host_calls_but_tip)"
  assert_eq "$1: no request is opened, read or merged" "" "$(requests)"
  assert_eq "$1: nothing was pushed" no "$(pushed)"
}
# AC-53, AC-54: a forged local origin/master, through the guard and run directly
for h in $hosts; do
  evil_fixture --git-host $h
  out=$(ghook "bash scripts/pipeline/install-merge.sh"); gx=$?; : > "$FK/log"
  out=$(route); evil_refused "AC-53/54: $h: a forged origin/master (the guard's pre-check said $gx)" "$out" $?
  assert_eq "AC-53/54: $h: the trunk still has no backdoor" "$A0" "$(git -C "$ORIGIN" rev-parse master)"
done
# AC-55: PIPELINE_REMOTE names another repository whose master is evil; the host still reports A
for h in $hosts; do
  evil_fixture --git-host $h
  FORK="$(mktemp -d)"; git init -q --bare "$FORK"; g push -q "$FORK" evil:refs/heads/master; g remote add fork "$FORK"; g fetch -q fork
  sed -i 's/^PIPELINE_REMOTE=.*/PIPELINE_REMOTE="fork"/' "$R/$ENVF"; commit_all "remote fork"; g rev-parse HEAD > "$FK/src"; : > "$FK/log"
  out=$(route); evil_refused "AC-55: $h: PIPELINE_REMOTE=fork" "$out" $?
  assert_eq "AC-55: $h: nothing was pushed to the fork" no "$(git -C "$FORK" rev-parse -q --verify refs/heads/ship-pipeline/install >/dev/null 2>&1 && echo yes || echo no)"
done
# AC-59 (FR-18): a liar and a command in pipeline.env: in the working tree only, then committed as well
cat > "$FK/bin/liar" <<'FAKE'
#!/usr/bin/env bash
echo "liar $*" >> "$FK/liarlog"; cat "$FK/evil"
FAKE
chmod +x "$FK/bin/liar"
for h in $hosts; do
  case $h in github) v=PIPELINE_GH_CMD;; gitlab) v=PIPELINE_GLAB_CMD;; bitbucket) v=PIPELINE_CURL_CMD;; esac
  evil_fixture --git-host $h; g rev-parse evil > "$FK/evil"; rm -f "$FK/liarlog" "$MK"
  printf '%s="%s"\ntouch %s\n' "$v" "$FK/bin/liar" "$MK" >> "$R/$ENVF"
  out=$(route); evil_refused "AC-59: $h: a liar in the working-tree pipeline.env" "$out" $?
  assert_eq "AC-59: $h: only the honest fake is called" "" "$(cat "$FK/liarlog" 2>/dev/null)"
  [ -e "$MK" ] && bad "AC-59: $h: the working-tree pipeline.env is never run" || ok "AC-59: $h: the working-tree pipeline.env is never run"
  commit_all "the liar, committed"; g rev-parse HEAD > "$FK/src"; : > "$FK/log"
  out=$(route); x=$?; assert_exit "AC-59: $h: the liar committed as well: exit 4" 4 $x "$out"
  case "$out" in "NOT-INSTALL scripts/pipeline/pipeline.env: "*|"NOT-INSTALL src/Backdoor.java: "*) ok "AC-59: $h: NOT-INSTALL names pipeline.env or the backdoor";;
    *) bad "AC-59: $h: NOT-INSTALL names pipeline.env or the backdoor" "$out";; esac
  assert_eq "AC-59: $h: committed: only the honest fake is called" "" "$(cat "$FK/liarlog" 2>/dev/null)"
  assert_eq "AC-59: $h: committed: nothing was pushed" no "$(pushed)"
  [ -e "$MK" ] && bad "AC-59: $h: the committed pipeline.env is never run" || ok "AC-59: $h: the committed pipeline.env is never run"
done
# AC-31, AC-32 (amended): T read before the push, the request and T re-read after the wait and before the merge
order_check() { # <label> <request-open pattern> <request-info pattern> <merge pattern>
  local t1 t2 lo li lm
  t1=$(grep -n '/branches/' "$FK/log" | sed -n 1p | cut -d: -f1); t2=$(grep -n '/branches/' "$FK/log" | sed -n 2p | cut -d: -f1)
  lo=$(grep -nE -e "$2" "$FK/log" | head -n1 | cut -d: -f1); li=$(grep -nE -e "$3" "$FK/log" | tail -n1 | cut -d: -f1); lm=$(grep -nE -e "$4" "$FK/log" | head -n1 | cut -d: -f1)
  [ -n "$t1" ] && [ -n "$lo" ] && [ "$t1" -lt "$lo" ] && ok "$1: the trunk head is read from the host before the push and the request" \
    || bad "$1: the trunk head is read from the host before the push and the request" "$(cat "$FK/log")"
  [ -n "$t2" ] && [ -n "$li" ] && [ -n "$lm" ] && [ "$li" -lt "$t2" ] && [ "$t2" -lt "$lm" ] && ok "$1: the request, then the trunk head, are re-read right before the merge" \
    || bad "$1: the request, then the trunk head, are re-read right before the merge" "$(cat "$FK/log")"
  assert_eq "$1: two trunk-head reads" 2 "$(grep -c '/branches/' "$FK/log")"
}
fixture; out=$(route); assert_exit "AC-31: github: merged" 0 $? "$out"
order_check "AC-31: github" 'pulls\?head=' 'api repos/o/r/pulls/5 ' 'pulls/5/merge'
if command -v jq >/dev/null 2>&1; then
  fixture --git-host gitlab; out=$(route); assert_exit "AC-32: gitlab: merged" 0 $? "$out"
  order_check "AC-32: gitlab" 'merge_requests\?state=opened' 'merge_requests/7$' 'merge_requests/7/merge'
  fixture --git-host bitbucket; out=$(route); assert_exit "AC-32: bitbucket: merged" 0 $? "$out"
  order_check "AC-32: bitbucket" 'pullrequests\?state=OPEN' '-X GET .*/pullrequests/3$' 'pullrequests/3/merge'
fi
# AC-56, AC-57, AC-58: the host's answers decide, and a failed or disagreeing read refuses (all three hosts)
for h in $hosts; do
  fixture --git-host $h; T0="$A0"
  case $h in
    github) u=https://github.com/o/r/pull/5; mp='pulls/5/merge';;
    gitlab) u=https://gitlab.com/g/p/-/merge_requests/7; mp='merge_requests/7/merge';;
    bitbucket) u=https://bitbucket.org/w/r/pull-requests/3; mp='pullrequests/3/merge';;
  esac
  echo 0123456789abcdef0123456789abcdef01234567 > "$FK/tip2"
  out=$(route); assert_exit "AC-56: $h: the trunk moved before the merge: exit 3" 3 $? "$out"
  assert_contains "AC-56: $h: says so" "$out" "REFUSED $u the trunk moved since the check (host: 0123456789abcdef0123456789abcdef01234567, checked: $T0)"
  assert_eq "AC-56: $h: no merge call" 0 "$(grep -c "$mp" "$FK/log")"
  rearm; touch "$FK/open"; echo staging > "$FK/target"
  out=$(route); assert_exit "AC-57: $h: a reused request into staging: exit 3" 3 $? "$out"
  assert_contains "AC-57: $h: says so" "$out" "REFUSED $u the request targets 'staging', not 'master'"
  assert_eq "AC-57: $h: no merge call" 0 "$(grep -c "$mp" "$FK/log")"
  for f in "fake: HTTP 404: Branch not found" "curl: (6) Could not resolve host"; do
    rearm; echo "$f" > "$FK/tipfail"
    out=$(route); assert_exit "AC-58: $h: the trunk-head read fails ($f): exit 3" 3 $? "$out"
    assert_contains "AC-58: $h: REFUSED with the reason" "$out" "the trunk tip could not be read from the host ($f)"
    assert_eq "AC-58: $h: before any request call ($f)" "" "$(requests)"; assert_eq "AC-58: $h: and before any push ($f)" no "$(pushed)"
  done
  rearm; echo abc1234 > "$FK/tip"
  out=$(route); assert_exit "AC-58: $h: an answer that is not a full sha: exit 3" 3 $? "$out"
  assert_contains "AC-58: $h: says so" "$out" "the trunk tip could not be read from the host (the host's answer is not a full commit sha)"
  assert_eq "AC-58: $h: not a full sha: nothing pushed" no "$(pushed)"
  rearm; echo 0123456789abcdef0123456789abcdef01234567 > "$FK/tip"
  out=$(route); assert_exit "AC-58: $h: a trunk tip the remote does not have: exit 3" 3 $? "$out"
  assert_contains "AC-58: $h: says so" "$out" "the host's trunk tip 0123456789abcdef0123456789abcdef01234567 could not be fetched"
  assert_eq "AC-58: $h: unfetchable: no request call" "" "$(requests)"; assert_eq "AC-58: $h: unfetchable: nothing pushed" no "$(pushed)"
done
# AC-16 (amended), route side: the host's trunk head, not the local ref, decides ancestry and "nothing to merge"
fixture; X="$(g commit-tree -m other "$(g rev-parse 'HEAD^{tree}')")"; echo "$X" > "$FK/tip"
out=$(route); assert_exit "AC-16: the host's master not an ancestor of HEAD: exit 4" 4 $? "$out"
assert_contains "AC-16: says so" "$out" "NOT-INSTALL: the host's master ($X) is not an ancestor of HEAD"
assert_eq "AC-16: no request call" "" "$(requests)"; assert_eq "AC-16: nothing pushed" no "$(pushed)"
rearm; g rev-parse HEAD > "$FK/tip"
out=$(route); assert_exit "AC-16: the host's master already at HEAD: exit 1" 1 $? "$out"; assert_contains "AC-16: nothing to merge" "$out" "nothing to merge"
assert_eq "AC-16: nothing to merge: no request call" "" "$(requests)"; assert_eq "AC-16: nothing to merge: nothing pushed" no "$(pushed)"
# AC-17 (amended), route side: the committed configuration must be the working tree's
for kv in 'BASE_BRANCH="main"' 'GIT_HOST="gitlab"' 'GIT_HOST_URL="https://git.example.com"' 'PIPELINE_REMOTE="fork"'; do
  env_route "AC-17: route: a committed ${kv%%=*} the working tree does not say: exit 4" 4 "NOT-INSTALL scripts/pipeline/pipeline.env: scripts/pipeline/pipeline.env at HEAD says $kv" put_line "${kv%%=*}" "$kv"
done
# AC-60 (real history): a replace ref, a graft or a shallow boundary never makes the trunk an ancestor
rearm; I="$(g rev-parse HEAD)"; X="$(g commit-tree -m "the install, with no parent" "$(g rev-parse 'HEAD^{tree}')")"
g reset -q --hard "$X"; echo "$X" > "$FK/src"; g replace --graft "$X" "$A0"
assert_eq "AC-60: (the replace ref makes the trunk look like the parent)" 2 "$(g rev-list --count HEAD)"
out=$(route); assert_exit "AC-60: a replace ref: exit 4" 4 $? "$out"; assert_contains "AC-60: replace: not an ancestor" "$out" "is not an ancestor of HEAD"
assert_eq "AC-60: replace: nothing pushed" no "$(pushed)"
g replace -d "$X" >/dev/null; echo "$X $A0" > "$R/.git/info/grafts"; rearm
out=$(route); assert_exit "AC-60: a graft: exit 4" 4 $? "$out"; assert_contains "AC-60: graft: not an ancestor" "$out" "is not an ancestor of HEAD"
assert_eq "AC-60: graft: nothing pushed" no "$(pushed)"
rm -f "$R/.git/info/grafts"; g reset -q --hard "$I"; echo "$I" > "$FK/src"; echo "$I" > "$R/.git/shallow"; rearm
out=$(route); x=$?; [ "$x" = 3 ] || [ "$x" = 4 ] && ok "AC-60: a shallow boundary refuses (exit $x)" || bad "AC-60: a shallow boundary refuses" "exit $x: $out"
assert_eq "AC-60: shallow: nothing pushed" no "$(pushed)"
rm -f "$R/.git/shallow"
# AC-61: the local origin/master is not evidence: missing, or at an older trunk commit, the route still merges
fixture; g update-ref -d refs/remotes/origin/master
out=$(route); assert_exit "AC-61: no local origin/master: merged" 0 $? "$out"; assert_contains "AC-61: MERGED" "$out" "MERGED https://github.com/o/r/pull/5"
rearm; origin_repo; export ORIGIN; old="$(g rev-parse HEAD)"; (cd "$R" && echo "class B {}" > src/B.java); commit_all "B"; g push -q origin master; g fetch -q origin
install_branch; g rev-parse HEAD > "$FK/src"; g update-ref refs/remotes/origin/master "$old"; : > "$FK/log"
out=$(route); assert_exit "AC-61: a stale local origin/master: merged" 0 $? "$out"
assert_eq "AC-61: the trunk has the install" "$(g rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse master)"
# AC-34 (amended): the upgrade title comes from T, even with no local origin/master
rearm; origin_repo; export ORIGIN; bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name demo --team-key REP --base-branch master --staging-branch staging >/dev/null
commit_all "older install"; g push -q origin master; g fetch -q origin
install_branch; g rev-parse HEAD > "$FK/src"; g update-ref -d refs/remotes/origin/master; : > "$FK/log"
out=$(route); assert_exit "AC-34: an upgrade with no local origin/master is merged" 0 $? "$out"
assert_contains "AC-34: with the upgrade title (from T)" "$(cat "$FK/log")" "-f title=chore: update ship pipeline to v$ver"

# ==== SHI-57 (R1c-2, FR-19): what an unreviewed install may put in pipeline.env, on the route ====
fixture
en=$(( $(g show HEAD:$ENVF | wc -l | tr -d ' ') + 1 ))
bl="$(g show HEAD:$ENVF | grep -n '^BASE_BRANCH=' | cut -d: -f1)"; pl="$(g show HEAD:$ENVF | grep -n '^PROJECT_NAME=' | cut -d: -f1)"
rl="$(g show HEAD:$ENVF | grep -n '^PIPELINE_TICKET_REGEX=' | cut -d: -f1)"
NP="NOT-INSTALL scripts/pipeline/pipeline.env: scripts/pipeline/pipeline.env line"
# AC-65: plain settings pass and merge
env_route "AC-65: route: another plain value" 0 "MERGED" put_line DEV_URL 'DEV_URL="https://dev.example.com/#/x"'
env_route "AC-65: route: a single-quoted value" 0 "MERGED" put_line PROJECT_NAME "PROJECT_NAME='demo'"
env_route "AC-65: route: an empty value" 0 "MERGED" put_line HEALTH_PATH 'HEALTH_PATH='
env_route "AC-65: route: a trailing comment" 0 "MERGED" put_line PROJECT_NAME 'PROJECT_NAME="demo" # the name'
env_route "AC-65: route: comment and blank lines added" 0 "MERGED" add_line "" "# a note" ""
env_route "AC-65: route: a key removed" 0 "MERGED" sed -i '/^HEALTH_PATH=/d' "$ENVF"
env_route "AC-65: route: CRLF line endings" 0 "MERGED" sh -c "git config core.autocrlf false; sed -i 's/\$/\r/' $ENVF"
g config --unset core.autocrlf 2>/dev/null
env_route "AC-65: route: a narrow PIPELINE_TICKET_REGEX" 0 "MERGED" put_line PIPELINE_TICKET_REGEX 'PIPELINE_TICKET_REGEX="RAD-[0-9]+"'
# AC-66 .. AC-71, AC-73: refused before any push, naming the line
env_route "AC-66: route: an unknown key" 4 "$NP $en: 'FOO' is not a setting in the plugin's pipeline.env template" add_line 'FOO="x"'
env_route "AC-66: route: a test double's key" 4 "$NP $en: 'PIPELINE_GH_CMD' is not a setting" add_line 'PIPELINE_GH_CMD="/tmp/fake"'
env_route "AC-71: route: a retired key" 4 "$NP $en: 'PIPELINE_START_LEVEL' is not a setting" add_line 'PIPELINE_START_LEVEL="analysis"'
for l in "touch $MK" "source /tmp/x" 'eval "x"' "BASE_BRANCH=\"master\" touch $MK" "BASE_BRANCH=\"master\"; touch $MK" 'f() { :; }' 'if true; then :; fi'; do
  env_route "AC-67: route: a command line ($l)" 4 "$NP $en:" add_line "$l"
done
for v in "\"\$(touch $MK)\"" "\"\`touch $MK\`\"" '"${TRACKER_TEAM_KEY}"' '"$HOME"' '$HOME' '~/x' '"a\b"'; do
  env_route "AC-68: route: PROJECT_NAME=$v" 4 "$NP $pl: the value of 'PROJECT_NAME' is not a plain value" put_line PROJECT_NAME "PROJECT_NAME=$v"
done
env_route "AC-68: route: an open quote" 4 "$NP" put_line PROJECT_NAME "PROJECT_NAME=\"demo
x\""
env_route "AC-68: route: the regex line with a comment" 4 "$NP $rl: the value of 'PIPELINE_TICKET_REGEX'" put_line PIPELINE_TICKET_REGEX 'PIPELINE_TICKET_REGEX="${TRACKER_TEAM_KEY:-}-[0-9]+" # mine'
env_route "AC-68: route: the regex line with \$(id)" 4 "$NP $rl: the value of 'PIPELINE_TICKET_REGEX'" put_line PIPELINE_TICKET_REGEX 'PIPELINE_TICKET_REGEX="${TRACKER_TEAM_KEY:-}-[0-9]+$(id)"'
[ -e "$MK" ] && bad "AC-67/AC-68: route: nothing in the committed pipeline.env ran" || ok "AC-67/AC-68: route: nothing in the committed pipeline.env ran"
env_route "AC-69: route: export" 4 "$NP $bl: 'export' is not allowed" put_line BASE_BRANCH 'export BASE_BRANCH="master"'
env_route "AC-69: route: a bare export" 4 "$NP $en: 'export' is not allowed" add_line 'export PROJECT_NAME'
env_route "AC-70: route: BASE_BRANCH twice" 4 "$NP $en: 'BASE_BRANCH' is set more than once (first on line $bl)" add_line 'BASE_BRANCH="master"'
env_route "AC-70: route: the regex twice" 4 "$NP $en: 'PIPELINE_TICKET_REGEX' is set more than once (first on line $rl)" add_line 'PIPELINE_TICKET_REGEX="RAD-[0-9]+"'
env_route "AC-73: route: a secret under an unknown key" 4 "$NP $en: 'SECRET_TOKEN' is not a setting in the plugin's pipeline.env template" add_line 'SECRET_TOKEN="s3cr3t-value"'
case "$out" in *s3cr3t-value*) bad "AC-73: route: the value is never printed" "$out";; *) ok "AC-73: route: the value is never printed";; esac
# AC-74: no template in the reference fails closed, before any push
NOTPL="$(mktemp -d)/ref"; mkdir -p "$NOTPL"; (cd "$REPO_SRC" && cp -r .claude-plugin agents scripts template "$NOTPL/"); rm -f "$NOTPL/template/scripts/pipeline/pipeline.env"
rearm; out=$(PIPELINE_PLUGIN_ROOT="$NOTPL" route); assert_exit "AC-74: route: no pipeline.env template in the reference: exit 4" 4 $? "$out"
assert_contains "AC-74: route: says so" "$out" "the plugin's pipeline.env template could not be read"; assert_eq "AC-74: route: nothing pushed" no "$(pushed)"
# AC-64, AC-65: the other shapes merge as rendered, and with a bare value / this repository's own pipeline.env
fixture --deploy-mode explicit; out=$(route); assert_exit "AC-64: route: --deploy-mode explicit, as rendered: merged" 0 $? "$out"
rewind "$(cat "$FK/src")"; env_route "AC-65: route: a bare value (DEPLOY_MODE=explicit)" 0 "MERGED" put_line DEPLOY_MODE 'DEPLOY_MODE=explicit'
fixture --no-deploy-envs; out=$(route); assert_exit "AC-64: route: --no-deploy-envs, as rendered: merged" 0 $? "$out"
rewind "$(cat "$FK/src")"; env_route "AC-65: route: this repository's own pipeline.env" 0 "MERGED" cp "$REPO_SRC/$ENVF" "$ENVF"
# AC-72: an unchanged hand-edited pipeline.env does not block an upgrade; changed, the whole file is under the rule
rearm; origin_repo; export ORIGIN
bash "$REPO_SRC/scripts/init.sh" --project-dir "$R" --name demo --team-key REP --base-branch master --staging-branch staging >/dev/null
(cd "$R" && add_line 'PIPELINE_START_LEVEL="analysis"' 'MY_KEY="x"' 'export PIPELINE_WAIT_TRIES=3' 'BASE_BRANCH="master"')
commit_all "an older install, hand-edited"; g push -q origin master; g fetch -q origin; A0="$(g rev-parse HEAD)"
install_branch; g rev-parse HEAD > "$FK/src"; g rev-parse HEAD > "$FK/merge-to"; at="$(g rev-parse HEAD)"
out=$(route); assert_exit "AC-72: route: an unchanged hand-edited pipeline.env: merged" 0 $? "$out"
rewind "$at"; (cd "$R" && add_line "# one more line"); commit_all "touch pipeline.env"; g rev-parse HEAD > "$FK/src"
out=$(route); assert_exit "AC-72: route: changed, it is under the rule: exit 4" 4 $? "$out"
assert_contains "AC-72: route: naming the first bad line" "$out" "'PIPELINE_START_LEVEL' is not a setting in the plugin's pipeline.env template"
assert_eq "AC-72: route: nothing pushed" no "$(pushed)"
summary
