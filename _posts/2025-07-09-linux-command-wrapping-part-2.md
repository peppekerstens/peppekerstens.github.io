---
title: Prepping environment - Linux Command Wrapping Part 2
toc: true
---

Before we get into the nitty gritty of figuring stuff out, we need to set things up. This article describes our baseline.

This is not going to be detailled walk-through on any and every step I do or did. The assumption is that you are an experienced PowerShell coder and have created PowerShell modules before. That being said, I always found it annoying when somebody posted some code with no reference in which circumanstances they developed and tested it, resulting in you having to spend your precious time in figuring that out instead of actually contributing. So here is a run-over of our development environment baseline.

The assumption here is that all is being done on an Windows 11 machine with both [Windows Terminal](https://learn.microsoft.com/shows/open-at-microsoft/introduction-to-windows-terminal) and [Visual Studio Code](https://code.visualstudio.com/) already is present on the system.

Before anything can be done, we need a Linux box with PowerShell on it.

*note to self: replace all of this with winget install script*

### WSL

The [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/) (WSL) is perfect for this. Previos link explains on how to instal WSL. By default, Ubuntu will be installed.

When you have installed Docker for instance, you may find that WSL already is present on your system. Then you just need to add Ubuntu via de command-line like this:

```cmd
wsl --install ubuntu
```

You will be asked to provide credetials to logon into Ubuntu. 

You can set the Ubuntu system as the default one like this:

```cmd
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

```cmd
wsl --update ubuntu
```

Once everything is installed, you can either call/activate a session via just calling wsl on the command line, or by selecting it in the drop down menu in Windows Terminal.

The version I am working on:

```bash
Welcome to Ubuntu 24.04.2 LTS (GNU/Linux 6.6.87.2-microsoft-standard-WSL2 x86_64)
```

### PowerShell

Installing PowerShell can be done in a number of ways. To best working manual option for me was using [the script provided here](https://learn.microsoft.com/powershell/scripting/install/install-ubuntu?view=powershell-7.5). It also updates the system. Below is just a copy of that script for your convienience.

```bash
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

## Using the system

In follow up articles i'll be using the above setup. I will be switching back and forth from the Linux and Windows environments quite a lot.

Because they are on the same machine, you should be able to have access to both file-systems; WSL2 exposes the filesystems in Windows Explorer by default.

It is also quite easy to execute WSL commands from the Windows environment. This can be either Linux or PowerShell commands (once being set-up as described above)

```powershell
wsl lsblk
NAME
    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda   8:0    0 388.4M  1 disk
sdb   8:16   0   186M  1 disk
sdc   8:32   0     4G  0 disk [SWAP]
sdd   8:48   0     1T  0 disk /mnt/wslg/distro

wsl pwsh {get-module -listavailable}

    Directory: /opt/microsoft/powershell/7/Modules

ModuleType Version    PreRelease Name                                PSEdition ExportedCommands
---------- -------    ---------- ----                                --------- ----------------
Manifest   1.2.5                 Microsoft.PowerShell.Archive        Desk      {Compress-Archive, Expand-Archive}
Manifest   7.0.0.0               Microsoft.PowerShell.Host           Core      {Start-Transcript, Stop-Transcript}
Manifest   7.0.0.0               Microsoft.PowerShell.Management     Core      {Add-Content, Clear-Content, Clear-Item…
Binary     1.1.1                 Microsoft.PowerShell.PSResourceGet  Core,Desk {Compress-PSResource, Find-PSResource, …
Manifest   7.0.0.0               Microsoft.PowerShell.Security       Core      {Get-Credential, Get-ExecutionPolicy, S…
Manifest   7.0.0.0               Microsoft.PowerShell.Utility        Core      {Export-Alias, Get-Alias, Import-Alias,…
Script     1.4.8.1               PackageManagement                   Desk      {Find-Package, Get-Package, Get-Package…
Script     2.2.5                 PowerShellGet                       Desk      {Find-Command, Find-DSCResource, Find-M…
Script     2.3.6                 PSReadLine                          Desk      {Get-PSReadLineKeyHandler, Set-PSReadLi…
Binary     2.0.3                 ThreadJob                           Desk      Start-ThreadJob

```
