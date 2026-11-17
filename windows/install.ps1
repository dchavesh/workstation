<#
.SYNOPSIS
  Sets up the Windows side of the workstation, then hands over to the Linux
  side. Windows is the desktop (apps, browser, terminal window); WSL is the
  workspace (tools, engines, projects, agents).

.DESCRIPTION
  Steps, each one checked before anything is changed:
    1. Windows apps from apps.json, with winget.
    2. %USERPROFILE%\.wslconfig, sized from this machine's memory.
    3. WSL itself.
    4. The Linux distro.
    5. This repo cloned inside the distro, and machine/install.sh run there.

  The script stops with an instruction whenever a person is needed: a
  restart, creating the Linux user, or typing the sudo password. Run it again
  afterwards; steps already done are skipped.

.PARAMETER DryRun
  Report the current state and what would change. Changes nothing.

.PARAMETER DistroName
  Name of the WSL distro to create or use.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$DistroName = 'Ubuntu-26.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:WSL_UTF8 = '1' # wsl.exe otherwise prints UTF-16, which PowerShell cannot compare

$UbuntuRelease = 'Ubuntu-26.04'
$MemoryShareForWsl = 0.55 # the rest stays with Windows and its apps
$MinimumWindowsBuild = 22000 # Windows 11
$RepoPathInDistro = 'projects/personal/systems/workstation' # relative to the Linux home
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppsFile = Join-Path $PSScriptRoot 'apps.json'
$WslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'

$script:ManualSteps = @()

function Write-State([string]$Label, [string]$Text) { '{0,-8} {1}' -f $Label, $Text | Write-Host }
function Write-Ok([string]$Text) { Write-State 'ok' $Text }
function Write-Change([string]$Text) { Write-State $(if ($DryRun) { 'would' } else { 'change' }) $Text }
function Add-ManualStep([string]$Text) { $script:ManualSteps += $Text; Write-State 'you' $Text }

function Test-Prerequisites {
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -lt $MinimumWindowsBuild) { throw "Windows 11 is required (build $build found)." }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget is missing. Install "App Installer" from the Microsoft Store.' }
    if (-not (Test-Path $AppsFile)) { throw "Cannot find $AppsFile." }
    Write-Ok "Windows build $build, winget $((winget --version) -join '')"
}

function Get-WantedAppIds {
    $apps = Get-Content -Raw -Path $AppsFile | ConvertFrom-Json
    foreach ($source in $apps.Sources) { foreach ($package in $source.Packages) { $package.PackageIdentifier } }
}

