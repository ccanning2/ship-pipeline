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
  "api repos/o/r/pulls/5 "*) echo "$(cat "$FK/src") ready";;
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
  "api projects/"*"/merge_requests/7") printf '{"sha":"%s","detailed_merge_status":"mergeable"}\n' "$(cat "$FK/src")";;
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
  *"-X GET "*"/pullrequests/3") printf '{"source":{"commit":{"hash":"%s"}}}\n' "$(cut -c1-12 "$FK/src")";;
  *"-X POST "*"/pullrequests/3/merge"*)
    [ -f "$FK/refuse" ] && { echo 'curl: (22) The requested URL returned error: 400' >&2; exit 22; }
    git -C "$ORIGIN" update-ref refs/heads/master "$(cat "$FK/merge-to")"; echo '{}';;
  *) echo "fake curl: unexpected: $*" >&2; exit 22;;
esac
FAKE
chmod +x "$FK/bin/"*
export PIPELINE_GH_CMD="$FK/bin/gh" PIPELINE_GLAB_CMD="$FK/bin/glab" PIPELINE_CURL_CMD="$FK/bin/curl" BITBUCKET_API_TOKEN=x BITBUCKET_EMAIL=a@b.c
fresh() { # [init flags]: a new fixture on the install branch, and a clean fake host
  rm -f "$FK/log" "$FK/open" "$FK/refuse"; : > "$FK/log"
  origin_repo; export ORIGIN; install_branch "$@"; g rev-parse HEAD > "$FK/src"; g rev-parse HEAD > "$FK/merge-to"
}
route() { (cd "$R" && bash scripts/pipeline/install-merge.sh "$@" 2>&1); }
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
assert_eq "AC-38: no host call" "" "$(cat "$FK/log")"
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
summary
