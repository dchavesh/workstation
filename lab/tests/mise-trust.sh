#!/usr/bin/env bash
# Question: when an agent enters a repo nobody has approved, which mise
# commands run that repo's script? Compared for mise's default settings and
# for paranoid mode, which this machine uses.
#
# "ran" means the repo's script executed. "refused" means it did not.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="mise-trust"
readonly QUESTION="Which mise commands run an unapproved repo's script, by default and in paranoid mode?"

measure() {
  cat <<'IN_LAB'
readonly REPO="$HOME/t/trust-test"
readonly MARKER="$REPO/RAN"
rm -rf "$REPO" && mkdir -p "$REPO" && cd "$REPO"
printf 'touch "%s"\n' "$MARKER" >hook.sh
with_script() { printf '[tools]\nnode = "lts"\n\n[env]\n_.source = "./hook.sh"\n' >mise.toml; }
without_script() { printf '[tools]\nnode = "lts"\n' >mise.toml; }
mode_name() { if [[ "$1" == 1 ]]; then echo paranoid; else echo default; fi; }
outcome() { if [[ -e "$MARKER" ]]; then echo ran; else echo refused; fi; }

# try <case> <mode> <command...>: first contact with the repo, never approved.
try() {
  local name="$1" mode="$2"; shift 2
  with_script
  mise trust --untrust "$REPO/mise.toml" >/dev/null 2>&1
  rm -f "$MARKER"
  env MISE_PARANOID="$mode" "$@" >/dev/null 2>&1 </dev/null
  fact "${name}_$(mode_name "$mode")" "$(outcome)"
}

# The owner approves a harmless config; the repo then gains a script.
approved_then_edited() {
  local mode="$1"
  without_script
  env MISE_PARANOID="$mode" mise trust "$REPO/mise.toml" >/dev/null 2>&1
  with_script
  rm -f "$MARKER"
  env MISE_PARANOID="$mode" node --version >/dev/null 2>&1 </dev/null
  fact "approved_then_edited_$(mode_name "$mode")" "$(outcome)"
}

for mode in 0 1; do
  try tool_call_through_shim "$mode" node --version
  try mise_env "$mode" mise env
  try mise_exec "$mode" mise exec -- true
  try mise_install "$mode" mise install
  try ci_variable_set "$mode" env CI=1 mise env
  approved_then_edited "$mode"
done
cd "$HOME" && rm -rf "$REPO"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
