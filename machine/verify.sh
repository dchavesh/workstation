#!/usr/bin/env bash
# Health check: is this machine what machine/config.toml describes, and does
# it keep its promises to agents? Read-only apart from a scratch directory it
# removes. Exit 0 when every check passes, 1 otherwise.
#
#   machine/verify.sh                 print the result
#   machine/verify.sh --json FILE     also write it as data: every check, every
#                                     measured value, and the machine it ran on
set -uo pipefail

readonly RESULT_SCHEMA_VERSION=1
readonly REQUIRED_COMMANDS=(claude git curl jq rg zsh node uv gh glab just pre-commit gitleaks starship docker bwrap socat)
readonly MAX_SHELL_STARTUP_MS=300
readonly SECRET_NAME_PATTERN='(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY)'
readonly SRT_BIN="/usr/local/bin/srt"
readonly SYSTEM_NODE="/usr/bin/node"
readonly ALLOWED_HOST="api.anthropic.com"
readonly UNLISTED_URL="https://example.com"
readonly WINDOWS_PROGRAM="/mnt/c/Windows/System32/cmd.exe"
readonly WSL_CONF="/etc/wsl.conf"
readonly BASE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly FIELD=$'\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
login_user="$(id -un)"
runtime_dir="/run/user/$(id -u)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly SCRIPT_DIR login_user runtime_dir started_at

json_file=""
current_section=""
failures=0
records=()

# Turns the tab-separated records on stdin into one JSON document.
readonly JSON_WRITER='
import datetime, json, os, sys
checks, metrics = [], []
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if parts[0] == "check" and len(parts) >= 5:
        checks.append({"section": parts[1], "name": parts[2], "ok": parts[3] == "true", "detail": parts[4] or None})
    elif parts[0] == "metric" and len(parts) >= 4:
        metrics.append({"name": parts[1], "value": float(parts[2]), "unit": parts[3]})
try:
    machine = json.loads(os.environ.get("MACHINE_JSON") or "{}")
except json.JSONDecodeError:
    machine = {}
print(json.dumps({
    "schema_version": int(os.environ["SCHEMA_VERSION"]),
    "kind": "verify",
    "started_at": os.environ["STARTED_AT"],
    "finished_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "failures": int(os.environ["FAILURES"]),
    "checks": checks,
    "metrics": metrics,
    "machine": machine,
}, indent=2))
'

section() { current_section="$1"; printf '%s\n' "$1"; }

pass() {
  printf '  ok    %s\n' "$1"
  records+=("check${FIELD}${current_section}${FIELD}$1${FIELD}true${FIELD}")
}

fail() {
  printf '  FAIL  %s%s\n' "$1" "${2:+  ($2)}"
  records+=("check${FIELD}${current_section}${FIELD}$1${FIELD}false${FIELD}${2:-}")
  failures=$((failures + 1))
}

# metric <name> <value> <unit>: a measured number, kept beside the checks.
metric() {
  printf '        %s: %s %s\n' "$1" "$2" "$3"
  records+=("metric${FIELD}$1${FIELD}$2${FIELD}$3")
}

# expect <name> <command...>: passes when the command succeeds.
expect() {
  local name="$1" out; shift
  if out="$("$@" 2>&1)"; then pass "$name"; else fail "$name" "$(head -1 <<<"$out" | tr '\t' ' ' | cut -c1-90)"; fi
}

# refuse <name> <command...>: passes when the command fails.
refuse() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name" "it was allowed"; else pass "$name"; fi
}

is_wsl() { grep -qi microsoft /proc/version; }

parse_arguments() {
  while (( $# > 0 )); do
    case "$1" in
      --json) json_file="${2:?--json needs a file path}"; shift 2 ;;
      *) echo "verify: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
}

# Re-run this script with the environment a fresh non-interactive zsh has: no
# terminal, nothing inherited. That is what an agent or a script gets.
enter_clean_environment() {
  [[ -n "${VERIFY_CLEAN:-}" ]] && return
  if ! command -v zsh >/dev/null; then section "Shell"; fail "zsh is installed"; return; fi
  exec env -i HOME="$HOME" USER="$login_user" LOGNAME="$login_user" XDG_RUNTIME_DIR="$runtime_dir" \
    PATH="$BASE_PATH" VERIFY_CLEAN=1 zsh -c 'exec bash "$0" "$@"' "$SCRIPT_DIR/verify.sh" "$@"
}

check_boot() {
  section "Boot"
  expect "the user session exists" test -d "$runtime_dir"
  expect "user services survive the last terminal (linger)" test -e "/var/lib/systemd/linger/$login_user"
  expect "/tmp is on disk, not in memory" test "$(findmnt -no FSTYPE -T /tmp)" != tmpfs
  if is_wsl; then
    expect "WSL waits for a slow boot (initTimeout)" grep -qx 'initTimeout=60000' "$WSL_CONF"
    expect "Windows directories are kept off PATH" grep -qx 'appendWindowsPath=false' "$WSL_CONF"
  fi
}

startup_ms() {
  local started; started=$(date +%s%N)
  zsh -ic exit >/dev/null 2>&1 </dev/null
  echo $(( ($(date +%s%N) - started) / 1000000 ))
}

