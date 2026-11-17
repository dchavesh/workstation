# Track 1: Host and boot

**Decision: the boot race is understood, reproduced and fixed in the lab.
Open: Docker, where the virtual disk lives, and the Windows-side settings.**

## Question

Why does a cold start sometimes take 20 s or more and leave the shell broken,
what should be decided at format time, and which services should exist at all?

## Root cause of the slow, broken boots

An earlier note in this repo said the stall happened on the Windows side. That
was wrong. The journal shows it is one systemd unit inside the distro.

| Boot | `systemd-tmpfiles-setup` ran for | systemd startup | User session |
|------|----------------------------------|-----------------|--------------|
| 2026-11-11 09:49 | 16.3 s | 20.3 s | never created |
| 2026-11-11 09:56 | 0.02 s | 1.6 s | created |
| 2026-11-13 06:11 | started at 3.9 s, never finished before the distro was stopped | not finished | never created |
| 2026-11-13 06:12 | 0.54 s | 2.2 s | created |

What that unit does on Ubuntu 24.04:

- It runs `systemd-tmpfiles --create --remove --boot`.
- The vendor rule for `/tmp` is `D /tmp 1777 root root 30d`. The capital `D`
  means "empty this directory at boot".
- `/tmp` is on the ext4 disk, so its contents survive until the next boot.
- After 6 h 40 min of uptime `/tmp` held 292,890 entries (1.5 GB). 265,833 of
  them belonged to one agent session's scratch directory.

So the chain is: agents write many files to `/tmp`; the next boot deletes them
before anything else may start; that takes longer than the 10 s WSL waits for
systemd; WSL logs the user in before `systemd-logind` exists; the user session
is never created; anything using `XDG_RUNTIME_DIR` fails. The two fast boots
both came minutes after a wipe, when `/tmp` was nearly empty.

Not reproduced: the exact duration. Deleting 100,100 empty files with a warm
cache took 0.56 s in the lab, so the 16 s and longer on real boots must come
from a cold cache and real file contents. The unit and the rule are certain;
the per-file cost is not measured.

## Lab: the race reproduced, and what fixes it

`lab/tests/boot-race.sh` adds a unit that keeps early boot busy for 30 s, boots
the lab cold under four settings, and reports whether the user session exists.

| Settings | Wait for first command | Session at login | Session later |
|----------|------------------------|------------------|---------------|
| Defaults | 21 s | **missing** | **missing** |
| Linger on | 21 s | **missing** | present |
| `initTimeout=60000` | 31 s | present | present |
| Linger and `initTimeout` | 31 s | present | present |

- **Defaults** reproduce the failure exactly.
- **Linger** alone is not a fix: the first shell still starts without a
  session. It only repairs later shells.
- **`initTimeout`** (under `[boot]` in `/etc/wsl.conf`) makes WSL wait for
  systemd. A slow boot then costs time and nothing else.

Lab check of the rule itself: with `D`, 100,100 entries were removed by the
boot-time step; with `d`, none were, and the step took 0.01 s.

## What the sources say

Read on 2026-11-13 by a research pass. *docs* = official documentation.

- `[boot] initTimeout` (default 10000 ms) and `[general] instanceIdleTimeout`
  are documented WSL settings. *docs* — <https://learn.microsoft.com/en-us/windows/wsl/wsl-config>
- WSL maintainers say these errors mean systemd was too slow: disable the slow
  unit or raise `initTimeout`. — <https://github.com/microsoft/WSL/issues/13186>
- Sparse virtual disks remain experimental. — <https://github.com/microsoft/WSL/issues/13241>
- A Dev Drive must be created at format time, and Microsoft expects no gain
  for files used from inside WSL. *docs* — <https://learn.microsoft.com/en-us/windows/dev-drive/>
- Ubuntu on WSL reads cloud-init user data once at first start. *docs* —
  <https://ubuntu.com/wsl/docs/latest/reference/instance_configuration/>
- Ubuntu 26.04: Rust coreutils and sudo, systemd 259, `/tmp` on tmpfs,
  Python 3.14. *docs* — <https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/>
- Docker Desktop runs its own distro in the same VM; on WSL its Resource Saver
  frees no memory while integration is on. Docker Engine supports 26.04. *docs*
  — <https://docs.docker.com/desktop/use-desktop/resource-saver/>

