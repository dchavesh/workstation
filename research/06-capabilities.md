# Track 6: Capabilities — work beyond software

**Decision: pending.** The packaging idea below is a proposal; most device
tests need physical hardware.

## Question

Agents should be able to do multimedia, hardware/IoT and mobile work, and to
switch on what a job needs. What can a process inside WSL2 actually reach, and
how should each discipline's requirements be packaged?

## A correction to the starting assumption

The machine does not have integrated graphics only. It has an **NVIDIA RTX 2060
(6 GB)** beside the Intel UHD 730. `nvidia-smi` sees it from a fresh distro
with no setup, and the research pass measured a 1080p NVENC test encode at
269 fps inside WSL.

## What works inside WSL2

Read on 2026-11-13 by a research pass, from Microsoft, vendor and project
documentation.

| Discipline | Works | How | Hard limits |
|------------|-------|-----|-------------|
| USB and serial | partly | usbipd-win on Windows, udev rules and groups in Linux | binding needs Windows admin once; re-attach after a reset or replug |
| Embedded (ESP-IDF, Zephyr) | yes | Linux toolchains over usbipd | boards that re-enumerate when entering bootloader mode |
| Mobile | partly | Android builds; `adb` to a phone over USB or network | emulator inside WSL is unsupported by Google; iOS builds need a Mac |
| Multimedia | yes | ffmpeg with NVENC/CUDA or VA-API; audio through WSLg | audio only through WSLg's PulseAudio |
| GUI apps | partly | WSLg | not a desktop; windows appear on the Windows side |
| Windows programs | yes | `.exe` interop | slow file access across `/mnt/c`; path translation |
| GPU compute | yes | CUDA with only the Windows driver | 6 GB of video memory, 9 GB RAM cap: inference yes, training no |

Sources: <https://learn.microsoft.com/en-us/windows/wsl/connect-usb>,
<https://developer.android.com/studio/run/emulator-acceleration>,
<https://docs.nvidia.com/cuda/wsl-user-guide/index.html>,
<https://github.com/microsoft/wslg>,
<https://learn.microsoft.com/en-us/windows/wsl/filesystems>

**Plan around the Windows side for:** the Android emulator, GUI creative
applications, capture devices, and possibly serving local models (which would
escape the 9 GB cap). iOS needs a remote Mac.

## Lab results

| Test | Result |
|------|--------|
| `nvidia-smi` in a fresh 26.04 distro | RTX 2060, 6144 MiB, no setup needed |
| `/dev/kvm` | present |
| Device group IDs versus the distro's groups | match in the lab (kvm 991, render 990) |
| Login user in `kvm`, `render`, `video`, `dialout` | none of them by default |

Android emulator, tested in the lab on 2026-11-16
(`lab/tests/android-emulator.sh`, record with a screenshot in `data/runs/`).
Google does not support running it inside WSL, but it works here:

| Measure | Result |
|---------|--------|
| Acceleration | KVM usable once the user is in the `kvm` group |
| Boot, no window | Android 15 in 36 s |
| Driven from the command line (`adb`) | key press, screen tap and screenshot all worked |
| Memory | 3.3 GB while running, out of 9 GB for WSL |
| Disk | 4.8 GB for the command-line SDK, emulator and one system image |

So an agent in WSL can build an Android app, start an emulator, operate it
and look at the screen, with no Android Studio and nothing on Windows. The
cost is memory: one emulator is a third of the machine's WSL memory. It
belongs in an opt-in profile, not in the base install. Not tested: a real
phone (over Wi-Fi with `adb`, or over USB), the emulator's own window, and
whether a sandboxed agent can reach `adb`.

Browser, tested in the lab on 2026-11-17 (`lab/tests/browser.sh`, records
with a screenshot in `data/runs/`). A Playwright script opens a page, reads
its title, takes a screenshot and closes the browser. Headless Chromium
installs in 17 s and takes 287 MB.

| Situation | Page loaded | Time | Exited by itself |
|-----------|-------------|------|------------------|
| Outside the sandbox | yes | 0.3–0.5 s | yes |
| Inside, site on the list | **yes** | 0.3 s | yes, no process left |
| Inside, site not on the list | no, refused at once | 0.1 s | yes |
| Inside, Chromium's own inner sandbox left on | no, the browser does not start | — | yes |
| Inside, proxy address passed as the sandbox announces it | no, times out | 20 s | yes |

So an agent can drive a browser inside the sandbox, and the website list
still applies to it. Three conditions, found by the test:

1. **Chromium's inner sandbox must be off** inside the agent sandbox (it is
   Playwright's default on Linux). The outer sandbox is then the only fence.
2. **The proxy's user and password must be passed separately.** The sandbox
   announces its proxy as `http://user:password@localhost:3128`, and Chromium
   ignores credentials written inside the address.
3. **The sandbox's temporary directory must exist.** `TMPDIR` points to
   `/tmp/claude`, which is not there on a first run; Playwright fails at
   launch until it is created.

This replaces the first, inconclusive attempt, in which the browser was
started by hand and did not exit. Containers are local too: Docker Engine is
in the base and wakes on first use (`01-host-and-boot.md`).

The research pass found the IDs did *not* match in the daily distro while the
lab was also running (`/dev/kvm` owned by group 991, where that distro's `kvm`
is 993). Device nodes appear to be shared between running distros. With one
distro after the format this should not occur; to confirm.

## Proposal

1. **Base, always on:** systemd, mise, the agent, and the machine-level items
   nothing else can own — kernel modules to load, group membership, baseline
   udev rules.
2. **One profile per discipline**, each a directory holding: tool versions and
   apt packages, udev rules and groups, the Windows-side requirements, and a
   `verify` script. One command applies a profile; applying twice changes
   nothing.
3. **A generated description of the machine** — built from the verify scripts,
   never written by hand — that marks each capability as enabled, available,
   needs hardware, or needs a Windows admin step. An agent reads this instead
   of probing.

Windows-admin steps (binding a USB device, drivers) stay a one-time human gate.
Agents work headless (`blender -b`, headless browsers).

## To run

Without hardware: load the USB kernel modules; check VA-API per adapter; a
headless Blender render with CUDA; audio in and out; a local model with
Ollama, WSL versus Windows.

With hardware: attach and flash an ESP32 and a Pico through usbipd; whether an
unprivileged agent can attach a device; `adb` to a phone over network and USB.

## Not verified

- VA-API on this machine (the render node could not be opened), and Vulkan.
- The Android emulator on WSL's KVM.
- Webcam and USB audio quality over usbipd.
