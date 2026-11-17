# Track 3: Isolation — what an agent can read, change and reach

**Decision: taken by the owner in the Daedalus plan, not here.** Unattended
agents run inside Anthropic's sandbox runtime (`srt`) with the Bash sandbox
on, credentials outside, and network by allowlist. A microVM comes later, only
for repositories the owner does not trust. If `srt` cannot run a medium task
on WSL2, the fallback is a dev container with Docker. (Daedalus: T-19, T-11,
P3, P14, kill criterion K2.)

This page now answers a narrower question: can the machine host that
decision? **Yes, tested in the lab on 2026-11-16** (results below). The
sandbox profile, permissions and settings belong to Daedalus.

## Question

Every agent currently runs as the owner's Unix user, with read access to all
SSH keys, API tokens and projects. How should that be limited, while several
agents work in parallel and an agent can still install what a job needs?

## What the sources say

Read on 2026-11-13 by a research pass. Items marked *docs* come from official
documentation and have not yet been reproduced in the lab.

**Claude Code**

- The Bash sandbox is off by default, needs `bubblewrap` and `socat` on WSL2,
  and confines only Bash commands. Read, Edit, WebFetch, hooks and MCP servers
  run outside it. *docs* — <https://code.claude.com/docs/en/sandboxing>
- By default it limits writes to the working directory and blocks network
  outside an allowlist, but reads still reach credential files such as `~/.ssh`
  until extra settings are added. Network matching is by hostname. *docs* — same page
- On WSL2, Windows programs stay launchable from inside the sandbox unless an
  optional filter is installed. *docs* — same page
- Anthropic says the Bash sandbox is not sufficient for fully unattended runs;
  running without permission prompts needs a container, a VM or the sandbox
  runtime, as a non-root user. *docs* — <https://code.claude.com/docs/en/sandbox-environments>