function Test-AppInstalled([string]$Id) {
    winget list --id $Id --exact --accept-source-agreements *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-Apps {
    $missing = @(Get-WantedAppIds | Where-Object { -not (Test-AppInstalled $_) })
    if ($missing.Count -eq 0) { Write-Ok 'every app in apps.json is installed'; return }
    Write-Change "install $($missing.Count) app(s): $($missing -join ', ')"
    if ($DryRun) { return }
    winget import --import-file $AppsFile --no-upgrade --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { Write-State 'warning' "winget import ended with code $LASTEXITCODE; run the script again to see what is still missing" }
}

function Get-WantedWslConfig {
    $totalGb = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $memoryGb = [math]::Max(4, [math]::Round($totalGb * $MemoryShareForWsl))
    return "[wsl2]`r`nmemory=${memoryGb}GB`r`n"
}

function Set-WslConfig {
    $wanted = Get-WantedWslConfig
    $current = if (Test-Path $WslConfigPath) { Get-Content -Raw -Path $WslConfigPath } else { '' }
    if (($current -replace '\s', '') -eq ($wanted -replace '\s', '')) { Write-Ok ".wslconfig is as wanted ($(($wanted -split "`r`n")[1]))"; return }
    Write-Change "write .wslconfig with $(($wanted -split "`r`n")[1])$(if ($current) { '; the current file is kept as a backup' })"
    if ($DryRun) { return }
    if ($current) { Copy-Item -Path $WslConfigPath -Destination "$WslConfigPath.before-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    Set-Content -Path $WslConfigPath -Value $wanted -Encoding ASCII -NoNewline
}

function Test-WslReady {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    wsl.exe --status *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-Wsl {
    if (Test-WslReady) { Write-Ok 'WSL is installed'; return $true }
    Write-Change 'install WSL (asks for administrator rights)'
    if ($DryRun) { return $false }
    wsl.exe --install --no-distribution
    Add-ManualStep 'Restart Windows, then run this script again.'
    return $false
}

function Get-DistroNames { @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

function Get-DistroUser { (wsl.exe --distribution $DistroName -- id -un 2>$null | Select-Object -First 1) }

# Returns $true when the distro exists and has a normal (non-root) user.
function Install-Distro {
    if ((Get-DistroNames) -notcontains $DistroName) {
        Write-Change "install $UbuntuRelease as a distro named '$DistroName'"
        if ($DryRun) { return $false }
        wsl.exe --install $UbuntuRelease --name $DistroName --no-launch
        if ($LASTEXITCODE -ne 0) { throw "wsl --install ended with code $LASTEXITCODE." }
    }
    $user = Get-DistroUser
    if (-not $user -or $user -eq 'root') {
        Add-ManualStep "Create your Linux user: run  wsl -d $DistroName  once, choose a name and password, type exit, then run this script again."
        return $false
    }
    Write-Ok "distro '$DistroName' exists, Linux user '$user'"
    return $true
}

function Invoke-InDistro([string]$Command) {
    wsl.exe --distribution $DistroName --cd '~' -- bash -c $Command
    return $LASTEXITCODE
}

function Copy-RepoIntoDistro {
    Invoke-InDistro "test -d $RepoPathInDistro/.git" *> $null
    if ($LASTEXITCODE -eq 0) { Write-Ok "the repo is in the distro at ~/$RepoPathInDistro"; return }
    Write-Change "clone this repo into the distro at ~/$RepoPathInDistro"
    if ($DryRun) { return }
    $windowsPath = $RepoRoot -replace '\\', '/'
    $origin = (git -C $RepoRoot remote get-url origin 2>$null)
    $code = Invoke-InDistro "set -e; source=`$(wslpath -a '$windowsPath'); mkdir -p `$(dirname $RepoPathInDistro); git clone --quiet `"`$source`" $RepoPathInDistro; if [ -n '$origin' ]; then git -C $RepoPathInDistro remote set-url origin '$origin'; fi"
    if ($code -ne 0) { throw 'Could not clone the repo into the distro.' }
}

function Install-LinuxSide {
    Invoke-InDistro 'command -v mise >/dev/null && test -L ~/.config/mise' *> $null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'the Linux side has been installed before; update it inside the distro with: mise bootstrap'; return }
    Write-Change "run machine/install.sh wsl inside the distro (asks for your sudo password)"
    if ($DryRun) { return }
    $code = Invoke-InDistro "bash ~/$RepoPathInDistro/machine/install.sh wsl"
    if ($code -ne 0) {
        Add-ManualStep "The Linux install stopped (code $code). In a terminal run:  wsl -d $DistroName -- bash ~/$RepoPathInDistro/machine/install.sh wsl"
        return
    }
    wsl.exe --terminate $DistroName *> $null
    Add-ManualStep "Check the result:  wsl -d $DistroName -- bash ~/$RepoPathInDistro/machine/verify.sh"
}

function Main {
    Write-Host $(if ($DryRun) { 'Dry run: nothing will be changed.' } else { 'Applying.' })
    Test-Prerequisites
    Install-Apps
    Set-WslConfig
    if ((Install-Wsl) -and (Install-Distro)) {
        Copy-RepoIntoDistro
        Install-LinuxSide
    }
    if ($script:ManualSteps.Count -gt 0) {
        Write-Host "`nSteps for you:"
        $script:ManualSteps | ForEach-Object { Write-Host "  - $_" }
    }
}

Main
