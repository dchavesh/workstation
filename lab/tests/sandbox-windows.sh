#!/usr/bin/env bash
# Question: what can a process inside the agent sandbox do with the Windows
# side, compared with a process outside it?
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="sandbox-windows"
readonly QUESTION="What can a sandboxed process do with Windows files and programs?"

measure() {
  cat <<'IN_LAB'
readonly PROJECT="$HOME/t/sandbox-windows"
readonly PROBE="/mnt/c/Users/Public/srt-probe.txt"
rm -rf "$PROJECT" && mkdir -p "$PROJECT" && cd "$PROJECT"
printf '{"network":{"allowedDomains":[],"deniedDomains":[]},"filesystem":{"denyRead":[],"allowWrite":["."],"denyWrite":[]}}\n' >settings.json
box() { /usr/bin/node /usr/local/bin/srt --settings settings.json -c "$1"; }

fact outside_windows_program_starts "$(yes_no powershell.exe -NoProfile -Command 'exit 0')"
fact inside_windows_files_readable "$(yes_no box 'ls /mnt/c/Windows')"
fact inside_windows_files_writable "$(yes_no box "touch $PROBE")"
fact inside_windows_program_starts "$(yes_no box '/mnt/c/Windows/System32/cmd.exe /c ver')"
rm -f "$PROBE"
cd "$HOME" && rm -rf "$PROJECT"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
