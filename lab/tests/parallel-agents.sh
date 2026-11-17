#!/usr/bin/env bash
# Question: when several agents work at once and one of them misbehaves
# (asks for far more memory than its share), do per-agent limits stop that
# one and leave the others to finish?
#
# Each "agent" here is a stand-in workload in its own systemd unit, started by
# the login user without root. The runaway one asks for 3 GB under a 1 GB cap.
# Nothing runs without a cap: an uncapped runaway process would take memory
# from the whole WSL machine, including the daily distro.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="parallel-agents"
readonly QUESTION="With one capped unit per agent, does a runaway agent get stopped while the others finish?"

measure() {
  cat <<'IN_LAB'
readonly WORKERS=3
readonly MEMORY_CAP="1G"
readonly CPU_CAP="200%"
readonly OUT="$HOME/t/parallel-agents"
readonly WORK='import hashlib, time
block = b"x" * 8000000
started = time.time()
for _ in range(400):
    hashlib.sha256(block).digest()
print(round(time.time() - started, 2))'
readonly RUNAWAY='data = bytearray(3 * 1024 * 1024 * 1024)
print("got 3 GB")'
rm -rf "$OUT" && mkdir -p "$OUT"
available_mb() { awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo; }
as_agent() { systemd-run --user --wait --collect --quiet --pipe -p MemoryMax="$MEMORY_CAP" -p MemorySwapMax=0 -p CPUQuota="$CPU_CAP" "$@"; }

fact memory_cap_per_agent "$MEMORY_CAP"
fact cpu_cap_per_agent "$CPU_CAP"
fact memory_available_mb_before "$(available_mb)"
fact one_worker_alone_seconds "$(as_agent python3 -c "$WORK")"

for worker in $(seq "$WORKERS"); do
  ( as_agent python3 -c "$WORK" >"$OUT/worker-$worker.out" 2>&1; echo "$?" >"$OUT/worker-$worker.exit" ) &
done
( as_agent python3 -c "$RUNAWAY" >"$OUT/runaway.out" 2>&1; echo "$?" >"$OUT/runaway.exit" ) &
wait

finished=0
for worker in $(seq "$WORKERS"); do
  [[ "$(cat "$OUT/worker-$worker.exit")" == 0 ]] && finished=$((finished + 1))
  fact "worker_${worker}_seconds_beside_runaway" "$(cat "$OUT/worker-$worker.out")"
done
fact workers_started "$WORKERS"
fact workers_finished "$finished"
fact runaway_got_its_memory "$(yes_no grep -q 'got 3 GB' "$OUT/runaway.out")"
fact runaway_exit_code "$(cat "$OUT/runaway.exit")"
fact memory_available_mb_after "$(available_mb)"
rm -rf "$OUT"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
