#!/usr/bin/env bash
# Question: what does Docker Engine cost while nobody uses it, and how long
# does the first command take to wake it?
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="docker-idle-cost"
readonly QUESTION="What does Docker Engine cost while idle, and how long does the first command take to wake it?"

measure() {
  cat <<'IN_LAB'
memory_mb() { systemctl show "$1" -p MemoryCurrent --value | awk '{print ($1 ~ /^[0-9]+$/) ? int($1 / 1048576) : 0}'; }
both_mb() { echo $(( $(memory_mb docker.service) + $(memory_mb containerd.service) )); }
fact docker_running_after_cold_start "$(yes_no systemctl is-active --quiet docker.service)"
fact containerd_running_after_cold_start "$(yes_no systemctl is-active --quiet containerd.service)"
fact memory_mb_before_first_use "$(both_mb)"
fact first_run_ms "$(elapsed_ms docker run --rm hello-world)"
fact second_run_ms "$(elapsed_ms docker run --rm hello-world)"
fact docker_running_after_first_use "$(yes_no systemctl is-active --quiet docker.service)"
fact memory_mb_after_first_use "$(both_mb)"
IN_LAB
}

main() {
  reset_facts
  restart_lab
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
