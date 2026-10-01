#!/usr/bin/env bash
# The fallback tracker adapter, installed as scripts/pipeline/tracker.sh when TRACKER="connector": no CLI fits this
# tracker, so every verb exits 3 and the caller uses the tracker's MCP connector tools for that step.
# adapter: tracker=connector
echo "tracker.sh: TRACKER=connector: use the tracker's MCP connector tools for this step" >&2
exit 3
