# First real test: the laptop

The laptop is the first machine to run the Windows half. It is going to be
formatted afterwards, so the test can run on it as it is today. The PC stays
untouched.

What has been tested before this: the Linux half, from an empty image, in the
lab (`data/runs/`). The Windows script has only run in dry-run mode on the
PC. Its apply path has never run. Expect it to need fixes.

## 1. By hand, in PowerShell on the laptop

```powershell
winget install --id Git.Git --exact
winget install --id GitHub.cli --exact
winget install --id Anthropic.ClaudeCode --exact
```

Open a new PowerShell window, then:

```powershell
gh auth login
gh repo clone dchavesh/workstation "$HOME\workstation"
cd "$HOME\workstation"
claude
```

## 2. The prompt for that session

> Read README.md, research/EVIDENCE.md, windows/LAPTOP-TEST.md and
> windows/install.ps1 first. This laptop is the first real test of this
> repo's Windows half. It will be formatted afterwards, so nothing on it
> needs preserving, but do not delete personal files.
>
> 1. Run `powershell -ExecutionPolicy Bypass -File windows\install.ps1 -DryRun`
>    and show me what it would change.
> 2. When I say go, run it without `-DryRun`. Each time it prints a step for
>    me (a restart, creating the Linux user, the sudo password), stop and
>    give me the exact command to run. Afterwards run the script again.
> 3. When the Linux side is installed, run `machine/verify.sh --json` inside
>    the distro. Save the result as `data/runs/<UTC time>-laptop/verify.json`
>    in this repo, next to a `notes.md` that lists everything that failed,
>    needed a manual step, or surprised you, on Windows or on Linux.
> 4. If a script has a bug, fix it in the repo and say what you changed and
>    why.
> 5. Do not change anything under `~/.claude` or any Claude Code setting. Do
>    not install anything that is not declared in this repo.
> 6. Commit on a branch named `laptop-test` and push it. Do not merge it into
>    master.

## 3. What comes back

The branch `laptop-test`, holding the laptop's first data record and the
notes. The PC session reads them and decides what changes.
