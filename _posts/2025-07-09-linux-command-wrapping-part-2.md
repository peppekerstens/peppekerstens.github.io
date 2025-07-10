---
title: Linux Command Wrapping - part 2
toc: true
---

## The joke is on me

My original detailled approach plan was:

1. Extract all cmdlets from original module and use them as input for the Linux module
2. Create empty proxy functions for all cmdlets
3. Insert Linux code in every function. Starting out with a warning that the Linux equivalent is not implemented yet
4. Create PowerShell equivalents of Linux command-line tools. If possible and of added value, using Crescendo.
5. Merging the PowerShell equivalents into the previous created proxy function.

...or so I thought. Well, this plan went sour very fast. :|

Naturally, I played around with some code a bit before diving in. At this point, I am tempted to say that the whole proxy functionality within PowerShell is FUBAR. Besides that, cmdlets build upon .Net functionality which simply is not present in Linux, which is the whole reason why they are not there Linux in the first place I guess

So in this article I take you down with me into my rabit-hole.

## Prepping the system

This is not going to be detailled walk-through on any and every step I do or did. The assumption is that you are an experienced PowerShell coder and have created PowerShell modules before. That being said, I always found it annoying when somebody posted some code with no reference in which circumanstances they developed and tested it, resulting in you having to spend your precious time in figuring that out instead of actually contributing. So here is a run-over of our development environment baseline.

