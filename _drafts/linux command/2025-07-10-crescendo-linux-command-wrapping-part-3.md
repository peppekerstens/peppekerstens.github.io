---
title: Crescendo - Linux Command Wrapping  Part 3
toc: true
---

This is a follow up article in a series on command wrapping. I'm rambling about Crescendo and whether I deem it to be of added value for creating PowerShell cmdlets for Linux. Although I try to make sense of what I do here whilst trying to figure stuff out, this is not meant to be an absolute beginners introduction the Crescendo.

I will assume that you have at least read [the documentation](https://learn.microsoft.com/powershell/utility-modules/crescendo/get-started/install-crescendo?view=ps-modules) and/or checked out [Jason Helmick's video series](https://www.youtube.com/playlist?list=PLdESG89G24aMfg9LHFfpdi4TsKoOZ1iUH) or [Adam Driscol's video](https://www.youtube.com/watch?v=c9m7ZdSwgkQ).

## Get-Disk

Let's linger on a replacement for the Get-Disk cmdlet as a use-case for Crescendo. We will limit ourselves to default behaviour for now. [Default behavior is reporting all disks, based on disk number](https://learn.microsoft.com/powershell/module/storage/get-disk).

The output is [documented as being an CIM representation of the WMI class: ROOT/Microsoft/Windows/Storage/MSFT_Disk](https://learn.microsoft.com/dotnet/api/microsoft.management.infrastructure.ciminstance#ROOT/Microsoft/Windows/Storage/MSFT_Disk). But the published link does not provide clarity on what that object looks like, [this one does](https://learn.microsoft.com/windows-hardware/drivers/storage/msft-disk)

### AI helping out

As anyone nowadays, I asked an LLM to create me an example:

*as a PowerShell developer, write a function which equals the get-disk function for ubuntu*

>To run a PowerShell equivalent of Get-Disk on Linux, you can use PowerShell Core (pwsh) and access Linux disk information via native commands like lsblk, df, or fdisk. Here's a PowerShell function that wraps lsblk and parses its output:

```powershell
function Get-LinuxDiskInfo {
    [CmdletBinding()]
    param ()

    $lsblkOutput = lsblk --json | ConvertFrom-Json

    $lsblkOutput.blockdevices | ForEach-Object {
        [PSCustomObject]@{
            Name       = $_.name
            Type       = $_.type
            Size       = $_.size
            Mountpoint = $_.mountpoint
            FSType     = $_.fstype
            Model      = $_.model
            Serial     = $_.serial
        }
    }
}
```

>Here's an enhanced PowerShell function for Linux that mimics lsblk and also includes partition hierarchy and SMART health data (if available via smartctl):

```powershell
function Get-LinuxDiskDetails {
    [CmdletBinding()]
    param ()

    # Check if smartctl is available
    $smartctlAvailable = Get-Command smartctl -ErrorAction SilentlyContinue

    # Get disk and partition info
    $lsblk = lsblk --json -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL | ConvertFrom-Json

    foreach ($disk in $lsblk.blockdevices) {
        $health = $null
        if ($smartctlAvailable -and $disk.type -eq 'disk') {
            try {
                $smart = smartctl -H "/dev/$($disk.name)" 2>$null
                $health = ($smart | Where-Object { $_ -match "SMART overall-health self-assessment test result" }) -replace '.*result: ', ''
            } catch {
                $health = "Unavailable"
            }
        }

        [PSCustomObject]@{
            Name       = $disk.name
            Type       = $disk.type
            Size       = $disk.size
            Model      = $disk.model
            Serial     = $disk.serial
            Mountpoint = $disk.mountpoint
            FSType     = $disk.fstype
            Health     = $health
            Children   = $disk.children | ForEach-Object {
                [PSCustomObject]@{
                    Name       = $_.name
                    Size       = $_.size
                    Mountpoint = $_.mountpoint
                    FSType     = $_.fstype
                }
            }
        }
    }
}

```

### Compare with original

From an input/output perspective, the AI provided solutions do not even come close 

So the baseline flow of Crescendo 

## Cmdlets

Both [the documentation](https://learn.microsoft.com/powershell/module/microsoft.powershell.crescendo/?view=ps-modules) as the actual module display 10 cmdlets

```powershell
get-command -module  microsoft.powershell.crescendo

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Function        Export-CrescendoCommand                            1.1.0      microsoft.powershell.crescendo
Function        Export-CrescendoModule                             1.1.0      microsoft.powershell.crescendo
Function        Export-Schema                                      1.1.0      microsoft.powershell.crescendo
Function        Import-CommandConfiguration                        1.1.0      microsoft.powershell.crescendo
Function        New-CrescendoCommand                               1.1.0      microsoft.powershell.crescendo
Function        New-ExampleInfo                                    1.1.0      microsoft.powershell.crescendo
Function        New-OutputHandler                                  1.1.0      microsoft.powershell.crescendo
Function        New-ParameterInfo                                  1.1.0      microsoft.powershell.crescendo
Function        New-UsageInfo                                      1.1.0      microsoft.powershell.crescendo
Function        Test-IsCrescendoCommand                            1.1.0      microsoft.powershell.crescendo
```

Apart from that, to me, the documentation does not seem to provide a clear overview in the conversion proces and which cmdlets should be used in which order.


[Documentation states](https://learn.microsoft.com/powershell/module/microsoft.powershell.crescendo/about/about_crescendo?view=ps-modules): The PowerShell Crescendo module provides a novel way to create proxy functions for native commands via JSON configuration files.

The module itself has not been updated for about a year at time of this writing and only has 10 maintainers.




