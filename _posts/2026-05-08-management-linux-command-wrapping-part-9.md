---
title: Management - Linux Command Wrapping Part 9
toc: true
---

After the `Storage.Linux` module, the next obvious gap is service management. On Windows you reach for `Get-Service`, `Start-Service`, `Stop-Service`. On Linux, in PowerShell 7, those cmdlets are simply missing. This part covers `PowerShell.Management.Linux` and a useful discovery along the way: a lot of the Windows `Microsoft.PowerShell.Management` module already works on Linux.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## What is actually missing?

The Windows `Microsoft.PowerShell.Management` module exports 60 cmdlets. Before writing a single line of code, it is worth checking which of those 60 already work on Linux.

Quite a few of them are filesystem and path cmdlets: `Get-ChildItem`, `Copy-Item`, `Move-Item`, `Remove-Item`, `Get-Content`, `Set-Content`, `Join-Path`, `Split-Path`, `Test-Path`, `Resolve-Path` and so on. These are implemented in cross-platform .NET and work fine in PowerShell 7 on Linux. Same for process management: `Get-Process`, `Stop-Process`, `Start-Process`, `Wait-Process` — all fine. And timezone: `Get-TimeZone`, `Set-TimeZone` — works.

Strip those out and you are left with a much smaller gap. The cmdlets that genuinely do not work on Linux:

- `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service`, `Resume-Service`, `Suspend-Service`, `Set-Service`, `New-Service`, `Remove-Service`
- `Get-ComputerInfo`
- `Rename-Computer`, `Restart-Computer`, `Stop-Computer`
- `Get-HotFix`
- `Clear-RecycleBin`

That is 15 cmdlets. Eight get full implementations. Seven become stubs.

## Service management via systemctl

The obvious Linux equivalent of the Windows service stack is `systemd` and its `systemctl` command. Services on modern Ubuntu are systemd units.

`Get-Service` needed to be the most complete of the four service cmdlets. On Windows it returns objects with properties like `Name`, `DisplayName`, `Status`, `StartType`, `ServiceType`, `CanStop`, `CanPauseAndContinue`. We need to match that shape on Linux.

Two `systemctl` invocations cover the data we need:

```bash
# Running state
systemctl list-units --type=service --all --no-pager --plain

# Start type (enabled/disabled/static/etc.)
systemctl list-unit-files --type=service --no-pager --plain
```

The results are joined on the service name (stripping the `.service` suffix). Status is mapped from `active`/`inactive`/`failed` to `Running`/`Stopped`/`Failed`. StartType is mapped from `enabled`/`disabled`/`static` to `Automatic`/`Disabled`/`Manual`.

```powershell
function Get-Service {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string[]]$DisplayName,
        [string[]]$Include,
        [string[]]$Exclude
    )
    if ($IsLinux) {
        # ... systemctl parsing ...
        [PSCustomObject]@{
            Name                   = $svcName
            DisplayName            = $description
            Status                 = $status
            StartType              = $startType
            ServiceType            = 'Win32OwnProcess'
            CanStop                = $status -eq 'Running'
            CanPauseAndContinue    = $false
        }
    } else {
        Microsoft.PowerShell.Management\Get-Service @PSBoundParameters
    }
}
```

`Start-Service`, `Stop-Service` and `Restart-Service` are straightforward wrappers around `systemctl start`, `systemctl stop`, `systemctl restart`. They support `-PassThru` (calls `Get-Service` to return the updated object) and `-ShouldProcess` for `-WhatIf`/`-Confirm` support.

## Get-ComputerInfo

This one was more involved. On Windows, `Get-ComputerInfo` returns a single object with dozens of properties pulled from WMI. On Linux, equivalent information is scattered across several sources:

| Windows property | Linux source |
|---|---|
| `OsName`, `OsVersion` | `/etc/os-release` |
| `CsName` (hostname) | `hostname` / `hostnamectl` |
| `CsTotalPhysicalMemory` | `/proc/meminfo` |
| `CsNumberOfProcessors` | `/proc/cpuinfo` |
| `OsUptime` | `/proc/uptime` |
| `OsArchitecture` | `uname -m` |
| `TimeZone` | `timedatectl` |

The implementation reads those files and commands and assembles a single `PSCustomObject` with matching property names. The `-Property` parameter (present on the Windows version) lets callers filter which properties are returned — useful when you only need one or two fields and do not want to run all the underlying commands.

```powershell
Get-ComputerInfo -Property OsName,CsTotalPhysicalMemory
```

## Rename-Computer, Restart-Computer, Stop-Computer

`Rename-Computer` wraps `hostnamectl set-hostname`. It requires root. The function checks for elevation and throws a meaningful error if not running as root.

```powershell
if ((id -u) -ne '0') {
    throw 'Rename-Computer requires root privileges. Run with sudo.'
}
hostnamectl set-hostname $NewName
```

`Restart-Computer` and `Stop-Computer` wrap `shutdown -r` and `shutdown -h`. Both accept a `-Delay` parameter (in minutes, defaulting to 0 for immediate).

## The stubs

`Resume-Service`, `Suspend-Service`, `Set-Service`, `New-Service`, `Remove-Service` — these are service control operations that have no clean, general-purpose Linux equivalent. `systemctl` can do most of what you need, but the parameter shapes do not map cleanly and the use cases are uncommon enough that the risk of getting it wrong outweighs the benefit. They get stubs for now.

`Get-HotFix` and `Clear-RecycleBin` are Windows-specific concepts with no Linux equivalent.

All seven stubs follow the same pattern:

```powershell
function Resume-Service {
    [CmdletBinding()]
    param()
    if ($IsLinux) {
        Write-Warning "Resume-Service is not implemented in PowerShell.Management.Linux."
    } else {
        Microsoft.PowerShell.Management\Resume-Service @PSBoundParameters
    }
}
```

## What we did not implement (and why)

Several cmdlets that are in the Windows module are **already cross-platform in PowerShell 7** and work fine on Linux without any wrapping:

- `Get-Process`, `Stop-Process`, `Start-Process`, `Wait-Process` — .NET-based, cross-platform
- `Get-TimeZone`, `Set-TimeZone` — .NET-based, cross-platform
- All filesystem cmdlets (`Get-ChildItem`, `Copy-Item`, etc.) — cross-platform
- `Test-Connection` — cross-platform (uses ICMP via .NET)

These do not belong in `PowerShell.Management.Linux`. Including them would shadow the built-in implementations, which could cause subtle breakage.

## Module manifest

The module exports exactly the 15 functions that cover the real gap: 8 implemented, 7 stubs. Version 0.1.0.

```powershell
FunctionsToExport = @(
    'Get-Service', 'Start-Service', 'Stop-Service', 'Restart-Service',
    'Get-ComputerInfo', 'Rename-Computer', 'Restart-Computer', 'Stop-Computer',
    'Resume-Service', 'Suspend-Service', 'Set-Service',
    'New-Service', 'Remove-Service', 'Get-HotFix', 'Clear-RecycleBin'
)
```

## Next up

With service management and computer info handled, the next module in the queue is `NetTCPIP.Linux`: `Get-NetAdapter`, `Get-NetIPAddress`, `Get-NetRoute` — wrapping `ip link`, `ip addr` and `ip route`. That is part 10.
