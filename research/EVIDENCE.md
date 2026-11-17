# Evidence register

Every investigation and test behind this repo, with where its evidence lives.
Written on 2026-11-16 at the owner's request: results must not live only in a
chat, or as an agent's word.

**How to read the last column**

- **script** — a saved script in this repo produces the result. Anyone can
  run it again and get data.
- **check** — the result is re-tested on every machine by `machine/verify.sh`.
- **one-off** — commands typed once in the lab. The number is written in the
  research page named, but the commands were not saved. Today the only raw
  record is the session transcript. These are the weak entries.

**State of the evidence:** 37 entries. 21 are backed by a script or a check,
5 are reading with sources, 11 are one-off.

**Data files:** since 2026-11-16 every rehearsal writes a record under
`data/runs/<time>-rehearsal/` (the steps and their durations, every check
before and after the install, measured values, the machine description, the
log), and `machine/verify.sh --json FILE` does the same for a single health
check on any machine. Everything else is still prose in `research/`. Closing
that gap is the next piece of work (see the end of this page).

## Investigations (reading, no lab)

| # | Date | What | Outcome | Evidence |
|---|------|------|---------|----------|
| I1 | 11–13 Nov | The daily distro's journal for four boots | Root cause of the original error: Ubuntu 24.04 empties `/tmp` at boot; 16.3 s on the failed boot, 0.02 s on a healthy one | `01-host-and-boot.md`; journal on the daily distro |
| I2 | 11–13 Nov | Audit of the daily distro | About ten install methods; a clean shell misses node, npm, pnpm, claude, uv, go, cargo, just, pre-commit; 292,890 entries in `/tmp` | `00-baseline.md`; one-off commands |
| I3 | 13 Nov | Five research passes over official documentation (boot, tools, isolation, keys, capabilities) | Source lists and candidate designs | `01`–`04`, `06` pages, each with links |
| I4 | 16 Nov | The owner's Daedalus plan | Boundary between the two efforts; isolation already decided there | `README.md`, `03-isolation.md` |
| I5 | 16 Nov | mise's published config schema and built-in help | mise can declare apt sources, system files and services; no winget support | `02-tools.md` |
| I6 | 16 Nov | Claude Code's setup page | Signed apt repository and key fingerprint; winget on Windows; no sandbox on native Windows | `02-tools.md`, `01-host-and-boot.md` |
| I7 | 13–16 Nov | Windows facts, read-only: disks, winget's app list, both machines' hardware | Second disk is a hard disk; 32 apps on the PC; laptop is Windows 11 Home with an MX250 | `00-baseline.md`, `01-host-and-boot.md` |

## Lab tests (Ubuntu 26.04 in the `lab` distro)

