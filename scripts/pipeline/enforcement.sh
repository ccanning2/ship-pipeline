#!/usr/bin/env bash
# How the release model is enforced on the code host. Read-only; always exits 0.
# Usage: enforcement.sh      prints "ENFORCEMENT=<host|local|unknown>" then one line explaining it
#   host     the Pipeline Gate check is required on the base and staging branches (protection, a ruleset,
#            a protected branch with "pipelines must succeed", or a Bitbucket "require passing builds" restriction)
#   local    only the guard-merge.sh hook enforces it. The hook gates agent tool calls only; a human or
#            another tool can still push past it.
#   unknown  the host CLI is missing or not signed in, so the host could not be asked
# The host comes from GIT_HOST in pipeline.env; scripts/pipeline/host.sh does the asking.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$here/host.sh" enforcement 2>/dev/null)"
case "$out" in ENFORCEMENT=*) printf '%s\n' "$out";; *) echo "ENFORCEMENT=unknown"; echo "Enforcement: unknown (the code host could not be asked)";; esac
exit 0
