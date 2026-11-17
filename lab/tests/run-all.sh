#!/usr/bin/env bash
# Runs every saved test that writes a record, one after the other, in a lab
# that lab/rehearse.sh has built. Each test writes its own record under
# data/runs/. A test that fails does not stop the others.
#
# Left out on purpose: android-emulator.sh (downloads about 5 GB) and
# boot-race.sh (prints a table and needs several minutes of cold boots).
set -uo pipefail

readonly TESTS=(
  shim-cost
  mise-trust
  gh-identities
  resource-limits
  sandbox-windows
  npm-package-weight
  docker-idle-cost
  windows-path-cost
  tmp-on-disk-boot
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

main() {
  local name failed=()
  for name in "${TESTS[@]}"; do
    printf '\n=== %s\n' "$name"
    "$SCRIPT_DIR/$name.sh" 2>&1 | grep -v 'mise WARN' || failed+=("$name")
  done
  if (( ${#failed[@]} > 0 )); then printf '\ndid not complete: %s\n' "${failed[*]}"; exit 1; fi
  printf '\nall %d tests wrote a record\n' "${#TESTS[@]}"
}

main "$@"
