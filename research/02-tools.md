# Track 2: Tools and project environments

**Decision: three install channels with mise at the centre, and mise's own
bootstrap instead of chezmoi. Both passed lab trials; a full rehearsal from an
empty distro is still to come.**

## Question

About ten install mechanisms are in use and nothing shows what is outdated.
What single, ordered rule covers installing, updating and pinning tools, for
the owner and for agents, without abandoning each tool's official install
documentation?

## What the sources say

Read on 2026-11-13 by a research pass. *docs* = official documentation.

- mise installs from publishers' own release files through several backends
  (GitHub and GitLab releases, npm, pipx, cargo, go and others). *docs* —
  <https://mise.jdx.dev/dev-tools/backends/>
- mise has a page for agents: shell activation in `.zshrc` never reaches an
  agent; it recommends a Claude Code session hook, with shims as the fallback.
  *docs* — <https://mise.jdx.dev/agents.html>
- `mise.lock` records a download URL and checksum per platform for most
  backends. *docs* — <https://mise.jdx.dev/security.html>
- `mise install`, `exec` and `run` approve the config they load, and a set
  `CI` variable approves everything. Paranoid mode removes both. *docs* — same page
- `mise bootstrap` and `[dotfiles]` (new in June 2026) declare apt packages,
  dotfiles, shell activation and systemd units. Some names are already
  scheduled for removal. *docs* — <https://mise.jdx.dev/bootstrap.html>
- chezmoi documents WSL detection but no recipe for one repo serving Windows
  and WSL, and says scripts "should be used sparingly". *docs* —
  <https://www.chezmoi.io/user-guide/machines/windows/>
- Claude Code reads `~/.zshrc` at session start and captures aliases and
  functions, sets `CLAUDECODE=1`, and applies `env` from its settings. *docs* —
  <https://code.claude.com/docs/en/tools-reference>
- Claude Code now has a signed apt repository. *docs* — <https://code.claude.com/docs/en/setup>

Alternatives, from the same pass: Nix, devbox, flox and pixi replace upstream
installers with their own packaging; Homebrew Bundle has no lock file; aqua
alone covers fewer runtimes and mise already uses its registry.

## Lab results

Ubuntu 26.04.1 in the `lab` distro, 2026-11-13.

| Test | Result |
|------|--------|
| Install mise from its documented apt source (`ppa:jdxcode/mise`) | works; mise 2026.11.7 in 23 s; updates arrive through apt |
| Install glab, gh, uv, just, pre-commit, gitleaks, chezmoi, starship, node | all nine in 6 s; the config is nine lines |
| Clean non-interactive shell, plain `PATH` | none of the tools found |
| Same shell with the shims directory on `PATH` | all found and working, no hooks needed |
| Per-directory versions through shims | parent 22, child 24, home 26 — correct in each |
| `[env]` values through shims | reach the tool, not the shell itself |
| Cost per tool call | direct 2.3 ms, through a shim 15.9 ms, `mise exec` 89.6 ms |
| Lock file | `mise lock --global` writes checksums for every platform |
| Update visibility | `mise outdated --bump` listed `just 1.40.0 → 1.59.0` |

### Trust: what runs in a repo nobody approved

The test repo's `mise.toml` sources a script. "Ran" means the script executed.

| First contact | Default settings | Paranoid mode |
|---------------|------------------|---------------|
| A tool call through a shim | refused, with a clear message | refused |
| `mise env` | refused | refused |
| `mise exec` | **ran** | refused |
| `mise install` | **ran** | refused |
| `CI=1 mise env` | **ran** | refused |
| Approved repo whose config is edited later to add a script | **ran** on the next tool call | refused until approved again |

By default, approval is tied to a path. In paranoid mode it is tied to the
file's contents, so a pulled branch or an edit cannot run code without a new
approval. A repo with tools only still works in paranoid mode once approved.

### Trial: one config for the machine (`mise bootstrap`)

A single `mise.toml` declared two apt packages, the login shell, a symlinked
`.zshrc`, a managed block in `.zshenv`, shims on `PATH` and two tools.

| Step | Result |
|------|--------|
| `mise bootstrap status` before | every part listed as missing, installed or differing |
| `mise bootstrap --dry-run` | printed the exact commands and edits, changed nothing |
| Apply | apt packages, symlink, both `.zshenv` blocks and tools applied in 6 s |
| Login shell | **failed**: mise runs `chsh` as the user, which needs a password and a terminal. `sudo chsh` worked. |
| Clean non-interactive zsh afterwards | node, glab, gh and uv found; `SSH_AUTH_SOCK` set; no aliases from `.zshrc` |
| Apply a second time | nothing changed; 0.13 s |
| Hand-edit a managed block and replace the symlink with a file | `status --missing` exits 1 and names both; `mise dot diff` shows the difference |
| Repair | `mise bootstrap` refuses to overwrite the hand-made file; `mise dot apply --force` restores it |

Limits found, from the documentation and the trial:

- It cannot enable a systemd unit that already exists (such as
  `ssh-agent.socket`); it manages only units it writes. On 26.04 that unit is
  enabled by default, so nothing is needed.
- Removing an apt entry from the config does not remove the package.
- `mise bootstrap plan` does not cover dotfiles, shell or tools; `--dry-run` does.
- The feature is five months old. Its older names are scheduled for removal in
  mise 2027.10.4. No experimental flag is required.

