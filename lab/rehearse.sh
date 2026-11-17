#!/usr/bin/env bash
# Full rehearsal: throw the lab away, build it from an empty Ubuntu image
# using only machine/, and check the result. Run from the daily distro:
#
#   lab/rehearse.sh
#
# The health check runs before the install (it must fail) and after (it must
# pass). The install must leave machine/mise.lock exactly as the repo has it.
#
# Every run leaves a record under data/runs/<time>-rehearsal/:
#   rehearsal.json       the steps, how long each took, and the outcome
#   verify-before.json   every check on the empty machine
#   verify-after.json    every check, measured values and the machine description
#   rehearsal.log        what was printed
set -euo pipefail

readonly RECORD_SCHEMA_VERSION=1
readonly LAB="lab"
readonly REPO_IN_LAB="projects/personal/systems/workstation" # relative to the lab user's home
readonly ENVIRONMENT="wsl"
readonly LAB_RESULT_BEFORE="/var/tmp/verify-before.json"
readonly LAB_RESULT_AFTER="/var/tmp/verify-after.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$REPO_DIR/data/runs/$RUN_ID-rehearsal"
readonly SCRIPT_DIR REPO_DIR RUN_ID RUN_DIR

step_records=()
lock_file_unchanged="unknown"

lab() { "$SCRIPT_DIR/lab" "$@"; }
in_lab() { lab user /dev/stdin 2>&1 | tr -d '\0'; }
from_lab() { wsl.exe -d "$LAB" --cd '~' -- cat "$1" </dev/null; }

step() {
  local title="$1" started; shift
  started=$(date +%s)
  printf '\n=== %s\n' "$title"
  "$@"
  local seconds=$(( $(date +%s) - started ))
  step_records+=("$title"$'\t'"$seconds")
  printf -- '--- %s: %d s\n' "$title" "$seconds"
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

# verify <result file in the lab> <file to save it as>
verify() {
  local status=0
  in_lab <<<"bash ~/$REPO_IN_LAB/machine/verify.sh --json $1" || status=$?
  from_lab "$1" >"$RUN_DIR/$2" 2>/dev/null || echo "rehearse: no result file for $2" >&2
  return "$status"
}

verify_must_fail() {
  if verify "$LAB_RESULT_BEFORE" verify-before.json | tail -4; then
    echo "rehearse: the check passed on an empty machine; it proves nothing" >&2
    exit 1
  fi
}

verify_must_pass() { verify "$LAB_RESULT_AFTER" verify-after.json; }

install() {
  in_lab <<<"bash ~/$REPO_IN_LAB/machine/install.sh $ENVIRONMENT" |
    grep -v -E '^(Get|Hit|Ign|Fetched|Reading|Building|Selecting|Preparing|Unpacking|Setting up|Processing|\(Reading|Created symlink|  [a-z0-9])' | tail -40
}

restart_lab() { lab stop >/dev/null; }

apply_again() { in_lab <<<'zsh -c "mise bootstrap"' | tail -4; }

# The install must not move any locked version. If the lab's lock file differs
# from the repo's, the build was not reproducible.
compare_lock_file() {
  if [[ "$(from_lab "$REPO_IN_LAB/machine/mise.lock")" == "$(cat "$REPO_DIR/machine/mise.lock")" ]]; then
    lock_file_unchanged="true"
    echo "lock file unchanged: $(grep -c '^\[\[' "$REPO_DIR/machine/mise.lock") tools at the locked versions"
  else
    lock_file_unchanged="false"
    echo "rehearse: the install changed machine/mise.lock" >&2
    exit 1
  fi
}

write_record() {
  local exit_status="$1"
  printf '%s\n' "${step_records[@]}" |
    RECORD_RUN_ID="$RUN_ID" SCHEMA_VERSION="$RECORD_SCHEMA_VERSION" EXIT_STATUS="$exit_status" \
      LOCK_FILE_UNCHANGED="$lock_file_unchanged" COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || true)" \
      DIRTY="$(git -C "$REPO_DIR" status --porcelain -- machine lab 2>/dev/null | wc -l)" python3 -I -c '
import json, os, sys
steps = [{"name": name, "seconds": int(seconds)} for name, seconds in (line.rstrip("\n").split("\t") for line in sys.stdin if "\t" in line)]
lock = os.environ["LOCK_FILE_UNCHANGED"]
print(json.dumps({
    "schema_version": int(os.environ["SCHEMA_VERSION"]),
    "kind": "rehearsal",
    "run_id": os.environ["RECORD_RUN_ID"],
    "result": "passed" if os.environ["EXIT_STATUS"] == "0" else "failed",
    "repo_commit": os.environ["COMMIT"] or None,
    "uncommitted_files": int(os.environ["DIRTY"]),
    "lock_file_unchanged": {"true": True, "false": False}.get(lock),
    "total_seconds": sum(step["seconds"] for step in steps),
    "steps": steps,
}, indent=2))' >"$RUN_DIR/rehearsal.json"
}

finish() {
  local exit_status=$?
  write_record "$exit_status"
  printf '\nrecord: %s (%s)\n' "${RUN_DIR#"$REPO_DIR"/}" "$([[ $exit_status -eq 0 ]] && echo passed || echo failed)"
}

run() {
  step "empty lab" rebuild_lab
  step "copy machine/ into the lab" copy_machine_dir
  step "health check on the empty machine (must fail)" verify_must_fail
  step "install" install
  restart_lab
  step "health check after install" verify_must_pass
  step "apply a second time (must change nothing)" apply_again
  step "lock file" compare_lock_file
}

main() {
  mkdir -p "$RUN_DIR"
  trap finish EXIT
  # Not a pipe: run must stay in this shell so finish can see what it recorded.
  run > >(tee "$RUN_DIR/rehearsal.log") 2>&1
}

main "$@"