## Decisions

1. **Ubuntu 26.04.** `/tmp` is on tmpfs there (confirmed in the lab: tmpfs,
   4.4 GB limit, rule `q`), so the boot-time wipe does not exist.
2. **`initTimeout=60000`** in `/etc/wsl.conf`, so a slow boot can never again
   produce a login without a session.
3. **`/tmp` on disk, cleaned by age, never at boot.** On 26.04 `/tmp` is
   memory by default: today's 1.5 GB of scratch files would come out of the
   9 GB VM, and memory is this machine's real limit. Revised on 2026-11-16:
   the first version of this decision moved the agent's scratch directory
   with a Claude Code setting. That setting belongs to Daedalus, and its
   sandbox profile names `/tmp` as the writable scratch path, so the machine
   makes `/tmp` itself safe instead. This also works for any agent.
   Lab test: `systemctl mask tmp.mount`, then 100,101 files (393 MB) in
   `/tmp`, then a cold boot — first command after 1.9 s, the boot-time step
   took 14 ms, the user session was present, every file survived. The vendor
   rule (`q /tmp 1777 root root 10d`) removes old files in the background.
4. **`appendWindowsPath=false`**, adding back only the Windows programs wanted
   (measured in `00-lab-stock-image.md`: 20 ms per failed lookup, and Windows
   `npm` standing in for a missing Linux one).
5. **Linger on**, for a different reason than the race: it starts the user's
   services at boot and keeps them when the last terminal closes.

## Proposed, not yet tested

- `.wslconfig`: keep `memory=9GB` and `processors=8`; smaller swap in a fixed
  location; drop `sparseVhd` (experimental) and `vmIdleTimeout`;
  `instanceIdleTimeout=-1` so background agents are not stopped.
- Remove or disable on the stock image: `wsl-pro-service`, snapd,
  landscape-client, cloud-init after first boot, `motd-news`, rsyslog; stop
  apt's catch-up runs right after boot.
- Install GNU coreutils on 26.04 so agent-written commands behave as expected.
- Use cloud-init user data for the very first boot (creating the user).

## Open — the owner's call

- **Docker — recommended: Docker Engine inside the distro.** Awaiting the
  owner's confirmation. Checked on 2026-11-13:
  - With Docker Desktop, `docker` inside the distro is one of 23 symlinks
    that work only while the Windows application is running (see
    `00-baseline.md`). An agent cannot rely on it.
  - Docker Desktop's data disk is 116.6 GB on a drive with 67.6 GB free.
  - Docker's apt repository serves 26.04 (`resolute`), so Engine fits the
    first install channel and updates with apt.
  - Engine lets the distro decide who may use the Docker socket, which track
    3 needs.
  - Lost: `docker` from Windows shells and the Desktop window.
  - The Daedalus plan (read 2026-11-16) settles the rest: it wants Docker off
    and no socket exposed to agents, uses Docker only as a fallback, and
    defers microVMs. Docker Desktop is not reinstalled after the format.
  - Lab test, 2026-11-16: Docker Engine 29.10.0 installed from Docker's apt
    repository in 12 s. With `docker.socket` enabled and `docker.service` and
    `containerd.service` disabled, nothing runs after a cold start (0 MB).
    The first `docker run` started both and finished in 2.9 s; they then held
    148 MB and 69 MB. From inside `srt`, `docker ps` was refused ("permission
    denied" on the socket) although the login user is in the `docker` group.
  - So the recommendation is: **Engine in the base, asleep until first use.**
    It costs nothing idle and the sandbox cannot reach it, which meets the
    plan's intent. Whether agents ever get Docker stays Daedalus's call.
- **Where the virtual disk lives — recommended: stay on the SSD (C:).** The
  second drive (D:, 1863 GB, empty) is a hard disk; a Linux disk on it would
  make every file operation slow. Use D: as the backup target that survives
  the format instead. Track 7 defines what is backed up and when.

## The Windows side (in scope since 2026-11-16)

The owner's position: Windows is the main operating system; the install must
set it up too, and agents in WSL must work with Windows without friction.

Facts collected, read-only:

- **PC:** MS-7D43, 12 logical processors, 15.8 GB, Windows 11 Pro build
  26300, NVMe SSD 477 GB plus a 1863 GB hard disk, RTX 2060. winget 1.29
  knows 32 apps, among them Claude (desktop), Cursor, Git, Android Studio,
  Temurin 17, Node.js LTS, Windows Terminal, WSL, and three Store apps.
- **Laptop (first real install):** Inspiron 7791 2-in-1, 8 logical
  processors, 15.8 GB, Windows 11 **Home** build 26300, one 477 GB SSD.
  Graphics: Intel UHD and an NVIDIA GeForce MX250. Home runs WSL 2; it has
  no Windows Sandbox or Hyper-V Manager. The owner allows any test on the
  laptop, including a Claude Code session there.
- mise's bootstrap has no winget support (its Windows package manager is
  scoop), so mise does not own the Windows side.
