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

**State of the evidence:** 31 entries. 8 are backed by a script or a check,
5 are reading with sources, 18 are one-off (three of those are now partly
covered by a check or by `machine/describe`). No run so far has written a
data file: results are prose in `research/`. Closing that gap is the next
piece of work (see the end of this page).

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
| T3 | 13 Nov | What do Windows directories on `PATH` cost? | 200 failed lookups: 4.00 s with them, 0.006 s without | one-off → `00-lab-stock-image.md` |
| T4 | 13 Nov | Does the boot race reproduce, and what fixes it? | Defaults: session missing. Linger alone: still missing at login. `initTimeout=60000`: present | script: `lab/tests/boot-race.sh` |
| T5 | 13 Nov | Does the 24.04 `/tmp` rule delete at boot? | Rule `D` removed 100,100 entries; rule `d` removed none | one-off → `01-host-and-boot.md` |
| T6 | 13 Nov | Do mise shims give every process the tools? | Yes; per-directory versions correct; 15.9 ms per call against 2.3 ms direct | one-off → `02-tools.md` |
| T7 | 13 Nov | What runs in a repo nobody approved? | By default `mise exec`, `mise install` and `CI=1` run its script; paranoid mode refuses all | one-off → `02-tools.md` |
| T8 | 13 Nov | Can mise's bootstrap own the machine config? | Apply, repeat, drift detection and repair worked in a first trial | one-off → `02-tools.md` (superseded by T18) |
| T9 | 13 Nov | Does the kernel have the pieces for sandboxing and limits? | User namespaces, cgroup v2; a 64 MB cap stopped a 300 MB request; a 50 % CPU cap held | one-off → `03-isolation.md` |
| T10 | 13 Nov | Does one SSH agent serve every terminal? | Yes on 26.04: started on demand, one process, key kept across sessions | one-off → `04-keys-and-secrets.md` |
| T11 | 13 Nov | Is the GPU visible in a fresh distro? | RTX 2060, 6 GB, no setup | one-off → `06-capabilities.md`; now in `machine/describe` |
| T12 | 16 Nov | Do the tools run in a read-only, no-network box? | Yes, also in paranoid mode | one-off → `03-isolation.md`; covered by check "tools work inside it" |
| T13 | 16 Nov | Can `/tmp` live on disk on 26.04 without slowing boot? | 100,101 files, cold boot 1.9 s, boot-time step 14 ms | one-off → `01-host-and-boot.md`; check covers only "on disk" |
| T14 | 16 Nov | Does Anthropic's sandbox runtime work here? | Yes after adding ripgrep; decoy file, outside writes, unlisted host, Windows programs all refused; 0.22–0.33 s start-up | check: 9 sandbox checks in `verify.sh`; start-up time one-off |
| T15 | 16 Nov | Can `gh` serve several identities without SSH? | One config with two accounts: no. One config per identity chosen by directory: yes, and no token outside | one-off (fake tokens) → `04-keys-and-secrets.md` |
| T16 | 16 Nov | What does an idle Docker Engine cost, and can a sandboxed agent reach it? | 0 MB until first use; first run 2.9 s; then 217 MB; refused inside the sandbox | check: 3 Docker checks; timings and memory one-off → `01-host-and-boot.md` |
| T17 | 16 Nov | What does a sandboxed process see of Windows? | Files readable, not writable; programs do not start | check (programs); read/write one-off → `03-isolation.md` |
| T18 | 16 Nov | Does one command build the machine from an empty image? | Before: 15 checks fail. Install 103 s. After: all 27 pass. Second apply changes nothing. Lock file unchanged | script: `lab/rehearse.sh` + `machine/verify.sh` |
| T19 | 16 Nov | Does Claude Code install from its own apt repository without touching its config? | 2.1.311 in 8 s; `~/.claude` not created | check ("a clean shell finds all tools"); the `~/.claude` part one-off |
| T20 | 16 Nov | Does a browser work locally for agents? | Outside the sandbox: yes. Inside: only with its inner sandbox off, and it did not exit by itself | one-off → `06-capabilities.md`. **Inconclusive**, needs a proper test |
| T21 | 16 Nov | What does Ubuntu's `npm` package bring with it? | 373 `node-*` packages, 92 MB | one-off → `02-tools.md` |

## Read-only measurements on the daily distro and on Windows

| # | Date | What | Result | Evidence |
|---|------|------|--------|----------|
| M1 | 13 Nov | Contents of `/tmp` after 6 h 40 min | 292,890 entries, 1.5 GB | one-off → `01-host-and-boot.md` |
| M2 | 13 Nov | Docker Desktop's links inside the distro | 23 links, all dangling when Docker Desktop is stopped | one-off → `00-baseline.md` |
| M3 | 13 Nov | Disk use on Windows | Distro disk 119.8 GB, Docker Desktop data 116.6 GB, 67.6 GB free on C: | one-off → `00-baseline.md` |

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

- Eighteen results cannot be re-run from this repo. Each should become a
  saved test under `lab/tests/`.
- No test writes data. Each run should leave a file (time, machine
  description, each check's outcome, timings), so results can be compared
  across machines and dates instead of being re-typed into prose.
- The format of that data is Daedalus's decision (its section 8.6). This repo
  should emit plain JSON that Daedalus can take in.
