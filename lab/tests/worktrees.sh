#!/usr/bin/env bash
# Question: can several agents work in one repository at the same time, each
# in its own working copy (a git worktree), sharing the machine's package
# caches, without colliding? And what does each extra working copy cost?
#
# The repository is a throwaway with one npm dependency (typescript) and one
# Python dependency (requests).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="worktrees"
readonly QUESTION="Can several agents share one repository through git worktrees and shared package caches without colliding?"

measure() {
  cat <<'IN_LAB'
readonly ROOT="$HOME/t/worktrees"
readonly AGENTS=3
rm -rf "$ROOT" && mkdir -p "$ROOT/repo" && cd "$ROOT/repo"
megabytes() { du -sm "$@" 2>/dev/null | tail -1 | cut -f1; }
# megabytes_together <paths...>: files shared by hard links are counted once.
megabytes_together() { du -smc "$@" 2>/dev/null | tail -1 | cut -f1; }

# --- a small repository with pinned tools and two kinds of dependencies
git init -q && git config user.email "test@example.com" && git config user.name "Lab test"
printf '[tools]\nnode = "lts"\n' >mise.toml && mise trust -q mise.toml
npm init -y >/dev/null 2>&1 && npm install --silent typescript >/dev/null 2>&1
printf '[project]\nname = "worktree-test"\nversion = "0.1.0"\nrequires-python = ">=3.12"\ndependencies = ["requests"]\n' >pyproject.toml
uv lock -q 2>/dev/null
printf 'node_modules/\n.venv/\n' >.gitignore
git add -A && git commit -q -m "initial"
fact repository_history_mb "$(megabytes .git)"

# --- one working copy per agent
fact create_one_worktree_ms "$(elapsed_ms git worktree add -q "$ROOT/agent-1" -b agent-1)"
for agent in $(seq 2 "$AGENTS"); do git worktree add -q "$ROOT/agent-$agent" -b "agent-$agent"; done
fact worktree_mb_before_dependencies "$(megabytes "$ROOT/agent-1")"
fact same_branch_in_two_worktrees_refused "$(yes_no sh -c "! git worktree add -q '$ROOT/duplicate' agent-1")"

# --- does a new working copy need a new approval before tools run in it?
fact tools_run_in_new_worktree_without_approval "$(cd "$ROOT/agent-1" && yes_no node --version)"
for agent in $(seq "$AGENTS"); do mise trust -q "$ROOT/agent-$agent/mise.toml"; done
fact tools_run_in_worktree_after_approval "$(cd "$ROOT/agent-1" && yes_no node --version)"

# --- dependencies: first with empty caches, then all agents at once
npm cache clean --force >/dev/null 2>&1; uv cache clean -q >/dev/null 2>&1
fact npm_install_empty_cache_ms "$(cd "$ROOT/agent-1" && elapsed_ms npm ci)"
fact uv_install_empty_cache_ms "$(cd "$ROOT/agent-1" && elapsed_ms uv sync)"
rm -rf "$ROOT/agent-1/node_modules" "$ROOT/agent-1/.venv"

# in_parallel <label> <command...>: run it in every worktree at the same time.
in_parallel() {
  local label="$1" agent slowest=0 succeeded=0 ms; shift
  for agent in $(seq "$AGENTS"); do
    ( cd "$ROOT/agent-$agent" && started=$(date +%s%N) && "$@" >/dev/null 2>&1; echo "$? $(( ($(date +%s%N) - started) / 1000000 ))" >"$ROOT/$label-$agent.result" ) &
  done
  wait
  for agent in $(seq "$AGENTS"); do
    read -r status ms <"$ROOT/$label-$agent.result"
    [[ "$status" == 0 ]] && succeeded=$((succeeded + 1))
    (( ms > slowest )) && slowest=$ms
  done
  fact "${label}_agents_succeeded" "$succeeded"
  fact "${label}_slowest_ms" "$slowest"
}
in_parallel npm_install_at_once npm ci
in_parallel uv_install_at_once uv sync
fact agents "$AGENTS"

# --- what each working copy costs on disk
fact node_modules_one_worktree_mb "$(megabytes "$ROOT/agent-1/node_modules")"
fact node_modules_all_worktrees_mb "$(megabytes_together "$ROOT"/agent-*/node_modules)"
fact python_environment_one_worktree_mb "$(megabytes "$ROOT/agent-1/.venv")"
fact python_environment_all_worktrees_mb "$(megabytes_together "$ROOT"/agent-*/.venv)"

# --- every agent commits on its own branch at the same moment
commit_work() { echo "work" >"result.txt" && git add result.txt && git commit -q -m "work from $(basename "$PWD")"; }
in_parallel commit_at_once commit_work
fact commits_in_repository "$(git -C "$ROOT/repo" log --all --oneline | wc -l)"
fact repository_passes_integrity_check "$(yes_no git -C "$ROOT/repo" fsck --no-progress)"

cd "$HOME" && rm -rf "$ROOT"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