## Decisions

0. **One config for the machine.** `mise bootstrap` replaces both chezmoi and
   hand-written setup scripts for the Linux side. One tool then owns packages,
   dotfiles, shell setup and tools, and reports drift for all of them.

1. **Three channels, in order.**
   - apt: operating-system packages, and vendors' signed apt repositories
     (mise itself, Claude Code).
   - mise: every runtime and developer tool.
   - The vendor's installer: only for toolchains that manage themselves
     (Android CLI, ESP-IDF, PlatformIO).
2. **Shims on `PATH` for every process**, set in `.zshenv` and in systemd's
   `environment.d`. This is agent-agnostic and costs about 14 ms per call. The
   Claude Code session hook is an optional speed-up on the agent side.
3. **Paranoid mode on**, and `CI` never set in an agent's environment.
4. **Lock files committed**, global and per project.

## Changes after reading the Daedalus plan (2026-11-16)

- **The sandbox pieces are system packages, not mise tools.** bubblewrap,
  socat, ripgrep and a system Node come from apt; `srt` is installed by root
  into `/usr/local`. The plan requires a location the login user cannot
  write, and mise's directory is the user's. Tested in `03-isolation.md`.
- **Claude Code is installed by this repo and configured by Daedalus** (the
  owner's clarification, 2026-11-16). Tested in the lab: its official apt
  repository (stable channel, key fingerprint checked by mise) installed
  `claude` 2.1.311 as a root-owned package in 8 s, and created neither
  `~/.claude` nor `~/.claude.json`. apt installs never update themselves, so
  the version moves only on a machine upgrade; Daedalus can pin an exact
  version in `config.toml` for its comparison runs.
- **Moved to Daedalus:** the alias guard on `CLAUDECODE` and the
  output-quieting variables. Both are agent settings. This repo's part is
  that a non-interactive shell has no aliases at all (already true in the
  trial).

## Full rehearsal from an empty distro (2026-11-16)

`lab/rehearse.sh` destroys the lab, creates an empty Ubuntu 26.04, copies
`machine/` in, runs the health check (which must fail), runs
`machine/install.sh wsl`, restarts, and checks again.

| Step | Result |
|------|--------|
| Health check on the empty machine | 15 checks fail, as it must |
| Install (mise from its PPA, then `mise bootstrap`) | 103 s |
| Health check after install | all 27 checks pass, in 5 s |
| Apply a second time | nothing changes, 1 s |
| Lock file after install | identical to the repo's: 8 tools, checksums for 7 platforms |
| Interactive shell start-up | 63 ms |

What the machine is made of:

- `machine/config.toml` — mise's global config, because `~/.config/mise` is a
  symlink to `machine/`. It declares the Docker apt source (with its key
  fingerprint), 18 apt packages, the Docker socket, the login shell, the
  dotfiles, the `.zshenv` blocks and 8 tools.
- `machine/config.wsl.toml` — the WSL-only parts (`/etc/wsl.conf`, five
  Windows programs by name), loaded with `MISE_ENV=wsl`.
- `machine/system/post-packages.sh` — five root steps mise has no exact
  section for: the sandbox runtime in `/usr/local`, `/tmp` on disk, Docker
  not started at boot, the docker group, login shell and linger.
- `machine/verify.sh` — the health check. `machine/describe` — the machine
  as JSON.

Corrections to the trial above:

- mise's bootstrap covers more than the trial found: apt sources with key
  fingerprints, system files under `/etc`, and enabling or masking existing
  system units (`[bootstrap.services]`). The limit "cannot enable an existing
  unit" applies only to `linux systemd-units`.
- `[bootstrap.services]` always manages running state. Declaring the Docker
  daemon "stopped" would make every later `mise bootstrap` stop running
  containers, so only `docker.socket` is declared there.
- The lock file is used only if it already exists. It is created once with
  `mise lock --global` and committed.
- `{{config_root}}` is the home directory for the global config, not the
  config's directory.

Found on the way:

- Ubuntu's `npm` package, needed once to install `srt` as root, brings 373
  `node-*` packages (92 MB) and, through recommended packages, a graphical
  terminal. Alternatives: NodeSource's apt repository (one package, needs a
  pin), or building `srt` as the user and copying it to `/usr/local`. Open.
- Lab only: sudo asks no password there. On a real machine it will.

## Open

- **Not covered by the rehearsal:** the Windows side (`.wslconfig`, terminal,
  winget), the owner's real identities and logins (private values, kept out
  of the repo in `~/.config/git/identities`), GNU coreutils, Claude Code
  itself (Daedalus installs it).
- **The Windows side** (`.wslconfig`, Windows Terminal, winget). Whether mise
  on Windows can own it, or it stays a short script.
- **The login shell step** on the real machine, where a terminal and a
  password exist.
- Alias leakage into Claude Code's shell: test a guard on `CLAUDECODE`.
- Where output-quieting variables (`NO_COLOR`, `PAGER`, `GIT_PAGER`) belong:
  the research pass suggests agent settings, not the shell.

## Not verified

- The Claude Code apt repository on 26.04.
- mise bootstrap's behaviour beyond its help text.
- `azure-cli` through mise (it installs through pipx and locks the version only).
