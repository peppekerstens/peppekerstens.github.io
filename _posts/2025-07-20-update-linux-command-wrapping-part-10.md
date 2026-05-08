---
title: Update.Linux - Wrapping apt as a PSWindowsUpdate Peer - Linux Command Wrapping Part 10
toc: true
---

Part 9 established the patterns that every module in this series follows: examples first, `BeforeDiscovery` for cross-platform test files, and a Linux-only guard in `.psm1`. Part 10 puts those patterns into practice with a new module: `Update.Linux`, a peer for the **PSWindowsUpdate** community module.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## Why PSWindowsUpdate?

The other modules in this series wrap built-in Windows modules — `Storage`, `NetTCPIP`, `Microsoft.PowerShell.Management`. PSWindowsUpdate is a community module, not a built-in. But it is extremely widely used: it is the de facto standard for managing Windows Update from PowerShell, and many automation scripts rely on its cmdlets.

On a Linux server managed alongside Windows machines, a sysadmin familiar with `Get-WindowsUpdate` and `Install-WindowsUpdate` should be able to apply the same mental model to Linux package updates. `Update.Linux` provides exactly that: the same cmdlet names, the same parameter shapes, the same output object properties — but backed by `apt` and `dpkg` instead of the Windows Update API.

## What gets mapped

PSWindowsUpdate exports 22 cmdlets. For a first release, three core cmdlets cover the most common automation patterns:

| Linux-native name | PSWindowsUpdate equivalent | Linux tool |
|---|---|---|
| `Get-LinuxUpdate` | `Get-WindowsUpdate` | `apt list --upgradable` |
| `Install-LinuxUpdate` | `Install-WindowsUpdate` | `apt-get upgrade` / `apt-get install` |
| `Get-LinuxUpdateHistory` | `Get-WUHistory` | `/var/log/dpkg.log` |

The remaining 19 cmdlets are exported as stubs that emit a `Write-Warning` and return nothing.

## The naming decision

The first draft named the functions exactly as PSWindowsUpdate does: `Get-WindowsUpdate`, `Install-WindowsUpdate`, `Get-WUHistory`. That is the straightforward parity approach. But on reflection, calling a function `Get-WindowsUpdate` on a Linux machine is confusing — and wrong. The noun says "Windows". Any developer reading `Get-WindowsUpdate` in a Linux script needs to stop and check whether this is actually doing what the name implies.

The resolution: use Linux-appropriate names for the actual functions, and export the PSWindowsUpdate names as **aliases**.

```powershell
# .psm1 — after dot-sourcing function files
Set-Alias -Name 'Get-WindowsUpdate'     -Value 'Get-LinuxUpdate'
Set-Alias -Name 'Install-WindowsUpdate' -Value 'Install-LinuxUpdate'
Set-Alias -Name 'Get-WUHistory'         -Value 'Get-LinuxUpdateHistory'
Set-Alias -Name 'Hide-WindowsUpdate'    -Value 'Hide-LinuxUpdate'
Set-Alias -Name 'Remove-WindowsUpdate'  -Value 'Remove-LinuxUpdate'
Set-Alias -Name 'Show-WindowsUpdate'    -Value 'Show-LinuxUpdate'
```

Scripts written for PSWindowsUpdate continue to work without modification — `Get-WindowsUpdate` is a valid command and behaves identically to `Get-LinuxUpdate`. But a new Linux-first script should use the Linux name. The intent is self-documenting.

The `WU*`-prefixed stubs (`Get-WUApiVersion`, `Add-WUServiceManager`, etc.) keep their original names. The `WU` prefix is a PSWindowsUpdate-specific abbreviation that does not mention "Windows"; renaming those would be gratuitous without adding clarity.

## Implementing Get-LinuxUpdate

The `apt list --upgradable` command returns one line per upgradable package in this format:

