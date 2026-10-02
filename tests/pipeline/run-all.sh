#!/usr/bin/env bash
# Runs all pipeline tooling tests. Exit non-zero if any fail.
# The files run in parallel (each builds its own temporary repositories). Each file's output is streamed, in
# order, as soon as it and every file before it have finished, with a [n/N] progress line; a total follows.
# PIPELINE_TESTS_SERIAL=1 runs them one after another instead.
cd "$(dirname "$0")"
tests=(test_config.sh test_init.sh test_gate.sh test_promote.sh test_intake_status.sh test_allow_paths.sh test_guard_merge.sh test_doctor.sh test_deploy_scripts.sh test_adapters.sh test_install_merge.sh test_tracker_adapters.sh test_host_adapters.sh)
status=0; passed=0; failed=0; n=0
present=(); for t in "${tests[@]}"; do [ -f "$t" ] && present+=("$t"); done
out="$(mktemp -d)"; trap 'rm -rf "$out"' EXIT
report() { # <test file>: print its log and progress, add up its counts
  local t="$1" rc p f; rc="$(cat "$out/$t.rc" 2>/dev/null || echo 1)"; n=$((n+1))
  cat "$out/$t.log"
  p="$(sed -n 's/^  -- \([0-9]*\) passed, \([0-9]*\) failed$/\1/p' "$out/$t.log" | tail -n 1)"
  f="$(sed -n 's/^  -- \([0-9]*\) passed, \([0-9]*\) failed$/\2/p' "$out/$t.log" | tail -n 1)"
  passed=$((passed + ${p:-0})); failed=$((failed + ${f:-0}))
  [ "$rc" = 0 ] || status=1
  printf '[%d/%d] %s %s (%d%% of files done)\n' "$n" "${#present[@]}" "$t" "$([ "$rc" = 0 ] && echo passed || echo FAILED)" $((n * 100 / ${#present[@]}))
}
if [ "${PIPELINE_TESTS_SERIAL:-0}" = 1 ]; then
  for t in "${present[@]}"; do bash "$t" > "$out/$t.log" 2>&1; echo $? > "$out/$t.rc"; report "$t"; done
else
  pids=()
  for t in "${present[@]}"; do ( bash "$t" > "$out/$t.log" 2>&1; echo $? > "$out/$t.rc" ) & pids+=($!); done
  for i in "${!present[@]}"; do wait "${pids[$i]}"; report "${present[$i]}"; done
fi
echo "TOTAL: $passed passed, $failed failed"
[ $status -eq 0 ] && echo "ALL PIPELINE TESTS PASSED" || echo "PIPELINE TESTS FAILED"
exit $status