# Names of aliases that would run instead of a program on PATH (ls, cat, ...).
# zsh's own run-help and which-command hide nothing and are not listed.
shadowing_aliases() {
  zsh "$@" -c 'for name in ${(k)aliases}; do whence -p -- $name >/dev/null && print -r -- $name; done' 2>/dev/null </dev/null | tr '\n' ' '
}

check_shell() {
  section "Shell"
  expect "the login shell is zsh" test "$(getent passwd "$login_user" | cut -d: -f7)" = /usr/bin/zsh
  expect "no alias hides a real command (non-interactive shell)" test -z "$(shadowing_aliases)"
  expect "no alias hides a real command (interactive shell)" test -z "$(shadowing_aliases -i)"
  expect "an interactive shell starts without printing" test -z "$(zsh -ic exit 2>&1 </dev/null)"
  startup_ms >/dev/null
  local ms; ms="$(startup_ms)"
  expect "an interactive shell starts in under ${MAX_SHELL_STARTUP_MS} ms" test "$ms" -lt "$MAX_SHELL_STARTUP_MS"
  metric "interactive_shell_startup" "$ms" "ms"
  case ":$PATH:" in
    *:/mnt/*) fail "no Windows directory is on PATH" ;;
    *) pass "no Windows directory is on PATH" ;;
  esac
}

check_tools() {
  section "Tools"
  local missing=() name
  for name in "${REQUIRED_COMMANDS[@]}"; do command -v "$name" >/dev/null || missing+=("$name"); done
  if (( ${#missing[@]} == 0 )); then pass "a clean shell finds every tool"; else fail "a clean shell finds every tool" "missing: ${missing[*]}"; fi
  metric "tools_required" "${#REQUIRED_COMMANDS[@]}" "count"
  expect "the machine matches its config (no drift)" mise bootstrap status --missing
  expect "tool versions are locked" test -s "$HOME/.config/mise/mise.lock"
  if is_wsl; then expect "a chosen Windows program starts by name" powershell.exe -NoProfile -Command 'exit 0'; fi
}

check_secrets() {
  section "Secrets"
  local names
  names="$( { env; zsh -ic env 2>/dev/null </dev/null; } | cut -d= -f1 | grep -E "$SECRET_NAME_PATTERN" | sort -u | tr '\n' ' ')"
  if [[ -z "$names" ]]; then pass "no shell exports a secret"; else fail "no shell exports a secret" "found: $names"; fi
}

check_docker() {
  section "Docker"
  expect "docker wakes on first use" test "$(systemctl is-enabled docker.socket 2>&1)" = enabled
  expect "docker does not start at boot" test "$(systemctl is-enabled docker.service 2>&1)" = disabled
}

sandbox_startup_ms() {
  local started; started=$(date +%s%N)
  box true >/dev/null 2>&1
  echo $(( ($(date +%s%N) - started) / 1000000 ))
}

check_sandbox() {
  section "Sandbox for agents"
  if [[ ! -e "$SRT_BIN" ]]; then fail "the sandbox runtime is installed"; return; fi
  local scratch decoy settings runtime
  runtime="$(readlink -f "$SRT_BIN")"
  scratch="$(mktemp -d "$HOME/.verify-sandbox.XXXXXX")"
  decoy="$scratch/decoy-secret"
  settings="$scratch/settings.json"
  echo "decoy" >"$decoy"
  printf '{"network":{"allowedDomains":["%s"],"deniedDomains":[]},"filesystem":{"denyRead":["%s"],"allowWrite":["."],"denyWrite":[]}}\n' \
    "$ALLOWED_HOST" "$decoy" >"$settings"
  box() { (cd "$scratch" && "$SYSTEM_NODE" "$SRT_BIN" --settings "$settings" -c "$1"); }

  expect "the runtime is owned by root" test "$(stat -c %U "$runtime")" = root
  refuse "the login user cannot rewrite the runtime" test -w "$(dirname "$runtime")"
  expect "it starts on this kernel" box true
  metric "sandbox_startup" "$(sandbox_startup_ms)" "ms"
  expect "tools work inside it" box 'node --version && gh --version && uv --version'
  refuse "a denied file cannot be read" box "cat '$decoy'"
  refuse "nothing outside the project can be written" box "touch '$HOME/.verify-escape'"
  refuse "an unlisted host cannot be reached" box "curl -fsS -m 8 -o /dev/null $UNLISTED_URL"
  refuse "docker cannot be reached" box 'docker ps'
  if is_wsl; then refuse "Windows programs cannot be started" box "$WINDOWS_PROGRAM /c ver"; fi
  rm -rf "$scratch" "$HOME/.verify-escape"
}

write_json() {
  [[ -n "$json_file" ]] || return 0
  local machine
  machine="$("$SCRIPT_DIR/describe" 2>/dev/null || echo '{}')"
  printf '%s\n' "${records[@]}" |
    MACHINE_JSON="$machine" SCHEMA_VERSION="$RESULT_SCHEMA_VERSION" STARTED_AT="$started_at" FAILURES="$failures" \
      python3 -c "$JSON_WRITER" >"$json_file" || echo "verify: could not write $json_file" >&2
}

main() {
  parse_arguments "$@"
  enter_clean_environment "$@"
  check_boot
  check_shell
  check_tools
  check_secrets
  check_docker
  check_sandbox
  write_json
  if (( failures > 0 )); then printf '\n%d check(s) failed\n' "$failures"; exit 1; fi
  printf '\nall checks passed\n'
}

main "$@"
