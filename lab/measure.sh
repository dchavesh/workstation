#!/usr/bin/env bash
# Prints a baseline report for the distro it runs in. Read-only: changes nothing.
# Usage from the daily distro:  wsl.exe -d lab -u root -- bash -s < lab/measure.sh
set -uo pipefail

readonly BOOT_WAIT_SECONDS=120
readonly BLAME_ROWS=12

section() { printf '\n== %s ==\n' "$1"; }
one_line() { tr '\n' ' '; echo; }

section "release"
# shellcheck disable=SC1091
. /etc/os-release && echo "$PRETTY_NAME"
echo "kernel $(uname -r)"
systemctl --version | head -1

section "boot"
state=$(timeout "$BOOT_WAIT_SECONDS" systemctl is-system-running --wait 2>/dev/null)
echo "system state: ${state:-unknown}"
systemd-analyze 2>&1 | head -2
systemd-analyze blame --no-pager 2>/dev/null | head -"$BLAME_ROWS"

section "enabled services"
systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager | awk '{print $1}' | one_line

section "enabled timers"
systemctl list-unit-files --type=timer --state=enabled --no-legend --no-pager | awk '{print $1}' | one_line

section "failed units"
systemctl --failed --no-legend --no-pager | awk '{print $2}' | one_line

section "implementations"
for cmd in ls sudo python3 bash zsh git curl; do
  if path=$(command -v "$cmd" 2>/dev/null); then
    echo "$cmd: $(readlink -f "$path")"
  else
    echo "$cmd: missing"
  fi
done
ls --version 2>/dev/null | head -1
sudo --version 2>/dev/null | head -1
python3 --version 2>/dev/null

section "packages"
echo "installed: $(dpkg-query -f '.\n' -W | wc -l)"
echo "manually installed: $(apt-mark showmanual | wc -l)"
echo "snaps: $(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' | one_line)"

section "users"
getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1" uid="$3" shell="$7}'

section "wsl.conf"
cat /etc/wsl.conf 2>/dev/null || echo "(none)"

section "cloud-init"
cloud-init status 2>&1 | head -3

section "memory (MB)"
free -m | sed -n '1,2p'

section "disk"
df -h / | tail -1
