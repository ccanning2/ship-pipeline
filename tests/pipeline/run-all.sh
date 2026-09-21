#!/usr/bin/env bash
# Runs all pipeline tooling tests. Exit non-zero if any fail.
cd "$(dirname "$0")"
status=0
for t in test_config.sh test_init.sh test_gate.sh test_promote.sh test_intake_status.sh test_allow_paths.sh test_guard_merge.sh test_doctor.sh test_deploy_scripts.sh; do
  [ -f "$t" ] || continue
  bash "$t" || status=1
done
[ $status -eq 0 ] && echo "ALL PIPELINE TESTS PASSED" || echo "PIPELINE TESTS FAILED"
exit $status
