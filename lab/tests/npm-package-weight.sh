#!/usr/bin/env bash
# Question: how much does Ubuntu's npm package add to the machine? It is
# installed for one job: letting root install the sandbox runtime.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="npm-package-weight"
readonly QUESTION="How many packages and how much disk does Ubuntu's npm package add?"

measure() {
  cat <<'IN_LAB'
dependency_closure() {
  apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$@" 2>/dev/null |
    grep -E '^[a-z0-9]' | sort -u | wc -l
}
fact packages_needed_by_nodejs "$(dependency_closure nodejs)"
fact packages_needed_by_nodejs_and_npm "$(dependency_closure nodejs npm)"
fact node_library_packages_installed "$(dpkg -l 'node-*' 2>/dev/null | grep -c '^ii')"
fact node_library_packages_mb "$(dpkg-query -W -f='${Installed-Size}\n' 'node-*' npm 2>/dev/null | awk '{s += $1} END {print int(s / 1024)}')"
fact all_packages_installed "$(dpkg-query -f '.\n' -W | wc -l)"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
