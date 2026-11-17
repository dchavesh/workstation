#!/usr/bin/env bash
# Question: can `gh` and git serve several GitHub identities over HTTPS, with
# no SSH key, picking the account from the project directory?
#
# Uses made-up accounts and made-up tokens. Nothing is sent to GitHub.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="gh-identities"
readonly QUESTION="Can gh and git pick the GitHub account from the project directory, without SSH keys?"

measure() {
  cat <<'IN_LAB'
readonly ROOT="$HOME/t/identity-test"
rm -rf "$ROOT" && mkdir -p "$ROOT"

# gh_config <directory> <active user> [more users...]
gh_config() {
  local directory="$1" user; shift
  mkdir -p "$directory"
  {
    echo "github.com:"; echo "    git_protocol: https"; echo "    users:"
    for user in "$@"; do echo "        $user:"; echo "            oauth_token: FAKE-TOKEN-OF-$user"; done
    echo "    user: $1"; echo "    oauth_token: FAKE-TOKEN-OF-$1"
  } >"$directory/hosts.yml"
}
# credential <extra request line> <helper command...>: the password git would get.
credential() { printf 'protocol=https\nhost=github.com\n%s\n' "$1" | "${@:2}" 2>/dev/null | grep '^password=' | cut -d= -f2; }

# One gh config holding two accounts; git asks for the one that is not active.
gh_config "$ROOT/gh-both" alice bob
fact one_config_token_for_active_account "$(GH_CONFIG_DIR="$ROOT/gh-both" credential '' gh auth git-credential get)"
fact one_config_token_for_second_account "$(GH_CONFIG_DIR="$ROOT/gh-both" credential 'username=bob' gh auth git-credential get)"

# One gh config per identity, chosen by a mise.toml in that identity's directory.
for identity in personal kolora; do
  gh_config "$ROOT/gh-$identity" "user-$identity"
  mkdir -p "$ROOT/$identity/repo" && git -C "$ROOT/$identity/repo" init -q
  printf '[env]\nGH_CONFIG_DIR = "%s"\n' "$ROOT/gh-$identity" >"$ROOT/$identity/mise.toml"
  mise trust -q "$ROOT/$identity/mise.toml"
  cd "$ROOT/$identity/repo"
  fact "${identity}_directory_gh_token" "$(gh auth token 2>/dev/null)"
  fact "${identity}_directory_git_credential" "$(GIT_TERMINAL_PROMPT=0 credential '' git credential fill)"
done
cd "$ROOT"
fact outside_identity_directories_token "$(gh auth token 2>/dev/null)"
cd "$HOME" && rm -rf "$ROOT"
IN_LAB
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
}

main "$@"
