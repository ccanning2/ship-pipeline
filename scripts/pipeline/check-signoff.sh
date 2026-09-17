#!/usr/bin/env bash
# Back-compat: full "ready for production" check. Usage: check-signoff.sh <TICKET> [REF]
exec bash "$(dirname "$0")/gate.sh" "${1:-}" production ${2:+"$2"}
