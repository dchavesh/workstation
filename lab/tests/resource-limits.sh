#!/usr/bin/env bash
# Question: can the login user, without root, cap the memory and the
# processor time of one process? This is what keeps one agent from starving
# the others on a machine where memory is the limit.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="resource-limits"
readonly QUESTION="Can the login user cap one process's memory and processor time without root?"

measure() {
  cat <<'IN_LAB'
readonly ALLOCATE='x = bytearray(300 * 1024 * 1024); print("allocated")'
readonly BUSY_TWO_SECONDS='timeout 2 bash -c "while :; do :; done"'
capped() { systemd-run --user --wait --collect --quiet "$@"; }
cpu_seconds() { systemd-run --user --wait --collect "$@" bash -c "$BUSY_TWO_SECONDS" 2>&1 | grep -i -o 'CPU time consumed: [0-9.a-z]*' | awk '{print $NF}'; }

fact delegated_controllers "$(cat "/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers" 2>/dev/null)"
fact uncapped_300mb_allocation_succeeds "$(yes_no python3 -c "$ALLOCATE")"
fact capped_at_64mb_allocation_succeeds "$(yes_no capped -p MemoryMax=64M -p MemorySwapMax=0 python3 -c "$ALLOCATE")"
fact cpu_time_in_2s_uncapped "$(cpu_seconds)"
fact cpu_time_in_2s_capped_at_50_percent "$(cpu_seconds -p CPUQuota=50%)"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
