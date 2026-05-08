---
title: Update.Linux - Wrapping apt as a PSWindowsUpdate Peer - Linux Command Wrapping Part 11
toc: true
---

Part 10 laid out the patterns. Part 11 is where things get slightly more interesting, because this module is not wrapping a built-in Windows module — it is wrapping a community one.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## Why PSWindowsUpdate?

The other modules in this series have Windows built-ins as their peer: `Storage`, `NetTCPIP`, `Microsoft.PowerShell.Management`. PSWindowsUpdate is different — it is a community module. But it is an extremely widely used one. For a lot of sysadmins, `Get-WindowsUpdate` and `Install-WindowsUpdate` are just part of the standard toolkit. Automation scripts pass updates through it, patch compliance tools expect its output format, runbooks call it directly.

On a Linux box managed alongside Windows machines, I want the same mental model to work. Get updates. Install updates. Check what was installed. Same cmdlet names, same parameter shapes, same output properties — backed by `apt` and `dpkg` instead of the Windows Update API.

That is what `Update.Linux` is.

## What gets mapped

PSWindowsUpdate exports 22 cmdlets. Three of them cover the overwhelming majority of real-world use:

| Linux-native name | PSWindowsUpdate equivalent | Linux tool |
|---|---|---|
| `Get-LinuxUpdate` | `Get-WindowsUpdate` | `apt list --upgradable` |
| `Install-LinuxUpdate` | `Install-WindowsUpdate` | `apt-get upgrade` / `apt-get install` |
| `Get-LinuxUpdateHistory` | `Get-WUHistory` | `/var/log/dpkg.log` |

The remaining 19 cmdlets are exported as stubs. They run, they emit a warning, they return nothing. Better than a missing command error.

## The naming decision

The first draft named the functions exactly as PSWindowsUpdate does: `Get-WindowsUpdate`, `Install-WindowsUpdate`, `Get-WUHistory`. Straightforward. But calling a function `Get-WindowsUpdate` on a Linux machine is just wrong. The noun says "Windows". Anyone reading that in a Linux script has to stop and think about whether it is actually doing what the name implies.

So: Linux-appropriate names for the actual functions, and the PSWindowsUpdate names exported as **aliases**.

```powershell
# .psm1 — after dot-sourcing function files
Set-Alias -Name 'Get-WindowsUpdate'     -Value 'Get-LinuxUpdate'
Set-Alias -Name 'Install-WindowsUpdate' -Value 'Install-LinuxUpdate'
Set-Alias -Name 'Get-WUHistory'         -Value 'Get-LinuxUpdateHistory'
Set-Alias -Name 'Hide-WindowsUpdate'    -Value 'Hide-LinuxUpdate'
Set-Alias -Name 'Remove-WindowsUpdate'  -Value 'Remove-LinuxUpdate'
Set-Alias -Name 'Show-WindowsUpdate'    -Value 'Show-LinuxUpdate'
```

Scripts written for PSWindowsUpdate keep working without modification. `Get-WindowsUpdate` is a valid command and behaves identically to `Get-LinuxUpdate`. But anything written fresh for Linux should use the Linux name. Intent is self-documenting.

The `WU*`-prefixed stubs (`Get-WUApiVersion`, `Add-WUServiceManager`, etc.) keep their original names. The `WU` prefix is PSWindowsUpdate-specific shorthand that does not actually say "Windows", so renaming those would just be noise.

## Implementing Get-LinuxUpdate

`apt list --upgradable` returns one line per upgradable package:

```
Listing...
bash/jammy-updates 5.1-6ubuntu1.1 amd64 [upgradable from: 5.1-6ubuntu1]
curl/jammy-updates,jammy-security 7.81.0-1ubuntu1.15 amd64 [upgradable from: 7.81.0-1ubuntu1.14]
```

The first `Listing...` line goes to stdout, not stderr. So you cannot just redirect stderr away and call it done — you have to filter that line explicitly:

```powershell
$raw = apt list --upgradable 2>/dev/null | Where-Object { $_ -match '/' }
```

Each remaining line is parsed with a regex:

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

