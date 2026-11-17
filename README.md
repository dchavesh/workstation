# workstation

A local environment for AI agents: fast, secure, scalable, maintainable, cheap
to run and as deterministic as possible. Software development first; multimedia,
hardware/IoT and mobile work later. The environment should let an agent set up
what a job needs instead of limiting it.

**Status: research.** Nothing here is installed on the daily machine yet. The
result is installed from zero when the PC is formatted (before ~2026-12-13).

## Method

Every choice goes through the same steps and is recorded in `research/`:

1. The question.
2. What official documentation and primary sources recommend.
3. The candidates.
4. A test in the throwaway `lab` WSL distro.
5. The measured result.
6. The decision, and what would change it.

## Tracks

| # | Track | Question |
|---|-------|----------|
| 1 | Host and boot | What must be decided at format time, and which services should exist at all? |
| 2 | Tools and project environments | One ordered rule for installing things, with locked versions. |
| 3 | Isolation | What can an agent read, change and reach? |
| 4 | Keys and secrets | Keys that cannot be copied; tokens scoped to a project or command. |
| 5 | Many agents at once | Working copies, resource limits, sessions that outlive the terminal. |
| 6 | Capabilities | Devices, GPU, GUI and toolchains for non-software work, switched on per job. |
| 7 | Lifecycle | Install from zero, update, health check, what survives a format. |

## Layout

- `machine/` — the machine itself: one mise config, the dotfiles, one root
  script, the health check (`verify.sh`) and the machine description
  (`describe`). First run: `machine/install.sh wsl`. Afterwards:
  `mise bootstrap`.
- `windows/` — the Windows half: the app list for winget (`apps.json`), the
  install script (`install.ps1`, with `-DryRun`), and the steps for the first
  real test on the laptop (`LAPTOP-TEST.md`).
- `data/runs/` — what each test run produced, as JSON: one directory per
  run, named by its UTC start time. Written by the scripts, never by hand.
- `research/` — baseline measurements and one page per decision.
  `EVIDENCE.md` lists every test and how well its result is backed.
- `lab/` — scripts that create, provision and destroy the `lab` distro.
  `lab/rehearse.sh` rebuilds it from an empty image and runs the health check.

## Boundary with Daedalus

The owner's agent project, Daedalus, sets this boundary in its consolidation
document (entry A-59; sections 7.9, 8.1 and 10), read on 2026-11-16.

| | This repo: the machine layer | Daedalus M0: the agent layer |
|---|---|---|
| Owns | Shell, tools, packages, WSL, Windows, Docker | `~/.claude`, plugins, hooks, skills, CLAUDE.md, Claude Code settings, the sandbox profile, telemetry |
| Decides | How the machine is installed, updated and checked | Isolation, permissions, roles, what an agent may do |

What this repo owes Daedalus:

1. bubblewrap, socat, ripgrep and Anthropic's sandbox runtime (`srt`),
   installed where the login user cannot write.
2. The toolchain, working unchanged inside that sandbox.
3. Docker off by default, with no Docker socket within an agent's reach.
4. No secrets in the shell environment or in any repo.
5. A machine-readable description of the machine's state (versions, free
   memory, sandbox packages) that their measurement protocol can record per run.
6. A Linux half that does not depend on WSL, so it can later seed a VM or
   container image.

Clarified by the owner on 2026-11-16:

- **This repo installs Claude Code; it never configures it.** Installing goes
  through Claude Code's own apt repository (and winget on Windows).
- **Windows is the main operating system and is in scope.** The install has
  to set up Windows as well (apps, WSL, terminal), and agents running in WSL
  must be able to work with Windows without friction.
- **Browsers and containers are supplied locally.** No cloud runner is
  needed to give an agent either.

What this repo must not do:

- Write anything under `~/.claude`, or any Claude Code configuration, in any
  distro.
- Re-decide isolation. `research/03-isolation.md` records how the machine
  hosts the decision Daedalus already made.

## Goal, in the owner's words (2026-11-16)

Not to repair the current distro. To set up a terminal and workspace that is
fast, secure, scalable, maintainable, optimised and friendly for AI and
agents, so that the machine never interrupts an agent and the terminal
becomes a booster for agent work.

Two levels follow from that, and both are measured (Daedalus A-36: the machine
matters where a measurement shows it does):

1. **Never in the way.** Boot, tools, prompts, memory: nothing on the machine
   stops or stalls an agent.
2. **Booster.** Things that make agent work faster, cheaper or possible at
   all. Each one enters with a measurement and leaves if it shows nothing.

## Division of roles between Windows and WSL

The owner's original division, kept (2026-11-16):

- **Windows is the desktop:** what the owner looks at and clicks. Graphical
  apps, the browser, the terminal window.
- **WSL is the workspace:** where work runs. Runtimes, engines (including
  Docker Engine, so Docker Desktop is not needed), projects, agents.
- **Agents live in WSL** and reach Windows through a few named doors.

Windows apps start from a short list of what the owner actually uses, not
from what the old machine happened to have installed.

## Working rules from the owner (2026-11-16)

- **Sandbox by default, without shrinking the agent.** The owner no longer
  approves actions by hand, so the fence is what keeps that safe. The fence
  stays; capabilities (network, browser, containers, Windows) are passed
  through it by controlled doors, each one tested. This repo supplies the
  doors; Daedalus decides the policy.
- **Results are data, not an agent's word.** Every test is a saved script and
  every run leaves a file. `research/EVIDENCE.md` lists what exists and how
  well each result is backed.

## Rollout

The first real install is the owner's **laptop**. The PC stays untouched as
the fallback until the laptop proves the setup. There is no fixed format date:
nothing is formatted until the setup is tested. One repo therefore has to
serve two machines, so machine-specific values (memory, processors, GPU) are
parameters, not constants.
