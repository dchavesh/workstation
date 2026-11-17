#!/usr/bin/env bash
# Question: what does it cost to let WSL append the Windows directories to
# PATH? Every command that is not found gets searched for in each of them.
#
# Flips appendWindowsPath in the lab's /etc/wsl.conf for one measurement and
# puts it back, also if the test fails.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="windows-path-cost"
readonly QUESTION="What do the Windows directories on PATH cost when a command is not found?"

set_append() { echo "sed -i 's/^appendWindowsPath=.*/appendWindowsPath=$1/' /etc/wsl.conf"; }
enable_windows_path() { set_append true; }
disable_windows_path() { set_append false; }

measure_body() {
  cat <<'IN_LAB'
readonly LOOKUPS=200
failed_lookups() { local i; for i in $(seq "$LOOKUPS"); do command -v "no-such-command-$i"; done; }
fact "path_entries_$LABEL" "$(tr ':' '\n' <<<"$PATH" | wc -l)"
fact "windows_entries_$LABEL" "$(tr ':' '\n' <<<"$PATH" | grep -c '^/mnt/')"
fact "failed_lookups_${LOOKUPS}_ms_$LABEL" "$(elapsed_ms failed_lookups)"
IN_LAB
}
measure_with() { echo 'LABEL=with_windows_path'; measure_body; }
measure_without() { echo 'LABEL=without_windows_path'; measure_body; }

restore() { as_root disable_windows_path >/dev/null 2>&1 || true; restart_lab || true; }

main() {
  trap restore EXIT
  reset_facts
  as_root enable_windows_path
  restart_lab
  as_user measure_with
  as_root disable_windows_path
  restart_lab
  as_user measure_without
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
