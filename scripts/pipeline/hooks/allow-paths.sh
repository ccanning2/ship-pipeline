#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit) that confines a persona's file writes.
# Usage in agent frontmatter:  command: "bash scripts/pipeline/hooks/allow-paths.sh <glob> [<glob>...]"
# Globs are relative to the project root; <TICKET> in a glob matches any ticket folder name.
# Exit 2 blocks the write and explains why; exit 0 allows.
set -uo pipefail
input="$(cat)"
if command -v jq >/dev/null 2>&1; then
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
else
  # A bare `python3` on PATH can be a non-functional stub (Windows), so probe for a real one.
  py=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { py="$c"; break; }; done
  path="$(printf '%s' "$input" | $py -c 'import sys,json; t=json.load(sys.stdin).get("tool_input",{}); print(t.get("file_path") or t.get("path") or "")' 2>/dev/null || true)"
fi
[ -n "$path" ] || exit 0
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$path" in "$project"/*) rel="${path#"$project"/}";; /*) rel="$path";; *) rel="$path";; esac
rel="${rel#./}"

for pat in "$@"; do
  pat="${pat//<TICKET>/*}"
  # shellcheck disable=SC2254
  case "$rel" in $pat) exit 0;; esac
done
echo "PERSONA BOUNDARY: this persona may not write '$rel'. Allowed: $*" >&2
exit 2
