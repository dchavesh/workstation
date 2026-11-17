#!/usr/bin/env bash
# Full rehearsal: throw the lab away, build it from an empty Ubuntu image
# using only machine/, and check the result. Run from the daily distro:
#
#   lab/rehearse.sh
#
# The health check runs before the install (it must fail) and after (it must
# pass). The install must leave machine/mise.lock exactly as the repo has it.
set -euo pipefail

readonly LAB="lab"
readonly REPO_IN_LAB="projects/personal/systems/workstation" # relative to the lab user's home
readonly ENVIRONMENT="wsl"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT_DIR REPO_DIR

lab() { "$SCRIPT_DIR/lab" "$@"; }
in_lab() { lab user /dev/stdin 2>&1 | tr -d '\0'; }

step() {
  local title="$1" started; shift
  started=$(date +%s)
  printf '\n=== %s\n' "$title"
  "$@"
  printf -- '--- %s: %d s\n' "$title" "$(( $(date +%s) - started ))"
}

rebuild_lab() {
  local status
  status="$(lab status)"
  if grep -q '^lab: present' <<<"$status"; then lab destroy >/dev/null; fi
  lab create | tail -1
}

copy_machine_dir() {
  tar -C "$REPO_DIR" -c machine |
    wsl.exe -d "$LAB" --cd '~' -- sh -c "mkdir -p $REPO_IN_LAB && tar -x -C $REPO_IN_LAB && ls $REPO_IN_LAB/machine | tr '\n' ' '"
  echo
}

verify() { in_lab <<<"bash ~/$REPO_IN_LAB/machine/verify.sh"; }

verify_must_fail() {
  if verify | tail -4; then echo "rehearse: the check passed on an empty machine; it proves nothing" >&2; exit 1; fi
}

install() { in_lab <<<"bash ~/$REPO_IN_LAB/machine/install.sh $ENVIRONMENT" | grep -v -E '^(Get|Hit|Ign|Fetched|Reading|Building|Selecting|Preparing|Unpacking|Setting up|Processing|\(Reading|Created symlink)' | tail -40; }

restart_lab() { lab stop >/dev/null; }

apply_again() { in_lab <<<'zsh -c "mise bootstrap"' | tail -6; }

describe() { in_lab <<<"zsh -c ~/$REPO_IN_LAB/machine/describe"; }

# The install must not move any locked version. If the lab's lock file differs
# from the repo's, the build was not reproducible.
compare_lock_file() {
  local lab_lock
  lab_lock="$(wsl.exe -d "$LAB" --cd '~' -- cat "$REPO_IN_LAB/machine/mise.lock" </dev/null)"
  if [[ "$lab_lock" == "$(cat "$REPO_DIR/machine/mise.lock")" ]]; then
    echo "lock file unchanged: $(grep -c '^\[\[' "$REPO_DIR/machine/mise.lock") tools at the locked versions"
  else
    echo "rehearse: the install changed machine/mise.lock" >&2; exit 1
  fi
}

main() {
  step "empty lab" rebuild_lab
  step "copy machine/ into the lab" copy_machine_dir
  step "health check on the empty machine (must fail)" verify_must_fail
  step "install" install
  restart_lab
  step "health check after install" verify
  step "apply a second time (must change nothing)" apply_again
  step "machine description" describe
  step "lock file" compare_lock_file
}

main "$@"