The assumption here is that all is being done on an Windows 11 machine with both [Windows Terminal](https://learn.microsoft.com/shows/open-at-microsoft/introduction-to-windows-terminal) and [Visual Studio Code](https://code.visualstudio.com/) already is present on the system.

Before anything can be done, we need a Linux box with PowerShell on it.

*note to self: replace all of this with winget install script*

### WSL

The [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/) (WSL) is perfect for this. Previos link explains on how to instal WSL. By default, Ubuntu will be installed.

When you have installed Docker for instance, you may find that WSL already is present on your system. Then you just need to add Ubuntu via de command-line like this:

```text
wsl --install ubuntu
```

You will be asked to provide credetials to logon into Ubuntu. 

You can set the Ubuntu system as the default one like this:

```text
wsl --list
Windows Subsystem for Linux Distributions:
docker-desktop (Default)
Ubuntu

wsl --set-default ubuntu

wsl --list
Windows Subsystem for Linux Distributions:
Ubuntu (Default)
docker-desktop
```

If Ubuntu already is on your system, you can update in 2 ways. Either via Linux commands, shown in next section, or via the WSL command like this:

```text
wsl --update ubuntu
```

Once everything is installed, you can either call/activate a session via just calling wsl on the command line, or by selecting it in the drop down menu in Windows Terminal.

The version I am working on:

```text
Welcome to Ubuntu 24.04.2 LTS (GNU/Linux 6.6.87.2-microsoft-standard-WSL2 x86_64)
```

### PowerShell

Installing PowerShell can be done in a number of ways. To best working manual option for me was using [the script provided here](https://learn.microsoft.com/powershell/scripting/install/install-ubuntu?view=powershell-7.5). It also updates the system. Below is just a copy of that script for your convienience.

```tekst
###################################
# Prerequisites

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages.
sudo apt-get install -y wget apt-transport-https software-properties-common

# Get the version of Ubuntu
source /etc/os-release

# Download the Microsoft repository keys
wget -q https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb

# Register the Microsoft repository keys
sudo dpkg -i packages-microsoft-prod.deb

# Delete the Microsoft repository keys file
rm packages-microsoft-prod.deb

# Update the list of packages after we added packages.microsoft.com
sudo apt-get update

###################################
# Install PowerShell
sudo apt-get install -y powershell

# Start PowerShell
pwsh
```

## Some metadata and references

Some metadata for context and reference

### Windows PowerShell

```powershell
$psversiontable

Name                           Value
----                           -----
PSVersion                      5.1.26100.4061
PSEdition                      Desktop
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0...}
BuildVersion                   10.0.26100.4061
CLRVersion                     4.0.30319.42000
WSManStackVersion              3.0
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
```

### PowerShell Core (Windows)

```powershell
$PSversionTable

Name                           Value
----                           -----
PSVersion                      7.5.1
PSEdition                      Core
GitCommitId                    7.5.1
OS                             Microsoft Windows 10.0.26100
Platform                       Win32NT
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0…}
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
WSManStackVersion              3.0
```

### PowerShell Core (Ubuntu)

```powershell
$PSVersionTable

Name                           Value
----                           -----
PSVersion                      7.5.1
PSEdition                      Core
GitCommitId                    7.5.1
OS                             Ubuntu 24.04.2 LTS
Platform                       Unix
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0…}
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
WSManStackVersion              3.0
```

### Storage module

```powershell
get-module storage -ListAvailable

    Directory: C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules

ModuleType Version    PreRelease Name                                PSEdition ExportedCommands
---------- -------    ---------- ----                                --------- ----------------
Manifest   2.0.0.0               Storage                             Core,Desk {Add-InitiatorIdToMaskingSet, Add-Parti…

```

## Creating the proxy functions

In order to easilly create the proxy functions, I created a few helper functions like so:

```powershell
function New-ProxyFunction{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    #source: https://devblogs.microsoft.com/scripting/proxy-functions-spice-up-your-powershell-core-cmdlets/
    $MetaData = New-Object System.Management.Automation.CommandMetaData (Get-Command  $Name) 
    return [System.Management.Automation.ProxyCommand]::Create($MetaData)
}

function Initialize-Module{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
        ,
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    $module = Get-Module -Name $Name -ListAvailable
    if ($null -eq $module) {
        Write-Error "Module '$Name' not found."
        return
    }
    
    $functions = Get-Command -Module $Name | Where-Object { $_.CommandType -eq 'Function' }
    
    foreach ($function in $functions) {
        $scriptBlock = Join-Path -Path $Path -ChildPath "$($function.Name).ps1"
        if (-Not (Test-Path -Path $scriptBlock)) {
            New-Item -Path $scriptBlock -ItemType File -Force | Out-Null
        }
        # Write the proxy function to the script file
        "Function $($function.Name) {`n" | Set-Content -Path $scriptBlock
        New-ProxyFunction -Name $function.Name | Add-Content -Path $scriptBlock
        "`n}`n" | Add-Content -Path $scriptBlock
    }
}
```

With the above, a first set-up is easily made. After prepping a GitHub repo, all that is needed is starting PowerShell Core under Windows and:

```powershell
cd [path-to-module]
Initialize-Module -name storage -path .\Storage.Linux\functions
```

...and presto!  

```powershell
gci .\Storage.Linux\Functions\

    Directory: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\Storage.Linux\Functions

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
la---            7/9/2025 10:09 AM           3291 Add-InitiatorIdToMaskingSet.ps1
la---            7/9/2025 10:09 AM           3759 Add-PartitionAccessPath.ps1
la---            7/9/2025 10:09 AM           5355 Add-PhysicalDisk.ps1
la---            7/9/2025 10:09 AM           3585 Add-StorageFaultDomain.ps1
la---            7/9/2025 10:09 AM           2984 Add-TargetPortToMaskingSet.ps1
la---            7/9/2025 10:09 AM           3577 Add-VirtualDiskToMaskingSet.ps1
la---            7/9/2025 10:09 AM           2951 Block-FileShareAccess.ps1
la---            7/9/2025 10:09 AM           3971 Clear-Disk.ps1
la---            7/9/2025 10:09 AM           1517 Clear-FileStorageTier.ps1
la---            7/9/2025 10:09 AM           2945 Clear-StorageDiagnostic
```

## Testing the Get-Disk proxy function

In the below section, whenever something has gone wrong, I killed that session and spawned a new PowerShell session.

Checking out Get-Drive.ps:

```Powershell
cat .\Storage.Linux\Functions\get-disk.ps1 

