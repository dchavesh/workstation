#!/usr/bin/env bash
# Question: with /tmp on disk and full of agent scratch files, does a cold
# boot stay fast, and do the files survive it?
#
# This is the situation that broke the daily distro: Ubuntu 24.04 deleted
# every file in /tmp at boot, and that outlasted WSL's wait for systemd.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="tmp-on-disk-boot"
readonly QUESTION="With /tmp on disk and 100,000 files in it, is a cold boot fast and do the files survive?"

fill_tmp() {
  cat <<'IN_LAB'
readonly SCRATCH=/tmp/scratch-test
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH"
for directory in $(seq 1 100); do
  mkdir -p "$SCRATCH/d$directory"
  for file in $(seq 1 1000); do echo "payload $directory $file ................................................" >"$SCRATCH/d$directory/f$file"; done
done
sync
fact tmp_filesystem "$(findmnt -no FSTYPE -T /tmp)"
fact entries_before_boot "$(find "$SCRATCH" | wc -l)"
fact size_mb_before_boot "$(du -sm "$SCRATCH" | cut -f1)"
IN_LAB
}

after_boot() {
  cat <<'IN_LAB'
systemctl is-system-running --wait >/dev/null 2>&1
login_uid=$(id -u "$(awk -F= '/^default=/{print $2}' /etc/wsl.conf)")
fact user_session_present "$(yes_no test -d "/run/user/$login_uid")"
fact tmpfiles_setup_time "$(systemd-analyze blame 2>/dev/null | awk '$2 == "systemd-tmpfiles-setup.service" {print $1}')"
fact systemd_startup "$(systemd-analyze 2>/dev/null | head -1)"
fact entries_after_boot "$(find /tmp/scratch-test 2>/dev/null | wc -l)"
rm -rf /tmp/scratch-test
IN_LAB
}

time_cold_boot() {
  local started
  restart_lab
  started=$(date +%s%N)
  wsl.exe -d "$TEST_LAB_NAME" --cd / -- true </dev/null
  host_fact first_command_after_cold_boot_ms "$(( ($(date +%s%N) - started) / 1000000 ))"
}

main() {
  reset_facts
  as_root fill_tmp
  time_cold_boot
  as_root after_boot
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