- `srt` (Anthropic's sandbox runtime) wraps a whole process, including hooks and
  MCP servers, without Docker, and works with any agent. It is a beta research
  preview. *docs* — <https://github.com/anthropics/sandbox-runtime>
- Permission rules and hooks are policy, not a boundary. *docs* — <https://code.claude.com/docs/en/permissions>

**Containers**

- The reference dev container is an example, not a maintained base image. The
  docs warn that anything inside it can be exfiltrated in bypass mode and say
  not to mount `~/.ssh`. *docs* — <https://code.claude.com/docs/en/devcontainer>
- Access to the Docker daemon equals access to the host. An agent that can run
  `docker` as the owner bypasses every other layer. *docs* — <https://docs.docker.com/engine/security/>
- Docker Sandboxes (`sbx`) give each agent a microVM with its own kernel, deny
  network by default, and keep raw credentials outside the VM behind a proxy.
  It supports several agents. Requirements on Windows do not mention WSL2.
  *docs* — <https://docs.docker.com/ai/sandboxes/security/>

**Operating system**

- systemd's sandboxing properties work in user units but are not a guarantee,
  and its network filter takes addresses, not hostnames. *docs* — <https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html>
- bubblewrap and Landlock are building blocks, not finished sandboxes. *docs*
- No source recommends one Unix user per agent, although plain file
  permissions would keep the owner's keys unreadable. *inference*

## Options

| Option | Hides keys and tokens | Network control | Cost to start | Agent can install | Any agent |
|--------|----------------------|-----------------|---------------|-------------------|-----------|
| Claude Code Bash sandbox | if configured; Bash only | hostname allowlist | negligible | user level | no |
| `srt` | if configured | hostname allowlist | negligible | user level | yes |
| Dev container per project | yes, unless mounted | address allowlist | seconds | root, inside it | yes |
| Docker `sbx` microVM | yes, by proxy | deny by default | VM boot | root, inside it | yes |
| Separate Unix user + `systemd-run` | yes | addresses only | none | user level | yes |

Start-up cost and memory use are estimates; no source gives figures.

## Lab results so far

Run in the `lab` distro (Ubuntu 26.04.1, WSL kernel 6.18.58.1) on 2026-11-13.

| Check | Result |
|-------|--------|
| Kernel security modules | capability, landlock, yama, safesetid, selinux, bpf, ima. AppArmor is off. |
| Unprivileged user namespaces | work |
| `/dev/kvm` | present; the login user is not in the `kvm` group |
| `bubblewrap` | already installed (0.11.1) |
| `socat` | not installed; available from apt (1.8.1.1) |
| cgroups | version 2; `cpu`, `memory` and `pids` are delegated to the user's systemd manager |
| Memory cap without root | a process capped at 64 MB that asked for 300 MB was stopped; the uncapped control succeeded |
| CPU cap without root | a busy loop capped at 50% used 1.01 s of CPU in 2 s |

So the building blocks for the cheaper options exist on this kernel, and limits
per agent can be set by the user without root.

## Lab: the machine can host the sandbox runtime

Ubuntu 26.04.1, WSL kernel 6.18.58.1, 2026-11-16. A throwaway settings file
was used: one allowed host, one decoy file denied, writes limited to the
project and `/tmp`.

| Check | Result |
|-------|--------|
| Install | `npm install -g @anthropic-ai/sandbox-runtime` as root with apt's Node 22: version 0.0.83, files owned by root in `/usr/local` |
| Dependencies | bubblewrap and socat are not enough: `srt` refuses to start without **ripgrep** |
| Starts on this kernel | yes |
| Read the decoy file | refused ("Permission denied") |
| Read an ordinary file in the home directory | allowed — reads are open unless denied |
| Write outside the project | refused ("Read-only file system") |
| Write inside the project and in `/tmp` | allowed |
| Reach a host not on the list | refused by the proxy (403) |
| Reach the listed host | allowed |
| Tools installed by mise | work inside, same versions |
| Start a Windows program | fails (the socket it needs is blocked) |
| An environment variable set outside | visible inside |
| Start-up cost | 0.22–0.33 s per command |

Separately, with plain bubblewrap, the whole filesystem read-only except the
project and no network: node, gh, uv, just and glab all ran, also with mise in
paranoid mode. The tool layer needs no write access to the home directory and
no network to run.

What follows for the machine layer:

- **Three apt packages, not two:** bubblewrap, socat, ripgrep.
- **`srt` runs whichever `node` is first on `PATH`.** Its launcher starts with
  `#!/usr/bin/env node`, so with mise's shims first it runs under a Node the
  user can modify. A wrapper should call `/usr/bin/node /usr/local/bin/srt`.
  To pass on to Daedalus (component C8).
- **Environment variables pass straight through**, so a token exported by the
  shell is inside the sandbox. This confirms "no global exports" in track 4.
- **An unattended agent cannot install tools:** the tool directory is
  read-only inside and the network is closed. Tools a job needs are installed
  before the run, by the owner or in a supervised session. This matches the
  roles table (Daedalus 7.9): the agent proposes changes, it does not apply
  them to its own environment.

- **Windows files are readable inside the sandbox** unless denied
  (`ls /mnt/c/Windows` worked); writing them is refused and Windows programs
  do not start. To pass on to Daedalus: decide which parts of `/mnt/c` go on
  the deny list.

- **A browser works inside the sandbox** under three conditions (inner
  Chromium sandbox off, proxy credentials passed separately, `TMPDIR`
  created first). Details and data: `06-capabilities.md`,
  `lab/tests/browser.sh`. To pass on to Daedalus for any skill or tool that
  drives a browser in an unattended run.

These checks now run on every machine as part of `machine/verify.sh`.

## Still to run on this side

1. The fallback: Docker Engine installed but stopped; start-up time and memory
   of a dev container (needed only if Daedalus hits K2).
2. Devices: whether a process inside `srt` can open a USB serial device.
3. `/dev/kvm` group membership, when a microVM is first needed.

Moved to Daedalus, which owns them: the Claude Code sandbox settings, hooks
reading outside the project, and the decoy-secret exit test (E5).

## Not verified

- `sbx` with WSL-hosted workspaces and its memory use.
- Device and GPU access from inside each option.
- The exact names of the stricter sandbox settings, which are newer than the
  version history we have checked. Claude Code here is 2.1.322.