Function Get-Disk {

[CmdletBinding(DefaultParameterSetName='ByNumber', PositionalBinding=$false)]
param(
    [Parameter(ParameterSetName='ByUniqueId')]
    [Alias('Id')]
    [ValidateNotNull()]
    [string[]]
    ${UniqueId},

    [Parameter(ParameterSetName='ByName')]
    [ValidateNotNull()]
    [string[]]
    ${FriendlyName},

    [Parameter(ParameterSetName='ByName')]
    [ValidateNotNull()]
    [string[]]
    ${SerialNumber},

    [Parameter(ParameterSetName='ByPath', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string[]]
    ${Path},

    [Parameter(ParameterSetName='ByNumber', Position=0, ValueFromPipelineByPropertyName=$true)]
    [Alias('DeviceId')]
    [ValidateNotNull()]
    [uint[]]
    ${Number},

    [Parameter(ParameterSetName='ByPartition', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_Partition')]
    [ciminstance]
    ${Partition},

    [Parameter(ParameterSetName='ByVirtualDisk', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_VirtualDisk')]
    [ciminstance]
    ${VirtualDisk},

    [Parameter(ParameterSetName='ByiSCSISession', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_iSCSISession')]
    [ciminstance]
    ${iSCSISession},

    [Parameter(ParameterSetName='ByiSCSIConnection', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_iSCSIConnection')]
    [ciminstance]
    ${iSCSIConnection},

    [Parameter(ParameterSetName='ByStorageSubSystem', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_StorageSubSystem')]
    [ciminstance]
    ${StorageSubSystem},

    [Parameter(ParameterSetName='ByStorageNode', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_StorageNode')]
    [ciminstance]
    ${StorageNode},

    [Parameter(ParameterSetName='ByStorageJob', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_StorageJob')]
    [ciminstance]
    ${StorageJob},

    [Parameter(ParameterSetName='ByStorageJob')]
    [Parameter(ParameterSetName='ByStorageNode')]
    [Parameter(ParameterSetName='ByStorageSubSystem')]
    [Parameter(ParameterSetName='ByiSCSIConnection')]
    [Parameter(ParameterSetName='ByiSCSISession')]
    [Parameter(ParameterSetName='ByVirtualDisk')]
    [Parameter(ParameterSetName='ByPartition')]
    [Parameter(ParameterSetName='ByNumber')]
    [Parameter(ParameterSetName='ByPath')]
    [Parameter(ParameterSetName='ByName')]
    [Parameter(ParameterSetName='ByUniqueId')]
    [Alias('Session')]
    [ValidateNotNullOrEmpty()]
    [CimSession[]]
    ${CimSession},

    [Parameter(ParameterSetName='ByStorageJob')]
    [Parameter(ParameterSetName='ByStorageNode')]
    [Parameter(ParameterSetName='ByStorageSubSystem')]
    [Parameter(ParameterSetName='ByiSCSIConnection')]
    [Parameter(ParameterSetName='ByiSCSISession')]
    [Parameter(ParameterSetName='ByVirtualDisk')]
    [Parameter(ParameterSetName='ByPartition')]
    [Parameter(ParameterSetName='ByNumber')]
    [Parameter(ParameterSetName='ByPath')]
    [Parameter(ParameterSetName='ByName')]
    [Parameter(ParameterSetName='ByUniqueId')]
    [int]
    ${ThrottleLimit},

    [Parameter(ParameterSetName='ByStorageJob')]
    [Parameter(ParameterSetName='ByStorageNode')]
    [Parameter(ParameterSetName='ByStorageSubSystem')]
    [Parameter(ParameterSetName='ByiSCSIConnection')]
    [Parameter(ParameterSetName='ByiSCSISession')]
    [Parameter(ParameterSetName='ByVirtualDisk')]
    [Parameter(ParameterSetName='ByPartition')]
    [Parameter(ParameterSetName='ByNumber')]
    [Parameter(ParameterSetName='ByPath')]
    [Parameter(ParameterSetName='ByName')]
    [Parameter(ParameterSetName='ByUniqueId')]
    [switch]
    ${AsJob})

begin
{
    try {
        $outBuffer = $null
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
        {
            $PSBoundParameters['OutBuffer'] = 1
        }

        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-Disk', [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = {& $wrappedCmd @PSBoundParameters }

        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($PSCmdlet)
    } catch {
        throw
    }
}

process
{
    try {
        $steppablePipeline.Process($_)
    } catch {
        throw
    }
}

end
{
    try {
        $steppablePipeline.End()
    } catch {
        throw
    }
}

clean
{
    if ($null -ne $steppablePipeline) {
        $steppablePipeline.Clean()
    }
}
<#

.ForwardHelpTargetName Get-Disk
.ForwardHelpCategory Function

#>


}

```

..and here the problems start.

First of all, severall parameters are being referenced by types which simply do not exist under Linux. For instance:

```Powershell
    [Parameter(ParameterSetName='ByPartition', ValueFromPipeline=$true)]
    [ValidateNotNull()]
    [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_Partition')]
    [ciminstance]
    ${Partition},
```

We should be able to fix this of course.

Secondly and foremost, the proxy function seems to crash. When creating the function as-is, one should be able to execute it as-is, at least on the PowerShell version you created it on.

Simplest way is to load it into session

```Powershell
. ./get-disk.ps1
get-disk
```

After a little wait, I get a ~5000 line crash stack and then a hanging PowerShell session! I posted the stack in the repo [here](). It is not all; the first part is not there. I tried to capture it, but it seems not contained within any PowerShell output stream. Like a hard crash.

I tried this on the other PowerShell versions available on my system, but they all crashed!

## Testin other proxy functions

Now, this might be me just having bad luck. So I checked my [old proxy function for Out-Gridview](https://gist.github.com/peppekerstens/b6553910fa316cfe9bdab2d73a3476a5).

```Powershell
. .\Out-Gridview.ps1
out-gridview
InvalidOperation: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\Helpers\Out-Gridview.ps1:45
Line |
  45 |          [Microsoft.PowerShell.Commands.OutputModeOption]
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Unable to find type [Microsoft.PowerShell.Commands.OutputModeOption].
```

ok....at least a normal error. Apparently, the Out-Gridview cmdlat has changed internally and the [Microsoft.PowerShell.Commands.OutputModeOption] type has been abandoned or something like that? 

Let's re-create the proxy function for Out-GridView using the helper funcions as stated earlier:

```PowerShell
Initialize-Module -name Microsoft.PowerShell.Utility .\PowerShell.Utility.Linux
```

Strangely enough, the [Microsoft.PowerShell.Commands.OutputModeOption] type is there as well:

```PowerShell
Function Out-GridView {

[CmdletBinding(DefaultParameterSetName='PassThru', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2109378')]
param(
    [Parameter(ValueFromPipeline=$true)]
    [psobject]
    ${InputObject},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Title},

    [Parameter(ParameterSetName='Wait')]
    [switch]
    ${Wait},

    [Parameter(ParameterSetName='OutputMode')]
    [Microsoft.PowerShell.Commands.OutputModeOption]
    ${OutputMode},

    [Parameter(ParameterSetName='PassThru')]
    [switch]
    ${PassThru})
```

Let's test out this one then:

```PowerShell
cd ./PowerShell.Utility.Linux
. ./Out-Gridview.ps1
Out-GridView
#checking if i really ran the proxy command; there should be no source..
get-command out-gridview

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Function        Out-GridView

```

Wait, what?!? No error....? Ok, the plot thickens! To confirm I started a new PowerShell session.

```PowerShell
# in-place loading of the old proxy code
cd .\helpers\
. .\Out-GridView.ps1
out-gridview
InvalidOperation: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\Helpers\Out-Gridview.ps1:45
Line |
  45 |          [Microsoft.PowerShell.Commands.OutputModeOption]
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Unable to find type [Microsoft.PowerShell.Commands.OutputModeOption].
# in-place loading of the proxy code I just created
cd..
cd .\PowerShell.Utility.Linux\
. .\Out-GridView.ps1
out-gridview
InvalidOperation: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\PowerShell.Utility.Linux\Out-GridView.ps1:18
Line |
  18 |      [Microsoft.PowerShell.Commands.OutputModeOption]
     |      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Unable to find type [Microsoft.PowerShell.Commands.OutputModeOption].
```

Ok...strange. So when does the error disappear then? Again, new PS session:

To confirm I started a new PowerShell session.

```PowerShell
get-command out-gridview

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Cmdlet          Out-GridView                                       7.0.0.0    Microsoft.PowerShell.Utility

# call it once
out-gridview
# are we sure that we called the original?
get-command out-gridview

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Cmdlet          Out-GridView                                       7.0.0.0    Microsoft.PowerShell.Utility

# load the old proxy code
cd C:\Users\peppe\OneDrive\GitHub\Storage.Linux
cd .\helpers\
. .\Out-GridView.ps1
out-gridview
Get-Content: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\Helpers\Out-Gridview.ps1:67
Line |
  67 |  … stomObject](Get-Content -Path "$($env:USERPROFILE)\.out-gridview.sett …"
     |                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Cannot find path 'C:\Users\peppe\.out-gridview.settings' because it does not exist.
# load the new proxy code
cd ..
cd .\PowerShell.Utility.Linux\
. .\Out-GridView.ps1
out-gridview
```

So my old code still errors, but on a different section which makes sense. Apparently the cmdlet must have been load before the [Microsoft.PowerShell.Commands.OutputModeOption] type gets detected.
Investigating a little further, this makes sense when you discover that [Microsoft.PowerShell.Commands.OutputModeOption] is part of the Microsoft.PowerShell.Commands.Utility.dll as stated [here](https://learn.microsoft.com/dotnet/api/microsoft.powershell.commands.outputmodeoption?view=powershellsdk-7.4.0)

Kind of misleading in my opinion. By its name, I would have expected that is was part of the PowerShell core types/enums.

## Abandoning proxy functions

A few hours burned and very little to show. This made me rethink about using proxy functions as a baseline. The cullprits are:

* Non explainable stack errors (so far)
* Parity with the original cdmlet or function also implies keeping that up. Whenever the source changes, you'll probably have to recreate the proxy function. Which may result in a lot of maintenance work when cmdlet coverage increases
* Depends on .Net code and/or dll's which may not be present on Linux. Needs a work-around, be emulated or recreated.
* For stuf to work on Linux, it is not absolutally needed

That's it for now.
