#!/usr/bin/env bash
# Reproduces the boot race that broke the daily distro, then checks which
# settings fix it.
#
# The race: an early systemd unit takes longer than WSL is willing to wait, so
# WSL logs the user in before systemd-logind exists and the user session
# (/run/user/<uid>) is never created.
#
# Run from the daily distro:  lab/tests/boot-race.sh
# Leaves the lab as it found it: slow unit removed, linger off, default timeout.
set -euo pipefail

readonly LAB="lab"
readonly SLOW_SECONDS=30          # longer than WSL's default 10 s wait plus its 10 s session wait
readonly PATIENT_TIMEOUT_MS=60000 # the initTimeout value under test
readonly SLOW_UNIT="lab-slow-boot.service"

as_root() { wsl.exe -d "$LAB" -u root --cd / -- bash -s -- "$@" | tr -d '\0\r'; }

install_slow_unit() {
  as_root "$SLOW_UNIT" "$SLOW_SECONDS" <<'EOF'
set -euo pipefail
cat > "/etc/systemd/system/$1" <<UNIT
[Unit]
Description=Lab: keep early boot busy for $2 s
DefaultDependencies=no
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sleep $2

[Install]
WantedBy=sysinit.target
UNIT
systemctl enable --quiet "$1"
EOF
}

remove_slow_unit() {
  as_root "$SLOW_UNIT" <<'EOF'
set -euo pipefail
systemctl disable --quiet "$1" 2>/dev/null || true
rm -f "/etc/systemd/system/$1"
EOF
}

# configure <linger: on|off> <initTimeout in ms, or "default">
configure() {
  as_root "$1" "$2" <<'EOF'
set -euo pipefail
login_user=$(awk -F= '/^default=/{print $2}' /etc/wsl.conf)
if [[ "$1" == on ]]; then loginctl enable-linger "$login_user"; else loginctl disable-linger "$login_user"; fi
sed -i '/^initTimeout=/d' /etc/wsl.conf
if [[ "$2" != default ]]; then sed -i "s/^systemd=true\$/systemd=true\ninitTimeout=$2/" /etc/wsl.conf; fi
EOF
}

# Boots the lab cold and reports what the first login saw.
measure() {
  local label="$1" start first elapsed after
  wsl.exe --terminate "$LAB" >/dev/null 2>&1 || true
  start=$(date +%s.%N)
  first=$(wsl.exe -d "$LAB" --cd / -- sh -c '[ -d "/run/user/$(id -u)" ] && echo present || echo MISSING' 2>/dev/null | tr -d '\0\r')
  elapsed=$(printf '%.0f' "$(echo "$(date +%s.%N) - $start" | bc)")
  after=$(as_root <<'EOF'
systemctl is-system-running --wait >/dev/null 2>&1 || true
sleep 3
login_uid=$(id -u "$(awk -F= '/^default=/{print $2}' /etc/wsl.conf)")
[[ -d "/run/user/$login_uid" ]] && echo present || echo MISSING
EOF
)
  # WSL's own error lines are not counted: the kernel log is shared by every
  # distro in the VM, so a count would include other distros' boots.
  printf '%-34s %6ss   %-9s %s\n' "$label" "$elapsed" "$first" "$after"
}

main() {
  trap 'configure off default >/dev/null 2>&1; remove_slow_unit >/dev/null 2>&1' EXIT
  install_slow_unit
  printf '%-34s %7s   %-9s %s\n' "settings" "wait" "at login" "later"
  configure off default;               measure "defaults"
  configure on  default;               measure "linger"
  configure off "$PATIENT_TIMEOUT_MS"; measure "initTimeout=$PATIENT_TIMEOUT_MS"
  configure on  "$PATIENT_TIMEOUT_MS"; measure "linger + initTimeout"
}

main "$@"
