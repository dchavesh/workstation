#!/usr/bin/env bash
# Runs as root inside the lab. Creates the login user the way Ubuntu's first-run
# setup would (minus the password) and makes it the default user.
# Safe to run again: each step checks before it changes anything.
set -euo pipefail

readonly LOGIN_NAME="${1:?usage: provision-user.sh <username>}"
readonly WSL_CONF="/etc/wsl.conf"
readonly SUDOERS_FILE="/etc/sudoers.d/90-lab-rehearsal"

if [[ ! "$LOGIN_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "provision-user: not a valid Linux user name: $LOGIN_NAME" >&2
  exit 1
fi

if id "$LOGIN_NAME" >/dev/null 2>&1; then
  echo "user $LOGIN_NAME: already present"
else
  useradd --create-home --shell /bin/bash --groups sudo "$LOGIN_NAME"
  echo "user $LOGIN_NAME: created"
fi

# Lab only: the rehearsal runs without a terminal, so nobody can type a sudo
# password. On the real machine sudo keeps asking for one.
if [[ -f "$SUDOERS_FILE" ]]; then
  echo "$SUDOERS_FILE: already present"
else
  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$LOGIN_NAME" > "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
  echo "$SUDOERS_FILE: passwordless sudo for $LOGIN_NAME (lab only)"
fi

if grep -q '^\[user\]' "$WSL_CONF" 2>/dev/null; then
  echo "$WSL_CONF: default user already set"
else
  printf '\n[user]\ndefault=%s\n' "$LOGIN_NAME" >> "$WSL_CONF"
  echo "$WSL_CONF: default user set to $LOGIN_NAME"
fi
