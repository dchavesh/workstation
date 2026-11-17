# Track 4: Keys and secrets

**Decision for the owner's keys: passphrase-protected keys in WSL with the
socket-activated agent.** The owner answered on 2026-11-13: no hardware
security key, no password manager with an SSH agent (wanted later, not now).
The agents' credentials and the secrets part stay pending on track 3.

**Reopened on 2026-11-16.** The Daedalus plan records that the owner barely
uses SSH and prefers `gh` and `glab` (its machine diagnostic of 30 Oct: all
five SSH aliases fail, the agent is empty), and its global CLAUDE.md will say
"gh/glab instead of SSH". If that is the owner's real workflow, the simpler
design is HTTPS through `gh` and `glab` with no SSH keys for git at all. Open
question for the owner; to verify in that case: whether `gh` picks the right
account per directory when git passes a username from an `includeIf` block.

Lab test with fake tokens, 2026-11-16 (gh 2.103.3, mise in paranoid mode):

| Setup | Result |
|-------|--------|
| One `gh` config holding two accounts; git asks for the second by username | nothing returned — `gh` serves only the active account |
| One `gh` config per identity, chosen by a `GH_CONFIG_DIR` line in that identity directory's `mise.toml` | `gh` and `git credential fill` both return the right account in each directory |
| Same, outside every identity directory | no token — it fails closed |
| `gh auth token` inside `srt` when the token file is not on the deny list | **prints the token** |

So HTTPS through `gh`/`glab` can carry all four identities with no SSH key,
using one rule: the directory decides the identity (git email through
`includeIf`, credentials and the CLI through `GH_CONFIG_DIR`).

**Recommendation, awaiting the owner:** `gh`/`glab` only for git; no SSH keys
for git. A second mechanism adds a second credential to protect and little
redundancy: the fallback when a token breaks is a new browser login, not a
key on disk. SSH keys only where SSH is the only way in (servers), added when
first needed.

To pass on to Daedalus: its sandbox deny list names `~/.ssh`, `~/.aws` and
`~/.gitconfig` but not the `gh` and `glab` config directories, where WSL keeps
tokens in plain text. They must be on it.

Confirmed by the plan and by the lab: credentials live outside the sandbox
(P3); only short-lived, repository-scoped tokens go inside; and environment
variables pass straight into `srt`, so nothing secret may be exported by the
shell. The API key for unattended runs needs a store outside the sandbox that
Daedalus's `apiKeyHelper` can read.

## Question

Four SSH identities ask for passphrases in every new terminal, and every
process inherits every API token from `~/.zshrc.local`. What should replace
both, on a machine where agents run as the owner's user?

## What the sources say

Read on 2026-11-13 by a research pass. *docs* = official documentation.

**SSH**

- `ssh-agent` supports systemd socket activation since OpenSSH 10.0, and
  Ubuntu ships a user socket unit at `$XDG_RUNTIME_DIR/openssh_agent`.
  `AddKeysToAgent` accepts `yes`, `confirm` or a lifetime. *docs* —
  <https://www.openssh.org/releasenotes.html>, <https://man.openbsd.org/ssh_config>
- The Windows `ssh-agent` keeps keys in the Windows account and they cannot be
  read back. *docs* — <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement>
- 1Password's documented WSL route is `ssh.exe` through interop, with the SSH
  config on the Windows side. A process can sign but cannot export the key.
  *docs* — <https://www.1password.dev/ssh/integrations/wsl/>
- Bitwarden's SSH agent documentation does not mention WSL. *docs*
- Hardware-key SSH keys work from WSL2 through Windows' helper; with
  verification required they need a PIN and a touch on every use. *docs* —
  <https://developers.yubico.com/SSH/Securing_SSH_and_git_with_FIDO2_on_WSL2.html>
- GitHub calls SSH signatures the simplest way to sign commits. *docs*

**Secrets**

- `gh` and `glab` use the system keyring and fall back to plain text; on WSL
  `gh` does so silently. Azure CLI caches tokens in plain text on Linux. *docs*
- AWS ranks short-term credentials first and long-term keys "not recommended". *docs*
- `sops exec-env` gives decrypted values only to the child process it starts;
  SOPS recommends age for encryption. *docs* — <https://getsops.io/docs/usage/advanced/>
- mise's secret handling is experimental. *docs*
- 1Password: assume processes of the same user can read each other's
  environment; use service accounts scoped to a vault. *docs*
- For automation, GitHub recommends one-hour app tokens, fine-grained tokens
  over classic ones, and deploy keys scoped to one repository. *docs* —
  <https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys>
- Anthropic recommends keeping credentials outside the agent's boundary. *docs* —
  <https://code.claude.com/docs/en/agent-sdk/secure-deployment>

**The point that shapes everything else:** an SSH agent or a keyring stops a
key being *copied*, not *used*. Any process running as the owner can ask the
agent socket to sign, or run `gh auth token`. *inference*

## Lab results

Ubuntu 26.04.1 in the `lab` distro, 2026-11-13.

| Test | Result |
|------|--------|
| OpenSSH version | 10.2 |
| `ssh-agent.socket` user unit | shipped and enabled by default |
| Agent processes before first use | 0 — it starts on demand |
| Add a passphrase-protected test key once | 1 agent process |
| A second, separate session | same agent, key still loaded, still 1 process |
| `ssh-add` with `SSH_AUTH_SOCK` unset | fails — the variable must be exported |
| TPM device in WSL | none |

Compared with today: one agent instead of one per terminal, started only when
used, and a key is unlocked once per WSL boot instead of once per terminal.

## Candidate

- **Owner:** passphrase-protected keys in WSL, the shipped socket-activated
  agent, `SSH_AUTH_SOCK` exported from `.zshenv`, `AddKeysToAgent yes`, and
  SSH commit signing per identity. No bridge to Windows.
- **Agents:** their own narrow credentials — a deploy key per repository or an
  expiring fine-grained token — and the owner's keys, CLI logins and the agent
  socket kept outside whatever boundary track 3 chooses.
- **Secrets:** no global exports. Encrypted per-project files (sops + age),
  decrypted only for the command that needs them. Short-term cloud logins.

**What would change it:**

- A password manager with an SSH agent, if the owner adopts one later: its
  agent gives a better restore story after a format, at the cost of routing
  SSH through Windows. Nothing in the candidate blocks that move.
- A hardware security key, if the owner buys one: use it for the organisation
  identities.
- The sandbox failing to hide the agent socket: move agents to a separate
  Linux user or a container.

## To run

1. `AddKeysToAgent yes` against a real host, in two terminals, then after
   `wsl --shutdown`.
2. From inside each isolation option: read a key file, list the agent's keys,
   print tokens from the environment, run `gh auth token`. All should fail.
3. `sops exec-env` with an age key: confirm a sibling process cannot read the
   values.
4. Commit signing with an SSH key under each `includeIf` identity.

## Not verified

- Windows Hello and TPM-backed keys from WSL (community reports only).
- Whether `ssh` itself falls back to the socket when the variable is unset.
- Whether Claude Code's sandbox blocks Unix sockets by default on WSL2.