| # | Date | Question | Result | Evidence |
|---|------|----------|--------|----------|
| T1 | 13 Nov | How long does a throwaway distro take to rebuild? | 23–36 s | script: `lab/lab` |
| T2 | 13 Nov | What does a stock 26.04 image contain? | systemd 259, Rust coreutils and sudo, Python 3.14, `/tmp` in memory | script: `lab/measure.sh` → `00-lab-stock-image.md` |
| T3 | 13 Nov | What do Windows directories on `PATH` cost? | 200 failed lookups: 3.7 s with them, 0.045 s without (first measured as 4.00 s and 0.006 s) | script + **data**: `lab/tests/windows-path-cost.sh` |
| T4 | 13 Nov | Does the boot race reproduce, and what fixes it? | Defaults: session missing. Linger alone: still missing at login. `initTimeout=60000`: present | script: `lab/tests/boot-race.sh` |
| T5 | 13 Nov | Does the 24.04 `/tmp` rule delete at boot? | Rule `D` removed 100,100 entries; rule `d` removed none | one-off → `01-host-and-boot.md` |
| T6 | 13 Nov | Do mise shims give every process the tools? | Yes. Per call: 0.9 ms direct, 13.1 ms through a shim, 13.9 ms through `mise exec`. **The first note said 89.6 ms for `mise exec`; that did not reproduce** | script + **data**: `lab/tests/shim-cost.sh` |
| T7 | 13 Nov | What runs in a repo nobody approved? | By default `mise exec`, `mise install` and `CI=1` run its script; paranoid mode refuses all | script + **data**: `lab/tests/mise-trust.sh` |
| T8 | 13 Nov | Can mise's bootstrap own the machine config? | Apply, repeat, drift detection and repair worked in a first trial | one-off → `02-tools.md` (superseded by T18) |
| T9 | 13 Nov | Does the kernel have the pieces for sandboxing and limits? | User namespaces, cgroup v2; a 64 MB cap stopped a 300 MB request; a 50 % CPU cap held | script + **data**: `lab/tests/resource-limits.sh` |
| T10 | 13 Nov | Does one SSH agent serve every terminal? | Yes on 26.04: started on demand, one process, key kept across sessions | one-off → `04-keys-and-secrets.md` |
| T11 | 13 Nov | Is the GPU visible in a fresh distro? | RTX 2060, 6 GB, no setup | one-off → `06-capabilities.md`; now in `machine/describe` |
| T12 | 16 Nov | Do the tools run in a read-only, no-network box? | Yes, also in paranoid mode | one-off → `03-isolation.md`; covered by check "tools work inside it" |
| T13 | 16 Nov | Can `/tmp` live on disk on 26.04 without slowing boot? | 100,101 files, cold boot 1.9 s, boot-time step 14 ms | script + **data**: `lab/tests/tmp-on-disk-boot.sh` |
| T14 | 16 Nov | Does Anthropic's sandbox runtime work here? | Yes after adding ripgrep; decoy file, outside writes, unlisted host, Windows programs all refused; 0.22–0.33 s start-up | check: 9 sandbox checks in `verify.sh`; start-up time one-off |
| T15 | 16 Nov | Can `gh` serve several identities without SSH? | One config with two accounts: no. One config per identity chosen by directory: yes, and no token outside | script + **data**: `lab/tests/gh-identities.sh` |
| T16 | 16 Nov | What does an idle Docker Engine cost, and can a sandboxed agent reach it? | 0 MB until first use; first run 2.9 s; then 217 MB; refused inside the sandbox | script + **data**: `lab/tests/docker-idle-cost.sh` |
| T17 | 16 Nov | What does a sandboxed process see of Windows? | Files readable, not writable; programs do not start | script + **data**: `lab/tests/sandbox-windows.sh` |
| T18 | 16 Nov | Does one command build the machine from an empty image? | Before: 14–15 checks fail. Install 103–186 s. After: every check passes. Second apply changes nothing. Lock file unchanged | script + **data**: `lab/rehearse.sh`, records in `data/runs/` |
| T19 | 16 Nov | Does Claude Code install from its own apt repository without touching its config? | 2.1.311 in 8 s; `~/.claude` not created | check ("a clean shell finds all tools"); the `~/.claude` part one-off |
| T20 | 16–17 Nov | Does a browser work locally for agents, also inside the sandbox? | Yes. Outside: loads in 0.3–0.5 s. Inside: a listed site loads in 0.3 s, an unlisted one is refused, and the browser exits by itself, under three conditions (inner sandbox off, proxy credentials passed separately, `TMPDIR` created). The first attempt by hand was inconclusive | script + **data**: `lab/tests/browser.sh` (record includes `inside-sandbox.png`) |
| T21 | 16 Nov | What does Ubuntu's `npm` package bring with it? | 373 `node-*` packages, 92 MB | script + **data**: `lab/tests/npm-package-weight.sh` |
| T22 | 16 Nov | Does the Windows install script read a machine's state correctly without changing it? | Dry run on the PC: found winget, WSL, the lab distro and its user; would write `.wslconfig` with 9 GB; reported Chrome as missing although it is installed (winget cannot see that install). **The apply path has never run** | script: `windows/install.ps1 -DryRun`; apply is for the laptop (`windows/LAPTOP-TEST.md`) |
| T23 | 16 Nov | Can an Android emulator run inside WSL with no window, driven from the command line? | Yes: Android 15 booted in 36 s with KVM, used 3.3 GB of memory, answered a key press and a tap, and gave a screenshot. The SDK takes 4.8 GB | script + **data**: `lab/tests/android-emulator.sh` (record includes `screen.png`) |
| T24 | 16 Nov | With one capped unit per agent, is a runaway agent stopped while the others finish? | Yes: three workloads finished in 1.77–1.83 s beside a runaway one (1.62 s alone); the runaway asked for 3 GB under a 1 GB cap and did not get it | script + **data**: `lab/tests/parallel-agents.sh` |
| T25 | 17 Nov | Can several agents share one repository through git worktrees and shared package caches? | Yes: three installs and three commits at once all succeeded; a worktree costs 7 ms and 1 MB; npm dependencies are copied (31 MB each), Python ones shared. Tools are refused in a new worktree until its config is approved | script + **data**: `lab/tests/worktrees.sh` |
| T26 | 17 Nov | Does an agent's work outlive the terminal, and can it be seen and reached again? | With linger on: yes, through 45 s with no terminal, and WSL keeps the distro up for it. With linger off it dies after about 15 s. With nothing running WSL stops the distro. Units are listed with memory and processor use; a tmux session in a capped unit is readable from another terminal | script + **data**: `lab/tests/agent-sessions.sh` |

