# Baseline: the machine before the redesign

Measured on 2026-11-11 and 2026-11-13 on the daily distro. Facts only; every
later result is compared against these.

## Machine

| Item | Value |
|------|-------|
| Host | Windows 11 build 26300, Windows Terminal |
| WSL | 3.0.5.0, kernel 6.18.58.1, WSLg 1.0.79 |
| Distro | Ubuntu 24.04, systemd 255, `systemd=true` |
| Hardware | i5-12400 (6 cores / 12 threads), 16 GB RAM |
| `.wslconfig` | processors=8, memory=9GB, swap=8GB, vmIdleTimeout=120000, autoMemoryReclaim=gradual, sparseVhd=true |
| Disk | 101 GB used on the distro's virtual disk; 31 git repos under `~/projects` |
| Drive C: | NVMe SSD, 476 GB, 67.6 GB free. Holds the distro's virtual disk (119.8 GB) and Docker Desktop's data disk (116.6 GB) |
| Drive D: | SATA hard disk, 1863 GB, empty |
| Other distros | `docker-desktop` (Docker Desktop on Windows) |

## Boot

| Measure | Value |
|---------|-------|
| Healthy boot, systemd startup | 1.6 s (2026-11-11 09:57), 2.2 s (2026-11-13) |
| Failed boot, systemd startup | 20.3 s (2026-11-11 09:49) |
| `systemd-tmpfiles-setup`, failed boot | 16.3 s (healthy: 0.02 s) |
| Background work after boot | `apt-daily` 12.2 s, `apt-daily-upgrade` 5.3 s |
| Linger for the user | off |

The failed boot, from the journal:

- `WaitForBootProcess: /sbin/init failed to start within 10000ms` at 10 s.
- WSL ran `login` anyway; `systemd-logind` started 6 s later, so no session
  was registered.
- `CreateLoginSession: Timed out waiting for user session for uid=1000`.
- `/run/user/1000` was never created for that boot. `fnm env` failed in every
  shell and `node` was missing from `PATH`.

The cause of the stall was first recorded here as "on the Windows side and not
known". That was wrong: it is `systemd-tmpfiles-setup` emptying `/tmp` at
boot. See `01-host-and-boot.md`.

Enabled services on the stock image that a workstation may not need:
cloud-init (4 units), snapd (6), landscape-client, wsl-pro, apport,
unattended-upgrades, ubuntu-advantage, rsyslog, motd-news.

## Shell

| Measure | Value |
|---------|-------|
| Interactive zsh startup | 0.93 s first run, 0.15 s after |
| Framework | oh-my-zsh, 9 plugins, Powerlevel10k with instant prompt |
| `ssh-agent` processes running | 4 (one started per terminal by `.zshrc`) |
| SSH keys | 4, one per identity; `ssh-add` runs on all of them in every new terminal |

A second recurring error, reported by the owner:
`compinit:527: no such file or directory: /usr/share/zsh/vendor-completions/_docker`.
Docker Desktop places 23 symlinks in the distro (`/usr/bin/docker`, the
compose and CLI plugins, shell completions) that point into
`/mnt/wsl/docker-desktop/`. That path exists only while Docker Desktop is
running. When it is stopped every link dangles, and zsh reports the error
whenever it rebuilds its completion cache.

## Tools

Install mechanisms in use: apt, Homebrew (one tool, `glab`), snap (nothing),
fnm's install script, `npm -g`, uv's install script, `uv tool`, `pip --user`,
a Go tarball in `/usr/local`, rustup, vendor scripts for AWS and Azure.

Claude Code is installed inside Node v24.14.1's directory, so switching Node
versions with fnm removes it.

Not covered by the old bootstrap scripts: Homebrew, micromamba, the Jupyter
stack in `~/.local/bin`, gitleaks, tools installed with `uv tool`.

## What an agent sees

A non-interactive zsh started from a clean environment:

| Found | Missing |
|-------|---------|
| git, gh, glab, java, python3 | node, npm, pnpm, claude, uv, go, cargo, just, pre-commit |

Aliases active in the agent's shell: `ls` runs `eza --icons`, `cat` runs
`batcat --style=plain`, `fd` runs `fdfind`.
