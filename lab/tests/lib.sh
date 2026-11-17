#!/usr/bin/env bash
# Shared by the saved tests in this directory. Sourced, never run.
#
# A test resets the facts file, runs scripts inside the lab that append facts
# ("name<TAB>value"), and calls write_test_record, which turns the facts and
# the lab's machine description into data/runs/<time>-<test>/result.json.
#
# The tests expect a lab that lab/rehearse.sh has built.

readonly TEST_SCHEMA_VERSION=1
readonly TEST_LAB_NAME="lab"
readonly TEST_FACTS="/var/tmp/test-facts.tsv"
readonly TEST_DESCRIBE='zsh -c ~/projects/personal/systems/workstation/machine/describe'

TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_REPO_DIR="$(dirname "$(dirname "$TEST_LIB_DIR")")"
TEST_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TEST_RUN_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
readonly TEST_LIB_DIR TEST_REPO_DIR TEST_STARTED_AT TEST_RUN_STAMP

test_lab() { "$TEST_REPO_DIR/lab/lab" "$@"; }

# What every lab-side script starts with.
#   fact <name> <value>       record one fact
#   elapsed_ms <command...>   run it quietly and print how long it took
#   yes_no <command...>       print true if it succeeds, false if not
lab_prelude() {
  printf 'FACTS=%q\n' "$TEST_FACTS"
  cat <<'PRELUDE'
set -uo pipefail
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
fact() { printf '%s\t%s\n' "$1" "$(tr '\n\t' '  ' <<<"${2-}" | cut -c1-400)" >>"$FACTS"; }
elapsed_ms() { local started; started=$(date +%s%N); "$@" >/dev/null 2>&1; echo $(( ($(date +%s%N) - started) / 1000000 )); }
yes_no() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }
PRELUDE
}

# Wraps a script so that the lab first saves it to a file and then runs the
# file. A script read from standard input loses the rest of its lines as soon
# as one of its commands reads standard input too (adb does), and then ends
# without an error.
saved_and_run() {
  echo 'script_file="/var/tmp/test-script.$(id -un).sh"'
  echo "cat >\"\$script_file\" <<'__LAB_SCRIPT__'"
  lab_prelude
  "$1"
  echo '__LAB_SCRIPT__'
  echo 'bash "$script_file" </dev/null'
}

# as_user <function that prints a script>: run that script in the lab.
as_user() { saved_and_run "$1" | test_lab user /dev/stdin; }
as_root() { saved_and_run "$1" | test_lab root /dev/stdin; }

reset_facts() { wsl.exe -d "$TEST_LAB_NAME" -u root --cd / -- sh -c ": > $TEST_FACTS; chmod 666 $TEST_FACTS" </dev/null; }

# A fact measured from outside the lab, such as how long it takes to start.
host_fact() { printf '%s\t%s\n' "$1" "$2" | wsl.exe -d "$TEST_LAB_NAME" -u root --cd / -- tee -a "$TEST_FACTS" >/dev/null; }

restart_lab() { test_lab stop >/dev/null; }

# write_test_record <test name> <question>
write_test_record() {
  local name="$1" question="$2" facts machine run_dir
  facts="$(wsl.exe -d "$TEST_LAB_NAME" --cd / -- cat "$TEST_FACTS" </dev/null 2>/dev/null || true)"
  if [[ -z "$facts" ]]; then
    echo "$name: the test produced no facts, so it did not run; no record written" >&2
    return 1
  fi
  machine="$(test_lab user /dev/stdin <<<"$TEST_DESCRIBE" 2>/dev/null | tr -d '\0' || true)"
  run_dir="$TEST_REPO_DIR/data/runs/$TEST_RUN_STAMP-$name"
  mkdir -p "$run_dir"
  printf '%s\n' "$facts" | RECORD_TEST="$name" RECORD_QUESTION="$question" RECORD_STARTED_AT="$TEST_STARTED_AT" \
    RECORD_SCHEMA="$TEST_SCHEMA_VERSION" RECORD_MACHINE="$machine" python3 -I -c '
import json, os, sys

def typed(value):
    value = value.strip()
    if value == "":
        return None
    if value in ("true", "false"):
        return value == "true"
    for convert in (int, float):
        try:
            return convert(value)
        except ValueError:
            pass
    return value

facts = {}
for line in sys.stdin:
    if "\t" in line:
        name, value = line.rstrip("\n").split("\t", 1)
        facts[name] = typed(value)
try:
    machine = json.loads(os.environ.get("RECORD_MACHINE") or "{}")
except json.JSONDecodeError:
    machine = {}
print(json.dumps({
    "schema_version": int(os.environ["RECORD_SCHEMA"]),
    "kind": "test",
    "test": os.environ["RECORD_TEST"],
    "question": os.environ["RECORD_QUESTION"],
    "started_at": os.environ["RECORD_STARTED_AT"],
    "facts": facts,
    "machine": machine,
}, indent=2))' >"$run_dir/result.json"
  echo "record: data/runs/$TEST_RUN_STAMP-$name"
  python3 -I -c 'import json, sys
for name, value in json.load(open(sys.argv[1]))["facts"].items(): print(f"  {name}: {value}")' "$run_dir/result.json"
}