## Read-only measurements on the daily distro and on Windows

| # | Date | What | Result | Evidence |
|---|------|------|--------|----------|
| M1 | 13 Nov | Contents of `/tmp` after 6 h 40 min | 292,890 entries, 1.5 GB | one-off → `01-host-and-boot.md` |
| M2 | 13 Nov | Docker Desktop's links inside the distro | 23 links, all dangling when Docker Desktop is stopped | one-off → `00-baseline.md` |
| M3 | 13 Nov | Disk use on Windows | Distro disk 119.8 GB, Docker Desktop data 116.6 GB, 67.6 GB free on C: | one-off → `00-baseline.md` |
| M4 | 16 Nov | Which Windows apps the owner actually starts (Windows' own usage record, with permission) | Seven apps used this week, four more in three weeks; Docker Desktop once in September; six installed apps with no launch on record | one-off → `01-host-and-boot.md` (summary only; the raw list is personal and not stored) |

## What I got wrong, and how it was caught

| Claim | Caught by | Correction |
|-------|-----------|------------|
| The boot stall is on the Windows side | The journal (I1) | It is one systemd unit inside the distro |
| Linger fixes the broken first shell | T4 | It does not; `initTimeout` does |
| mise cannot enable existing system units | I5 | It can, through `[bootstrap.services]` |
| SSH keys with an agent are the owner's design | I4, then the owner | Reopened; `gh`/`glab` only is the recommendation (T15) |
| Unattended browser or container work needs a bigger room such as a cloud runner | The owner | Both are local (T16, T20) |
| The rehearsal's "must fail first" step worked | Running it | It passed on an empty machine because of a bug in `lab/lab`; fixed, then T18 |

## The gap, and what closes it

- Eleven entries are still one-off. Six are observations of the old machine
  and of Windows (I2, I7, M1-M4): they describe a state at one moment and are
  not repeated. T5, T8 and T10 concern things the design no longer uses
  (Ubuntu 24.04's `/tmp` rule, the first trial, the SSH agent). T11 and T12
  are now covered by `machine/describe` and by a health check.
- No lab test is open as inconclusive. Each record now carries the commit of
  the scripts that produced it.
- T19 has no check of its own for "installing Claude Code creates no
  `~/.claude`"; it should become a step of the rehearsal.
- `lab/tests/run-all.sh` runs the nine converted tests in one go; each writes
  its own record. The format of that data is Daedalus's decision (its section
  8.6). This repo emits plain JSON that Daedalus can take in.
