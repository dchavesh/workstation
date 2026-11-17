#!/usr/bin/env bash
# Steps that need root and that mise has no section for. Run by mise as a
# bootstrap hook, as the login user, after system packages are installed.
# Safe to repeat: each step checks before it changes anything.
set -euo pipefail

readonly SRT_PACKAGE="@anthropic-ai/sandbox-runtime"
readonly SRT_VERSION="0.0.83"
readonly SYSTEM_PREFIX="/usr/local" # root-owned: an agent cannot rewrite its own sandbox
readonly SYSTEM_NODE="/usr/bin/node"
readonly SYSTEM_NPM="/usr/bin/npm"
readonly LOGIN_SHELL="/usr/bin/zsh"
readonly DOCKER_GROUP="docker"
readonly DOCKER_DAEMON_UNITS=(docker.service containerd.service)
readonly TMP_MOUNT_UNIT="tmp.mount"

login_user="$(id -un)"
readonly login_user

die() { echo "post-packages: $*" >&2; exit 1; }

installed_srt_version() {
  [[ -x "$SYSTEM_PREFIX/bin/srt" ]] || return 0
  "$SYSTEM_NODE" "$SYSTEM_PREFIX/bin/srt" --version 2>/dev/null || true
}

install_sandbox_runtime() {
  [[ -x "$SYSTEM_NODE" && -x "$SYSTEM_NPM" ]] || die "system node and npm are missing"
  [[ "$(installed_srt_version)" == "$SRT_VERSION" ]] && return
  sudo "$SYSTEM_NPM" install --global --silent --prefix "$SYSTEM_PREFIX" "${SRT_PACKAGE}@${SRT_VERSION}"
}

set_login_shell() {
  [[ -x "$LOGIN_SHELL" ]] || die "$LOGIN_SHELL is missing"
  [[ "$(getent passwd "$login_user" | cut -d: -f7)" == "$LOGIN_SHELL" ]] && return
  sudo chsh --shell "$LOGIN_SHELL" "$login_user"
}

# The user's services start at boot and survive the last terminal closing.
enable_linger() {
  [[ -e "/var/lib/systemd/linger/$login_user" ]] && return
  sudo loginctl enable-linger "$login_user"
}

join_docker_group() {
  getent group "$DOCKER_GROUP" >/dev/null || die "group $DOCKER_GROUP is missing"
  id -nG "$login_user" | tr ' ' '\n' | grep -qx "$DOCKER_GROUP" && return
  sudo usermod --append --groups "$DOCKER_GROUP" "$login_user"
}

unit_state() { systemctl is-enabled "$1" 2>/dev/null || true; }

# /tmp on disk from the next boot on: agents write gigabytes of scratch files
# and memory is the limit. Masking does not unmount the /tmp in use now.
put_tmp_on_disk() {
  [[ "$(unit_state "$TMP_MOUNT_UNIT")" == masked ]] && return
  sudo systemctl mask --quiet "$TMP_MOUNT_UNIT"
}

# Docker does not start at boot; docker.socket wakes it on first use. Only the
# boot setting is touched, so a daemon that is running now keeps running.
let_docker_sleep() {
  local unit
  for unit in "${DOCKER_DAEMON_UNITS[@]}"; do
    [[ "$(unit_state "$unit")" == enabled ]] || continue
    sudo systemctl disable --quiet "$unit"
  done
}

main() {
  [[ $EUID -ne 0 ]] || die "run as the login user, not root"
  install_sandbox_runtime
  put_tmp_on_disk
  let_docker_sleep
  join_docker_group
  set_login_shell
  enable_linger
}

main "$@"
