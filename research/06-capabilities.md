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

Browser, tested in the lab on 2026-11-16 with Playwright's headless Chromium
(installed in 21 s, 287 MB):

| Where | Result |
|-------|--------|
| Outside the sandbox | page loaded |
| Inside `srt`, browser's own inner sandbox on | no page |
| Inside `srt`, inner sandbox off (`--no-sandbox`), site on the allowlist | page loaded, but the browser did not exit by itself and had to be stopped |
| Inside `srt`, site not on the allowlist | no page |

So a browser for agents is a local matter: it works outright in a supervised
session, and can work inside the sandbox with the allowlist still applied.
The clean-exit problem needs a proper test driven by Playwright before it is
relied on. Containers are local too: Docker Engine is in the base and wakes
on first use (`01-host-and-boot.md`).

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