- Claude Code's documentation: on native Windows it installs with
  `winget install Anthropic.ClaudeCode`, does not update itself that way, and
  **sandboxing is not supported there** (it is on WSL 2).

Tested from WSL, outside the sandbox: PowerShell, cmd, explorer, clip and wsl
start by name; Windows files can be read and written.

Which Windows apps the owner actually runs, read on 2026-11-16 with the
owner's permission from Windows' own per-user usage record (UserAssist; it
goes back to April 2026 and only sees programs started from the Start menu,
taskbar or Explorer, not from a terminal):

| Last used | Apps |
|-----------|------|
| This week | Chrome (several profiles), Windows Terminal, WhatsApp, Notepad, Snipping Tool, Calculator, Paint |
| Last 3 weeks | Discord, VS Code, NVIDIA App, Photos |
| 2–3 months ago | Docker Desktop (10 Sep, once), PowerShell, Edge, Spotify (3 Aug) |
| April–July | PicPick, Corsair iCUE |
| No launch on record | Cursor, Android Studio, Claude desktop, Teams, Outlook, Microsoft 365 Copilot |

Proposed app list for a new machine, following "Windows is the desktop":

- **Install (agreed by the owner):** Chrome, VS Code, WhatsApp, Discord. The
  NVIDIA app comes with the graphics driver; Spotify if wanted.
- **Already part of Windows:** Terminal, Notepad, Snipping Tool, Calculator,
  Paint, Photos, Edge, PowerShell, winget, WSL.
- **Not installed:** Docker Desktop (the engine lives in WSL), Cursor,
  Android Studio, Claude desktop, Teams, Outlook, Microsoft 365 Copilot,
  PicPick. iCUE only on the PC, if its keyboard or lighting needs it.
- **Command-line tools now on Windows** (Git, Node.js, Java 17) belong in
  WSL under this division and are not installed on Windows.
- **Corrected on 2026-11-16:** a first version of `apps.json` added Git, the
  GitHub CLI and Claude Code for Windows. None came from the owner's usage.
  They were there to fetch this private repo on a fresh Windows and to run
  an agent natively on Windows. Neither is needed: the distro's own git
  fetches the repo, and an agent in WSL already drives Windows through
  PowerShell. They are removed. Claude Code for Windows is added only if a
  task turns up that an agent in WSL cannot do.
- **Android Studio:** not launched since at least April. Agents need the
  command-line Android SDK, not the IDE. The emulator runs inside WSL: tested
  on 2026-11-16 (`lab/tests/android-emulator.sh`, details in
  `06-capabilities.md`). So Android work can live in WSL and Android Studio
  is not needed on Windows for agents. A phone, the microphone and the webcam
  need hardware tests that have not been run.

The laptop is set up like the PC and is in use. Until it is formatted it is
treated like the PC: tests there run in a `lab` distro and change nothing
else (`windows/LAPTOP-TEST.md`).

Candidate, not yet tested: winget for Windows apps (it is part of Windows 11
and each vendor publishes there), and one PowerShell script for WSL itself,
`.wslconfig` and the terminal. `winget configure`, Microsoft's declarative
format with its own drift test, may replace the script. The first real test
is a run on the laptop before it is formatted, where nothing can be lost.

## Not verified

- The per-file cost of the wipe on a cold boot.
- `instanceIdleTimeout=-1` and a fixed swap file on WSL 3.0.5.
- Docker Desktop's effect on start-up time.
- sudo-rs differences that matter to scripts.
