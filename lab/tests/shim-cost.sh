#!/usr/bin/env bash
# Question: what does it cost per call to reach a tool through mise's shim,
# compared with calling the program directly and with `mise exec`?
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="shim-cost"
readonly QUESTION="What does a tool call cost through a mise shim, compared with a direct call and with mise exec?"

measure() {
  cat <<'IN_LAB'
readonly CALLS=100
cd "$HOME"
program="$(mise which just)"
per_call_microseconds() {
  local started i
  started=$(date +%s%N)
  for ((i = 0; i < CALLS; i++)); do "$@" >/dev/null 2>&1; done
  echo $(( ($(date +%s%N) - started) / CALLS / 1000 ))
}
fact calls_per_measurement "$CALLS"
fact direct_call_microseconds "$(per_call_microseconds "$program" --version)"
fact shim_call_microseconds "$(per_call_microseconds just --version)"
fact mise_exec_call_microseconds "$(per_call_microseconds mise exec -- just --version)"
fact shim_resolves_to "$(command -v just)"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
