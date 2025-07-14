---
title: Crescendo - Linux Command Wrapping Part 4
toc: true
---

This is a follow up article in a series on command wrapping. I'm rambling about Crescendo and whether I deem it to be of added value for creating PowerShell cmdlets for Linux. Although I try to make sense of what I do here whilst trying to figure stuff out, this is not meant to be an absolute beginners introduction the Crescendo.

## References

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

## Get-LsBlk via Crescendo

So instead of trying to recreate Get-Drive, let's use Crescendo to create a PowerShell equivalent for lsblk first.

So let's start with the simplest setup, following what [we have just learned](#references)

```powershell
#linux box
#assumes crescendo module is installed
#in $home
$parameters = @{
    Verb = 'Get'
    Noun = 'LsBlk'
    OriginalName = "lsblk"
}
$CrescendoCommands += New-CrescendoCommand @parameters
Export-CrescendoCommand -command $CrescendoCommands -fileName .\lsblk.crescendo.json
```

This creates the following json:

```json
{
  "$schema": "https://aka.ms/PowerShell/Crescendo/Schemas/2022-06",
  "commands": [
    {
      "Verb": "Get",
      "Noun": "LsBlk",
      "OriginalName": "lsblk",
      "Platform": [
        "Windows",
        "Linux",
        "MacOS"
      ],
      "SupportsShouldProcess": false,
      "SupportsTransactions": false,
      "NoInvocation": false,
      "Parameters": [],
      "Examples": []
    }
  ]
}
```

Then create the module like this:

```powershell
#linux box
Export-CrescendoModule -ConfigurationFile ./lsblk.crescendo.json -ModuleName lsblk.psm1

Import-Module .\lsblk
Get-LsBlk
NAME  MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda   8:0    0 388.4M  1 disk
sdb   8:16   0   186M  1 disk
sdc   8:32   0     4G  0 disk [SWAP]
sdd   8:48   0     1T  0 disk /mnt/wslg/distro
```

After fiddling around with the config file for a while, I ended up with this:

```json
{
    "$schema": "https://aka.ms/PowerShell/Crescendo/Schemas/2022-06",
    "commands": [
        {
            "Verb": "Get",
            "Noun": "LsBlk",
            "OriginalName": "lsblk",
            "OriginalCommandElements": [
                "--json"
            ],
            "Platform": [
                "Linux"
            ],
            "SupportsShouldProcess": false,
            "SupportsTransactions": false,
            "NoInvocation": false,
            "Parameters": [
                {
                    "Name": "Output",
                    "OriginalName": "--output",
                    "ParameterType": "string",
                    "IsRequired": true,
                    "DefaultValue": "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,ROTA,RM,STATE,OWNER,GROUP,MODE"
                },
                {
                    "Name": "AllDevices",
                    "OriginalName": "-a",
                    "ParameterType": "switch"
                }
            ],
            "OutputHandlers": [
                {
                    "ParameterSetName": "Default",
                    "HandlerType": "Inline",
                    "Handler": "$args[0] | ConvertFrom-Json | Select-Object -ExpandProperty blockdevices",
                    "OutputType": "System.Collections.Generic.List`1[System.Management.Automation.PSObject]",
                    "OutputTypeDescription": "List of block devices with properties such as NAME, SIZE, TYPE, MOUNTPOINT, FSTYPE, MODEL, SERIAL, ROTA, RM, STATE, OWNER, GROUP, MODE."
                }
            ],
            "Description": "Get-LsBlk lists information about all available or the specified block devices. The lsblk command reads the sysfs filesystem and udev db to gather information. If the udev db is not available or lsblk is compiled without udev support, then it tries to read LABELs, UUIDs and filesystem types from the block device. In this case root permissions are necessary.",
            "Usage": {
                "Synopsis": "Lists information about all available or the specified block devices."
            },
            "HelpLinks": [
                "https://manpages.ubuntu.com/manpages/trusty/man8/lsblk.8.html"
            ],
            "Examples": []
        }
    ]
}
```

This can be improved upon of course, but for now it does the job.

## Caveats

During my Crescendo adventures, I found a few caveats. Let me stress that these might just be me knowing too little about Crescendo and it's features, does and dont's.

### Complex default command elements

Documentation says that you can add command elements that should always be executed in the "OriginalCommandElements" configuration section. So at first I added this:

```json
{
        "OriginalCommandElements": [
        "--json"
        "--output NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,ROTA,RM,STATE,OWNER,GROUP,MODE"
    ],
}
```

Although Crescendo throws no error during conversion, this does not work and the resulting function throws an error. The original command sees 'NAME" as a seperate parameter. I just stumbled upon following solution. It might be documented somewhere, but haven't found it:

```json
{
    "Parameters": [
        {
            "Name": "Output",
            "OriginalName": "--output",
            "ParameterType": "string",
            "IsRequired": true,
            "DefaultValue": "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,ROTA,RM,STATE,OWNER,GROUP,MODE"
        }
}
```

With the above, I expected the resulting function to error on the 'Output' parameter requirement when not provided. But apparently it does not. I do not know if this is a bug or behavior by design.

### OS detection does not seem to work

When creating a command for Linux, by setting the 'Platform' json configuration property to only Linux, I expected the resulting function to throw an error on the Windows platform. Something like 'Error, this function is not supported on Windows". Instead it just throws an error that it is not able to find lsblk.

```powershell
#windows box
get-lsblk                                               
Exception: Cannot find executable 'lsblk'
```

### Inline processing fiddlyness

Whilst trying to figure out a nice configuration, you'll end-up changing the json conigurationfile quite a lot. At some point in time, Crescendo started throwing this:

```powershell
import-module ./lsblk
ParserError: Missing closing '}' in statement block or type definition.
Import-Module: The module to process 'lsblk.psm1', listed in field 'ModuleToProcess/RootModule' of module manifest '/home/peppe/lsblk.psd1' was not processed because no valid module was found in any module directory.
```

Of course I blamed myself at first. So I re-checked the json file, reverting last changes, simplyfied it and so on. Visual Studio Code never showed markup errors. The error remained and would not go away anymore.

I was thrown off guard. I assumed some invisible corruption in the OutputHandlers section. When I added that sections, everything went sour. I ended up recreating the json file from scratch and plugging in its configuration item one at a time.

Eventually, I noticed that I did this:

```json
{
    "OutputHandlers": [
        {
            "HandlerType": "Inline",
            "Handler": "($args[0] | ConvertFrom-Json).blockdevices"
        }
    ]
}
```

I changed it to this:

```json
{
    "OutputHandlers": [
        {
            "HandlerType": "Inline",
            "Handler": "$args[0] | ConvertFrom-Json | Select-Object -ExpandProperty blockdevices"
        }
    ]
}
```

So I geuss you should be strict on obying the output stream order when choosing the 'Inline' HandlerType.

## Conclusion and next up

Getting my first command line wrapped by using Crescendo actually took me quite a while longer than I expected. Mainly because there is an investment to be done to figure out its behavior (and quirks?).

At this point, I'm on the fence on wether Crescendo will actually accelerate the command wrapping effort. For now, i'll keep using it as long as not to many other quirks pop-up.

At this point, I have not even started on the Get-Disk function. That's fine. I'll pick up on this in a next part somewhere...
