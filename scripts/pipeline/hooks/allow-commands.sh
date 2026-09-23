#!/usr/bin/env bash
# PreToolUse hook (Bash) that confines a persona's shell to named scripts, e.g. the tracker CLI adapter.
# Usage in agent frontmatter:  command: "bash scripts/pipeline/hooks/allow-commands.sh scripts/pipeline/tracker.sh"
# A command is allowed only when it is exactly `bash <allowed script> <args...>` (a leading `./` or the project
# path is accepted) and the arguments cannot start another command: outside single quotes there is no ; & | < >
# ( ) ` $ or newline. Text inside single quotes is literal, so --body '...' may hold anything but a single quote
# (write it as '\''). Exit 2 blocks and explains; exit 0 allows.
set -uo pipefail
input="$(cat)"
if command -v jq >/dev/null 2>&1; then cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  py=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { py="$c"; break; }; done
  cmd="$(printf '%s' "$input" | $py -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
fi
# fail closed: a command that cannot be read is blocked, not waved through
[ -n "$cmd" ] || case "$input" in *'"command"'*) echo "PERSONA BOUNDARY: could not read the command (install jq); blocked" >&2; exit 2;; *) exit 0;; esac
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"; project="${project//\\//}"
refuse() { echo "PERSONA BOUNDARY: this persona may run only: $(printf 'bash %s <args>; ' "$@")blocked: $cmd" >&2; exit 2; }
# one simple command, no expansion or redirection outside single quotes
bad="$(printf '%s' "$cmd" | awk -v sq="'" '
  BEGIN { q=0 }
  { line=$0; if (NR>1 && !q) { print "a newline"; exit }   # a newline inside single quotes is text
    for (i=1; i<=length(line); i++) { c=substr(line,i,1)
      if (q) { if (c==sq) q=0; continue }
      if (c==sq) { q=1; continue }
      if (c=="\\") { i++; continue }
      if (index(";&|<>()`$", c)) { print "\"" c "\""; exit }
    } }
  END { if (q) print "an unclosed quote" }')"
[ -z "$bad" ] || { echo "PERSONA BOUNDARY: blocked $bad in: $cmd. Only 'bash <script> <args>' is allowed; put free text inside single quotes." >&2; exit 2; }
read -r -a w <<<"$cmd"
[ "${w[0]:-}" = bash ] || refuse "$@"
s="${w[1]:-}"; s="${s//\\//}"; s="${s#"$project"/}"; s="${s#./}"
for a in "$@"; do [ "$s" = "$a" ] && exit 0; done
refuse "$@"
