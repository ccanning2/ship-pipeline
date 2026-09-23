#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
echo "allow-paths.sh (persona write boundary)"
H="$REPO_SRC/scripts/pipeline/hooks/allow-paths.sh"
run() { # run <file_path> <globs...>
  local fp="$1"; shift
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR=/repo bash "$H" "$@" 2>&1
}
out=$(run /repo/docs/pipeline/REP-1/research.md 'docs/pipeline/<TICKET>/research.md'); assert_exit "allowed ticket file" 0 $? "$out"
out=$(run /repo/docs/pipeline/REP-1/product.md 'docs/pipeline/<TICKET>/research.md'); assert_exit "other ticket file blocked" 2 $? "$out"
assert_contains "block message names file" "$out" "product.md"
out=$(run /repo/src/main/java/App.java 'docs/pipeline/<TICKET>/research.md'); assert_exit "source code blocked" 2 $? "$out"
out=$(run docs/pipeline/REP-9/tickets.md 'docs/pipeline/<TICKET>/product.md' 'docs/pipeline/<TICKET>/tickets.md'); assert_exit "relative path, second glob" 0 $? "$out"
out=$(run /repo/backend/src/test/java/FooTest.java 'src/test/*' '*/src/test/*'); assert_exit "qa: nested test source allowed" 0 $? "$out"
out=$(run /repo/frontend/src/Badge.test.tsx '*.test.*'); assert_exit "qa: jest test allowed" 0 $? "$out"
out=$(run /repo/frontend/src/Badge.tsx '*.test.*' 'src/test/*'); assert_exit "qa: component blocked" 2 $? "$out"
out=$(run /repo/src/main/resources/application.yml 'src/test/*'); assert_exit "qa: config blocked" 2 $? "$out"
out=$(printf 'garbage' | bash "$H" 'x' 2>&1); assert_exit "malformed input ignored" 0 $? "$out"
out=$(printf '{"tool_input":{}}' | bash "$H" 'x' 2>&1); assert_exit "no path ignored" 0 $? "$out"

# every restricted agent's frontmatter write hook: qa-tester writes only tests and its reports; the plan-mode
# personas write nothing at all (/ship applies their plans)
cd "$REPO_SRC"; AD=.claude/agents; [ -d agents ] && [ -f .claude-plugin/plugin.json ] && AD=agents
wcmd() { $PY -c 'import yaml,sys; s=open(sys.argv[1]).read().split("\n---\n")[0].lstrip("---\n"); h=yaml.safe_load(s)["hooks"]["PreToolUse"]; print([x for x in h if "Write" in x["matcher"]][0]["hooks"][0]["command"])' "$AD/$1.md"; }
wtry() { printf '{"tool_input":{"file_path":"%s/%s"}}' "$REPO_SRC" "$2" | CLAUDE_PROJECT_DIR="$REPO_SRC" bash -c "$(wcmd "$1")" >/dev/null 2>&1; echo $?; }
for a in product-owner business-analyst qa-tester; do assert_eq "$a: cannot write production code" 2 "$(wtry "$a" src/main/java/Escrow.java)"; done
assert_eq "qa-tester: can write qa-report.md" 0 "$(wtry qa-tester docs/pipeline/REP-5/qa-report.md)"
assert_eq "devops: cannot write production code" 2 "$(wtry devops src/main/java/Escrow.java)"
assert_eq "devops: cannot write tests" 2 "$(wtry devops src/test/java/EscrowTest.java)"
for f in .github/workflows/deploy.yml .gitlab-ci.yml scripts/deploy/deploy.sh Dockerfile docker-compose.yml docs/pipeline/REP-5/dev-check.md; do
  assert_eq "devops: can write $f" 0 "$(wtry devops "$f")"
done
assert_eq "product-owner (plan mode): cannot write even product.md" 2 "$(wtry product-owner docs/pipeline/REP-5/product.md)"
assert_eq "business-analyst (plan mode): cannot write even requirements.md" 2 "$(wtry business-analyst docs/pipeline/REP-5/requirements.md)"
summary