```
Listing...
bash/jammy-updates 5.1-6ubuntu1.1 amd64 [upgradable from: 5.1-6ubuntu1]
curl/jammy-updates,jammy-security 7.81.0-1ubuntu1.15 amd64 [upgradable from: 7.81.0-1ubuntu1.14]
```

The first "Listing..." line is always emitted to stdout (not stderr), so it must be filtered:

```powershell
$raw = apt list --upgradable 2>/dev/null | Where-Object { $_ -match '/' }
```

Each remaining line is parsed with a single regex:

```powershell
if ($line -match '^([^/]+)/(\S+)\s+(\S+)\s+(\S+)(?:\s+\[upgradable from:\s*([^\]]+)\])?') {
    [PSCustomObject]@{
        Title          = $Matches[1]
        Repository     = $Matches[2]
        Version        = $Matches[3]
        Architecture   = $Matches[4]
        CurrentVersion = $Matches[5]   # $null when no 'upgradable from' clause
        KB             = $null
        Size           = 0
        Status         = 'Available'
        Category       = 'Security'
        MsrcSeverity   = $null
        RebootRequired = $false
        IsDownloaded   = $false
        IsInstalled    = $false
        IsHidden       = $false
    }
}
```

The output object deliberately mirrors the PSWindowsUpdate output shape. A script that does `(Get-WindowsUpdate)[0].IsInstalled` or `Get-WindowsUpdate | Where-Object { $_.RebootRequired }` works without modification.

## Implementing Get-LinuxUpdateHistory

`/var/log/dpkg.log` records every package action the system has taken. Each line is structured:

```
2026-05-08 12:34:56 upgrade bash:amd64 5.1-6ubuntu1 5.1-6ubuntu1.1
2026-05-08 12:34:57 status installed bash:amd64 5.1-6ubuntu1.1
```

Only action lines (`install`, `upgrade`, `remove`, `purge`, `configure`) are relevant. `status` lines are filtered out:

```powershell
Get-Content '/var/log/dpkg.log' |
    Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (install|upgrade|remove|purge|configure) ' } |
    ForEach-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+([^:]+)(?::(\S+))?\s+(\S+)(?:\s+(\S+))?') {
            [PSCustomObject]@{
                Date         = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                Action       = $Matches[2]
                Title        = $Matches[3]
                Architecture = $Matches[4]
                Version      = $Matches[5]
                OldVersion   = $Matches[6]
                Result       = 'Succeeded'
                KB           = $null
            }
        }
    } |
    Sort-Object Date -Descending |
    Select-Object -First $Last
```

This mirrors the PSWindowsUpdate `Get-WUHistory` output: `Date`, `Title`, `Version`, `Result` — the fields most scripts use.

## Implementing Install-LinuxUpdate

`Install-LinuxUpdate` maps to `apt-get upgrade` (all packages) or `apt-get install <packages>` (filtered by `-Title`):

```powershell
if ($Title) {
    $packages = Get-LinuxUpdate -Title $Title | Select-Object -ExpandProperty Title
    $aptArgs  = @('install') + $packages + $(if ($AcceptAll) { @('-y') })
} else {
    $aptCmd  = if ($RecursiveInclude) { 'dist-upgrade' } else { 'upgrade' }
    $aptArgs = @($aptCmd) + $(if ($AcceptAll) { @('-y') })
}
& apt-get @aptArgs
```

After installation, `/var/run/reboot-required` is checked. If it exists and `-IgnoreReboot` is not set, the user gets a warning. `-AutoReboot` triggers an immediate `shutdown -r 0`.

The function uses `[CmdletBinding(SupportsShouldProcess)]` so `-WhatIf` and `-Confirm` work as expected:

```powershell
if ($PSCmdlet.ShouldProcess($targetDesc, 'Install-LinuxUpdate')) {
    # apt-get call here
}
```

## The Windows fallback

