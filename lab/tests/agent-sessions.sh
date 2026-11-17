#!/usr/bin/env bash
# Question: does work started for an agent keep running after the terminal
# that started it is closed? Can it be seen, with its memory and processor
# use, and reached again from another terminal?
#
# The "agent" is a stand-in that writes one line per second. It runs as a
# systemd unit of the login user, with a memory cap, and a second one runs
# inside tmux. tmux is installed in the lab for this test only.
#
# WSL stops a distro that has had no terminal attached for 15 seconds (the
# default of instanceIdleTimeout in .wslconfig). The test measures that too,
# and then repeats the wait with one session left open somewhere.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="agent-sessions"
readonly QUESTION="Does an agent's work outlive the terminal that started it, and can it be seen and reached again?"
readonly GAP_SECONDS=45        # longer than WSL's 15 s idle limit
readonly KEEP_ALIVE_SECONDS=90 # how long the stand-in "terminal left open" lasts

common() {
  cat <<'IN_LAB'
readonly WORK="$HOME/t/agent-sessions"
readonly UNIT="agent-heartbeat"
readonly HEARTBEAT="$WORK/heartbeat.log"
readonly BEAT='while :; do date +%s; sleep 1; done'
mkdir -p "$WORK"
unit_running() { systemctl --user is-active --quiet "$UNIT"; }
beats() { wc -l <"$HEARTBEAT" 2>/dev/null || echo 0; }
# Largest pause, in seconds, between two lines of the heartbeat file.
longest_pause() { awk 'NR > 1 && $1 - previous > worst {worst = $1 - previous} {previous = $1} END {print worst + 0}' "$HEARTBEAT" 2>/dev/null; }
start_unit() {
  rm -f "$HEARTBEAT"
  systemctl --user stop "$UNIT" >/dev/null 2>&1
  systemd-run --user --quiet --collect --unit "$UNIT" -p MemoryMax=256M bash -c "$BEAT >>$HEARTBEAT"
}
IN_LAB
}

# 1. Start it, look at it, and start a second one inside tmux.
start_and_look() {
  common
  cat <<'IN_LAB'
rm -rf "$WORK" && mkdir -p "$WORK"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux >/dev/null 2>&1
fact started "$(yes_no start_unit)"
sleep 3
fact listed_by_name_pattern "$(systemctl --user list-units --type=service --no-legend 'agent-*' | wc -l)"
fact memory_reported_bytes "$(systemctl --user show "$UNIT" -p MemoryCurrent --value)"
fact processor_time_reported_ns "$(systemctl --user show "$UNIT" -p CPUUsageNSec --value)"
fact memory_cap_reported "$(systemctl --user show "$UNIT" -p MemoryMax --value)"
tmux kill-server >/dev/null 2>&1
fact tmux_session_started_in_capped_unit "$(yes_no systemd-run --user --quiet --scope --unit agent-tmux -p MemoryMax=256M tmux new-session -d -s agent "$BEAT")"
IN_LAB
}

# 2. A different terminal, a few seconds later.
from_another_terminal() {
  common
  cat <<'IN_LAB'
fact running_seen_from_another_terminal "$(yes_no unit_running)"
fact output_readable_from_file "$(yes_no test "$(beats)" -gt 3)"
fact tmux_session_seen_from_another_terminal "$(yes_no tmux has-session -t agent)"
fact tmux_screen_readable_from_another_terminal "$(yes_no sh -c 'tmux capture-pane -p -t agent | grep -q "[0-9]"')"
IN_LAB
}

# 3. After a stretch with no terminal attached at all.
after_gap_without_terminals() {
  common
  cat <<'IN_LAB'
fact after_gap_without_terminals_still_running "$(yes_no unit_running)"
fact after_gap_without_terminals_tmux_alive "$(yes_no tmux has-session -t agent)"
fact after_gap_without_terminals_longest_pause_s "$(longest_pause)"
IN_LAB
}

restart_work() { common; echo 'start_unit; sleep 2; fact restarted_for_second_wait "$(yes_no unit_running)"'; }

# 4. After the same stretch, but with one session left open somewhere.
after_gap_with_one_session_open() {
  common
  cat <<'IN_LAB'
fact after_gap_with_one_session_open_still_running "$(yes_no unit_running)"
fact after_gap_with_one_session_open_longest_pause_s "$(longest_pause)"
systemctl --user stop "$UNIT" agent-tmux.scope >/dev/null 2>&1; tmux kill-server >/dev/null 2>&1
rm -rf "$WORK"
IN_LAB
}

# 5. Control: is it linger that keeps the work alive? Linger is switched off
# for one wait and switched back on, also if the test fails.
set_linger() { echo "loginctl $1-linger \"\$(awk -F= '/^default=/{print \$2}' /etc/wsl.conf)\""; }
linger_off() { set_linger disable; }
linger_on() { set_linger enable; }
start_without_linger() { common; echo 'start_unit; sleep 2; fact without_linger_started "$(yes_no unit_running)"'; }
after_gap_without_linger() {
  common
  cat <<'IN_LAB'
fact without_linger_after_gap_still_running "$(yes_no unit_running)"
fact without_linger_after_gap_longest_pause_s "$(longest_pause)"
fact without_linger_heartbeats_written "$(beats)"
systemctl --user stop "$UNIT" >/dev/null 2>&1
rm -rf "$WORK"
IN_LAB
}

lab_state() { wsl.exe --list --verbose </dev/null 2>&1 | tr -d '\0\r' | awk -v name="$TEST_LAB_NAME" '$1 == name || $2 == name {print $(NF - 1)}'; }

main() {
  reset_facts
  as_user start_and_look
  sleep 4
  as_user from_another_terminal

  sleep "$GAP_SECONDS"
  local state; state="$(lab_state)"
  as_user after_gap_without_terminals
  host_fact distro_state_after_gap_without_terminals "$state"
  host_fact gap_seconds "$GAP_SECONDS"

  as_user restart_work
  wsl.exe -d "$TEST_LAB_NAME" --cd / --exec sleep "$KEEP_ALIVE_SECONDS" </dev/null >/dev/null 2>&1 &
  sleep "$GAP_SECONDS"
  state="$(lab_state)"
  as_user after_gap_with_one_session_open
  host_fact distro_state_after_gap_with_one_session_open "$state"
  wait

  # Control: nothing of the agent's is running and no terminal is attached.
  sleep "$GAP_SECONDS"
  host_fact distro_state_after_gap_with_nothing_running "$(lab_state)"

  trap 'as_root linger_on >/dev/null 2>&1 || true' EXIT
  as_root linger_off
  as_user start_without_linger
  sleep "$GAP_SECONDS"
  state="$(lab_state)"
  as_user after_gap_without_linger
  host_fact distro_state_after_gap_without_linger "$state"
  as_root linger_on

  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
