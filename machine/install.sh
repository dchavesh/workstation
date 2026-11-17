#!/usr/bin/env bash
# First run on an empty machine. Afterwards `mise bootstrap` is the only command.
#
#   machine/install.sh          a plain Linux machine, VM or container
#   machine/install.sh wsl      a WSL distro
set -euo pipefail

readonly MISE_PPA="ppa:jdxcode/mise" # mise's documented apt source for Ubuntu
readonly KNOWN_ENVIRONMENTS=("" "wsl")

MACHINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MACHINE_DIR
readonly MISE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
readonly ENVIRONMENT="${1:-}"

die() { echo "install: $*" >&2; exit 1; }

validate() {
  [[ $EUID -ne 0 ]] || die "run as the login user, not root"
  local known
  for known in "${KNOWN_ENVIRONMENTS[@]}"; do [[ "$ENVIRONMENT" == "$known" ]] && return; done
  die "unknown environment '$ENVIRONMENT'"
}

install_mise() {
  command -v mise >/dev/null && return
  sudo add-apt-repository --yes "$MISE_PPA"
  sudo apt-get update --quiet
  sudo apt-get install --yes --quiet mise
}

# The repo directory becomes mise's global config directory.
link_config() {
  [[ "$(readlink -f "$MISE_CONFIG_DIR" 2>/dev/null)" == "$MACHINE_DIR" ]] && return
  [[ ! -e "$MISE_CONFIG_DIR" ]] || die "$MISE_CONFIG_DIR already exists; move it away first"
  mkdir -p "$(dirname "$MISE_CONFIG_DIR")"
  ln -s "$MACHINE_DIR" "$MISE_CONFIG_DIR"
}

apply() {
  MISE_ENV="$ENVIRONMENT" MISE_YES=1 mise bootstrap
}

main() {
  validate
  install_mise
  link_config
  apply
  echo "install: done. Restart the machine (WSL: wsl --shutdown), then run machine/verify.sh"
}

main "$@"