`Update.Linux` is Linux-only — the `.psm1` guard throws on Windows before any functions are loaded. But the three implemented functions each contain a Windows fallback that runs before the guard ever applies, since the guard is in the module loader while the function body runs after load. Wait — actually the guard throws at load time, so on Windows the module never loads and no function is ever defined.

For the rare case where someone calls `Get-LinuxUpdate` from a cross-platform script that has already handled the conditional import, the function itself also checks `$IsLinux` and delegates:

```powershell
if (-not $IsLinux) {
    if (Get-Module PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue) {
        PSWindowsUpdate\Get-WindowsUpdate @PSBoundParameters
    } else {
        Write-Warning "Get-LinuxUpdate: PSWindowsUpdate module is not installed..."
    }
    return
}
```

In practice this branch never runs (the module guard prevents loading on Windows), but it documents intent and makes the function unit-testable in isolation on Windows if needed.

## Module structure

```
Update.Linux/
  Update.Linux/
    Functions/
      Get-LinuxUpdate.ps1
      Install-LinuxUpdate.ps1
      Get-LinuxUpdateHistory.ps1
      Hide-LinuxUpdate.ps1
      Remove-LinuxUpdate.ps1
      Show-LinuxUpdate.ps1
      Add-WUServiceManager.ps1       # stub
      Disable-WURemoting.ps1         # stub
      Enable-WURemoting.ps1          # stub
      Get-WUApiVersion.ps1           # stub
      ... (13 more WU* stubs)
    Update.Linux.psm1
    Update.Linux.psd1
    Update.Linux.Tests.ps1
  Examples/
    Get-AvailableUpdates.ps1
    Get-PackageHistory.ps1
    Get-SecurityUpdates.ps1
    Get-UpdateSummary.ps1
    Examples.Tests.ps1
  README.md
  LICENSE
```

## Test results

The test suite covers module structure, manifest validation, file existence, syntax parsing, alias resolution, and runtime behaviour:

| Environment | Passed | Skipped | Failed |
|---|---|---|---|
| Windows (Pester 5.3.3) | 63 | 71 | 0 |
| WSL2 Ubuntu (Pester 5.7.1) | 134 | 0 | 0 |

All 134 tests run on WSL2 — there are no platform skips on Linux. The alias tests explicitly verify that `Get-WindowsUpdate` resolves to `Get-LinuxUpdate` and `Get-WUHistory` resolves to `Get-LinuxUpdateHistory`.

## Example scripts

Four example scripts cover the common patterns:

- **`Get-AvailableUpdates.ps1`** — list all upgradable packages in a table
- **`Get-PackageHistory.ps1`** — show recent package actions from the dpkg log
- **`Get-SecurityUpdates.ps1`** — filter `Get-LinuxUpdate` results to security repositories
- **`Get-UpdateSummary.ps1`** — combined report: available updates grouped by repository, plus recent history

All examples use the Linux-native function names. The PSWindowsUpdate alias test is in `Examples.Tests.ps1`:

```powershell
It 'alias Get-WindowsUpdate works as a parity alias' -Skip:(-not $IsLinux) {
    { Get-WindowsUpdate } | Should -Not -Throw
}
```

## What the module does not cover yet

The 16 remaining `WU*` stubs have no Linux equivalent today. Some have no meaningful mapping (Windows Update service management, WSUS configuration), and some could theoretically be mapped:

- `Get-WURebootStatus` — could check `/var/run/reboot-required`
- `Get-WUSettings` / `Set-WUSettings` — could map to `/etc/apt/apt.conf.d/` configuration
- `Hide-LinuxUpdate` / `Show-LinuxUpdate` — could use `apt-mark hold` / `apt-mark unhold`

These are left as stubs with a clear "contributions welcome" warning message pointing at the GitHub repository.

## Repository

[https://github.com/peppekerstens/Update.Linux](https://github.com/peppekerstens/Update.Linux) — v0.2.0

## Next up

`PowerShell.Security.Linux` — implementing `Get-Acl` and `Set-Acl` via `getfacl` and `setfacl`.
