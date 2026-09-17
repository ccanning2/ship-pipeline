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

# every restricted agent's frontmatter hook must block a source write and allow its own artifact
cd "$REPO_SRC"; AD=.claude/agents; [ -d agents ] && [ -f .claude-plugin/plugin.json ] && AD=agents
for a in market-researcher product-owner business-analyst qa-tester marketing-specialist; do
  cmd=$(python3 -c 'import yaml,sys; s=open(sys.argv[1]).read().split("\n---\n")[0].lstrip("---\n"); print(yaml.safe_load(s)["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$AD/$a.md")
  out=$(printf '{"tool_input":{"file_path":"%s/src/main/java/Escrow.java"}}' "$REPO_SRC" | CLAUDE_PROJECT_DIR="$REPO_SRC" bash -c "$cmd" 2>&1); assert_exit "$a: cannot write production code" 2 $? "$out"
done
for a in market-researcher:research.md product-owner:product.md business-analyst:requirements.md qa-tester:qa-report.md marketing-specialist:marketing.md; do
  n=${a%%:*}; f=${a#*:}
  cmd=$(python3 -c 'import yaml,sys; s=open(sys.argv[1]).read().split("\n---\n")[0].lstrip("---\n"); print(yaml.safe_load(s)["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$AD/$n.md")
  out=$(printf '{"tool_input":{"file_path":"%s/docs/pipeline/REP-5/%s"}}' "$REPO_SRC" "$f" | CLAUDE_PROJECT_DIR="$REPO_SRC" bash -c "$cmd" 2>&1); assert_exit "$n: can write $f" 0 $? "$out"
done
summary
