# Lab: the stock Ubuntu 26.04 image

Measured on 2026-11-13 in the `lab` distro, straight after `lab/lab create`,
before changing anything. Reproduce with `lab/lab measure`.

## What the image is

| Item | Value | Compared with the daily distro (24.04) |
|------|-------|----------------------------------------|
| Release | Ubuntu 26.04.1 LTS | 24.04 |
| systemd | 259 | 255 |
| Core utilities | uutils coreutils 0.8.0 (Rust) | GNU coreutils |
| sudo | sudo-rs 0.2.13 | sudo |
| Python | 3.14.4 | 3.12 |
| Time sync | chrony | systemd-timesyncd |
| Packages | 544 installed, 20 marked manual | — |
| Snaps | none | none |
| zsh | not installed | installed |
| cloud-init | reports `disabled` | 4 units enabled |
| Disk used | 1.3 GB | 101 GB |

Still enabled on the stock image: snapd, landscape-client, wsl-pro, apport,
cloud-init units, rsyslog, and the `apt-daily`, `apt-daily-upgrade`,
`motd-news` and `ua-timer` timers. `getty@tty1.service` fails on every boot,
which leaves the system state `degraded`.

## Start time

| Measure | Result |
|---------|--------|
| systemd startup, first boot | 2.27 s, of which `snapd.seeded` is 1.75 s |
| Stopped distro to first command, VM already warm | 1.60 s, 1.80 s, 1.70 s |
| Command in a running distro | 0.10 s, 0.12 s, 0.11 s |

These are distro starts inside a VM that is already running. A cold VM start
(first terminal after Windows boots) is not measured yet.

## Login session

A fresh login as the user gets `/run/user/1000`, a running user manager and a
session bus. Linger is off by default. Locale is `C.UTF-8`; no `TZ` is set.

## Windows directories on PATH

By default WSL appends the whole Windows `PATH`.

| Measure | Result |
|---------|--------|
| PATH entries | 30, of which 21 are under `/mnt/c` |
| 200 failed command lookups, full PATH | 4.00 s |
| 200 failed command lookups, Linux-only PATH | 0.006 s |

Each lookup of a command that does not exist costs about 20 ms instead of
0.03 ms, because every Windows directory is searched across the file-system
boundary.

Windows programs also stand in for missing Linux ones. On this image, with no
Node installed, `npm` resolves to `/mnt/c/Program Files/nodejs/npm`, and
`docker` and `code` resolve to their Windows versions. An agent that runs `npm`
before Node is set up gets the Windows one without any error.

**Candidate decision (to confirm with the host-and-boot research):** set
`appendWindowsPath=false` under `[interop]` in `/etc/wsl.conf`, and add back
only the Windows programs that are wanted, by name.
