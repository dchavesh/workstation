# First test on the laptop

**The laptop is not empty.** It is set up like the PC: a working WSL distro,
the owner's dotfiles, Claude Code inside WSL. It will be formatted later, but
until then it is a machine in use and is treated exactly like the PC:

- The existing distro, its files, `.wslconfig`, Windows settings and
  installed apps are not changed.
- Tests run in a second, throwaway distro named `lab`, the same way they do
  on the PC. Only that distro is ever created or destroyed.
- Nothing under `~/.claude` and no Claude Code setting is changed.

So the first laptop test is the same rehearsal the PC has already passed,
run on different hardware, plus a dry run of the Windows script. Nothing new
needs to be installed on Windows for it.

## 1. By hand, in the laptop's existing WSL terminal

```sh
gh repo clone dchavesh/workstation ~/projects/personal/systems/workstation
cd ~/projects/personal/systems/workstation
claude
```

## 2. The prompt for that session

> Read README.md, research/EVIDENCE.md and windows/LAPTOP-TEST.md first.
> This laptop is set up like the owner's PC and is in use. Do not change its
> existing distro, its `.wslconfig`, any Windows setting or app, anything
> under `~/.claude`, or any Claude Code setting. The only thing you may
> create or destroy is a WSL distro named `lab`.
>
> 1. Run `lab/lab status`. If a distro named `lab` already exists, stop and
>    ask me before going on.
> 2. Run `lab/rehearse.sh`. It builds a `lab` distro from an empty Ubuntu
>    image, installs this repo's machine config in it, and checks the result.
>    It writes a record under `data/runs/`.
> 3. From WSL, run the Windows script in dry-run mode only and save what it
>    prints into the same record directory as `windows-dry-run.txt`:
>    `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w windows/install.ps1)" -DryRun -DistroName lab`
>    Never run it without `-DryRun`.
> 4. In the same directory write `notes.md`: everything that failed, needed
>    a manual step, took much longer than on the PC, or surprised you.
>    Compare the timings with the PC's records already in `data/runs/`.
> 5. If a script has a bug, fix it in the repo and say what you changed and
>    why.
> 6. Commit on a branch named `laptop-test` and push it. Do not merge it into
>    master.

## 3. What comes back

The branch `laptop-test`, with the laptop's first data record and the notes.
The PC session reads them and decides what changes.

## Not part of this test

Running `windows/install.ps1` for real. Its apply path has never run
anywhere. It is meant for the day a machine is actually formatted, and before
that it should be tried once with a new distro name on a machine where the
owner agrees to it.
