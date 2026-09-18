#!/usr/bin/env bash
# Create/refresh a ticket's pipeline folder from a text brief or a requirements document.
# Usage: intake.sh <TICKET> <file.md|.txt|.docx|.pdf> [origin-label]
#        intake.sh <TICKET> - [origin-label]     (brief text on stdin, e.g. the tracker ticket body;
#                                                 origin-label defaults to "text (chat)", pass the ticket URL)
set -euo pipefail
ticket="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"; src="${2:-}"; origin_label="${3:-}"
[ -n "$ticket" ] && [ -n "$src" ] || { echo "usage: intake.sh <TICKET> <file|->" >&2; exit 1; }
root="$(git rev-parse --show-toplevel)"; cd "$root"
dir="docs/pipeline/$ticket"; mkdir -p "$dir/source"
tpl="docs/pipeline/_templates"

if [ "$src" = "-" ]; then
  body="$(cat)"; origin="${origin_label:-text (chat)}"
else
  [ -f "$src" ] || { echo "intake: file not found: $src" >&2; exit 1; }
  cp "$src" "$dir/source/"
  origin="$dir/source/$(basename "$src")"
  lower="$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.md|*.txt) body="$(cat "$src")";;
    *.docx)
      if command -v pandoc >/dev/null; then body="$(pandoc -t gfm "$src")"
      else
        # A bare `python3` on PATH can be a stub that cannot run (Windows), so probe for a real one.
        py=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 </dev/null && { py="$c"; break; }; done
        [ -n "$py" ] || { echo "intake: install pandoc or python-docx to read .docx" >&2; exit 1; }
        body="$($py -c 'import sys,docx; print("\n".join(p.text for p in docx.Document(sys.argv[1]).paragraphs))' "$src")" \
        || { echo "intake: install pandoc or python-docx to read .docx" >&2; exit 1; }
      fi;;
    *.pdf)
      command -v pdftotext >/dev/null || { echo "intake: install poppler-utils (pdftotext) to read .pdf" >&2; exit 1; }
      body="$(pdftotext -layout "$src" -)";;
    *) echo "intake: unsupported file type: $src (use .md .txt .docx .pdf)" >&2; exit 1;;
  esac
fi
[ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || { echo "intake: brief is empty" >&2; exit 1; }

{
  echo "# $ticket — Brief (from the owner)"
  echo
  echo "Source: $origin"
  echo "Received: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "---"
  echo
  printf '%s\n' "$body"
} > "$dir/brief.md"

[ -f "$dir/STATUS.md" ] || sed "s/<TICKET>/$ticket/g" "$tpl/STATUS.md" > "$dir/STATUS.md"
[ -f "$dir/clarifications.md" ] || sed "s/<TICKET>/$ticket/g" "$tpl/clarifications.md" > "$dir/clarifications.md"
[ -f "$dir/releases.md" ] || sed "s/<TICKET>/$ticket/g" "$tpl/releases.md" > "$dir/releases.md"
rmdir "$dir/source" 2>/dev/null || true
echo "intake: $dir/brief.md written from $origin"
