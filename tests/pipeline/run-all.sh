#!/usr/bin/env bash
# Runs all pipeline tooling tests. Exit non-zero if any fail.
# The files run in parallel (each builds its own temporary repositories) and their output is printed in order;
# PIPELINE_TESTS_SERIAL=1 runs them one after another instead.
cd "$(dirname "$0")"
tests=(test_config.sh test_init.sh test_gate.sh test_promote.sh test_intake_status.sh test_allow_paths.sh test_guard_merge.sh test_doctor.sh test_deploy_scripts.sh test_adapters.sh)
status=0
if [ "${PIPELINE_TESTS_SERIAL:-0}" = 1 ]; then
  for t in "${tests[@]}"; do [ -f "$t" ] || continue; bash "$t" || status=1; done
else
  out="$(mktemp -d)"; trap 'rm -rf "$out"' EXIT
  for t in "${tests[@]}"; do [ -f "$t" ] || continue; ( bash "$t" > "$out/$t.log" 2>&1; echo $? > "$out/$t.rc" ) & done
  wait
  for t in "${tests[@]}"; do
    [ -f "$out/$t.log" ] || continue
    cat "$out/$t.log"; [ "$(cat "$out/$t.rc")" = 0 ] || status=1
  done
fi
[ $status -eq 0 ] && echo "ALL PIPELINE TESTS PASSED" || echo "PIPELINE TESTS FAILED"
exit $status
