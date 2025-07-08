---
title: Linux Command Wrapping - part 2
toc: true
---

## Prepping the system

The assumption here is that all is being done on an Windows 11 machine with both [Windows Terminal](https://learn.microsoft.com/shows/open-at-microsoft/introduction-to-windows-terminal) and [Visual Studio Code](https://code.visualstudio.com/) already is present on the system.

Before anything can be done, we need a Linux box with PowerShell on it.

*note to self: replace all of this with winget install script*

### WSL

The [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/) (WSL) is perfect for this. Previos link explains on how to instal WSL. By default, Ubuntu will be installed.

When you hae installed Docker for instance, you may find that WSL already is present on your system. Then you just need to add Ubuntu via de command-line like this:

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

### PowerShell

Installing PowerShell can be done in a number of ways. To best working manual option for me was using [the script provided here](https://learn.microsoft.com/powershell/scripting/install/install-ubuntu?view=powershell-7.5). It also updates the system.

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