The output object mirrors the PSWindowsUpdate output shape on purpose. A script that does `(Get-WindowsUpdate)[0].IsInstalled` or `Get-WindowsUpdate | Where-Object { $_.RebootRequired }` should just work.

## Implementing Get-LinuxUpdateHistory

`/var/log/dpkg.log` keeps a record of everything the package manager has done. The format is straightforward:

```
2026-05-08 12:34:56 upgrade bash:amd64 5.1-6ubuntu1 5.1-6ubuntu1.1
2026-05-08 12:34:57 status installed bash:amd64 5.1-6ubuntu1.1
```

Only the action lines are useful (`install`, `upgrade`, `remove`, `purge`, `configure`). The `status` lines are noise and get filtered:

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

The output mirrors `Get-WUHistory`: `Date`, `Title`, `Version`, `Result` — the fields most scripts actually use.

## Implementing Install-LinuxUpdate

`Install-LinuxUpdate` maps to `apt-get upgrade` for everything, or `apt-get install <packages>` when `-Title` is specified to filter:

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

After the install, `/var/run/reboot-required` gets checked. If it exists and `-IgnoreReboot` is not set, the user gets a warning. `-AutoReboot` triggers `shutdown -r 0` immediately.

The function uses `[CmdletBinding(SupportsShouldProcess)]`, so `-WhatIf` and `-Confirm` work as expected:

```powershell
if ($PSCmdlet.ShouldProcess($targetDesc, 'Install-LinuxUpdate')) {
    # apt-get call here
}
```

## A note on the Windows fallback

The module guard in `.psm1` throws on Windows before any functions are loaded, so on Windows the module never loads at all. There is no path where `Get-LinuxUpdate` gets called on a Windows machine via this module.

That said, each of the three implemented functions also contains a platform check that delegates to PSWindowsUpdate if it is available. In practice this branch never runs, but it documents intent and makes the functions testable in isolation on Windows if you want to do that:

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

| Environment | Passed | Skipped | Failed |
|---|---|---|---|
| Windows (Pester 5.3.3) | 63 | 71 | 0 |
| WSL2 Ubuntu (Pester 5.7.1) | 134 | 0 | 0 |

No platform skips on Linux — all 134 tests run. The alias tests explicitly verify that `Get-WindowsUpdate` resolves to `Get-LinuxUpdate` and `Get-WUHistory` resolves to `Get-LinuxUpdateHistory`. That felt important to test explicitly rather than trust that the aliases were set up correctly.

## Example scripts

Four examples, covering the patterns most people actually need:

- **`Get-AvailableUpdates.ps1`** — list all upgradable packages in a table
- **`Get-PackageHistory.ps1`** — show recent package actions from the dpkg log
- **`Get-SecurityUpdates.ps1`** — filter `Get-LinuxUpdate` results to security repositories
- **`Get-UpdateSummary.ps1`** — combined report: available updates grouped by repository, plus recent history

All use the Linux-native names. The PSWindowsUpdate alias test is in `Examples.Tests.ps1`:

```powershell
It 'alias Get-WindowsUpdate works as a parity alias' -Skip:(-not $IsLinux) {
    { Get-WindowsUpdate } | Should -Not -Throw
}
```

## What is not done yet

The 16 remaining `WU*` stubs are stubs because either they have no meaningful Linux equivalent (Windows Update service management, WSUS configuration), or I just have not gotten to them yet. Some could theoretically be mapped:

- `Get-WURebootStatus` — could check `/var/run/reboot-required`
- `Get-WUSettings` / `Set-WUSettings` — could map to `/etc/apt/apt.conf.d/` configuration
- `Hide-LinuxUpdate` / `Show-LinuxUpdate` — could use `apt-mark hold` / `apt-mark unhold`

They have a warning message pointing at the GitHub repository. Contributions welcome.

## Repository

[https://github.com/peppekerstens/Update.Linux](https://github.com/peppekerstens/Update.Linux) — v0.2.0

## Next up

`PowerShell.Security.Linux` — implementing `Get-Acl` and `Set-Acl` via `getfacl` and `setfacl`.
