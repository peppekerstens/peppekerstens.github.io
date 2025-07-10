---
title: Linux Command Wrapping - part 1
toc: true
---

So I got myself insprired to do some PowerShell coding stuff again by watching some video's from [the European PowerShell Summit 2025](https://www.youtube.com/@PowerShellConferenceEU). This article rambles about the [Practical Linux automation with PowerShell](https://www.youtube.com/watch?v=RlzinWYIjBY) presented by Evgenij Smirnov.

## The high

This session especially intrigued me. First of all, I do IT stuff for a company which is mostly Windows oriented. Not even a handfull colleagues are Linux savvy. Still, customers do have Linux machines and request some form of support or service. Secondly, like Evgenij Smirnov states in his session, PowerShell was invisioned with a 'one to rule them all' mindset, unifying the way we command and script daily maintenance tasks for a variety of machines. Apparently, Linux still mostly seem to be 'undiscovered country'. And lastly, I believe Evgenij Smirnov's approach can be improved upon.

## The gap

The huge gap in existing 'inbox' PowerShell cmdlets for Linux versus Windows (~300 versus ~2000) was an eye opener for me. For some reason I just assumed that gap would have been bridged by others. But I guess others did the same as me; wait for it to happen...

[Evgenij Smirnov created an overview of cmdlets he views as 'essential' which in Linux.](https://github.com/psconfeu/2025/blob/main/Evgenij%20Smirnov/Linux/00-inthebox/MissingCmdletsGroupedSorted.ps1) A list of over 200 cmdlets.

## The approach

### Prioritise

I tend to agree that most of them have a value. But I am also convinced that some will probably be used more then others. I also stumbled upon some cmdlets which are not on my system at all. All the *nfs* commands for instance. So the first thing to do is to prioritise. Both distribution, most used cmdlets and most used parameters. Probably starting with only the default cmdlet behavior first (no/default params).

As [the Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/) defaults to Ubuntu and therefore would likely be most present on Windows oriented users who would like to try Linux, this should be the highest priority distribution.

A complete list and further detailing can be found in the repos fr each module as stated under [peer modules](#peer-modules)

### Work towards cmdlet parity and multi-platform

Aside from that, Evgenij Smirnov started creating a module build on script with 'alike' command names, adding the 'Linux' prenoun in front of a known noun. From a 'make it small, keep it simple' development perspective, this is perfectly fine and a good approach. But at end, to get adoption and traction, the original cmdlet call should 'just work' the same as it does on Windows. Or as close as it can be.

This can be achieved by using the proxy functions within PowerShell as [being explained by Shay Levy here](https://devblogs.microsoft.com/scripting/proxy-functions-spice-up-your-powershell-core-cmdlets/). I already created a proxy function for [Out-Gridvew a few years ago](https://gist.github.com/peppekerstens/b6553910fa316cfe9bdab2d73a3476a5).

Although it may seem silly to proxy a function on a system where that function does not exist, but in an ideal world our modules should end-up being multi-platform supported.

### Use frameworks

[Crescendo](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.crescendo/?view=ps-modules) is a development accelerator enabling you to rapidly build PowerShell cmdlets that leverage existing command-line tools. At least, that is what Microsoft claims.

[Jason Helmick](https://devblogs.microsoft.com/powershell/author/jahelmic/) endorsed this module a few years ago when it was being developed. Although the idea seemed promising, I have never actually played around with it. Mostly because mmost command-line tools already have been re-engineered in the Windows realm.

This would be a perfect oppertunity to test it out and evaluate if there is added value.

### Peer modules

Evgenij Smirnov proposes to put the cmdlets in [his module called Linux.Automation](https://github.com/it-pro-berlin-de/Linux.Automation).

Although I do have nothing against contributing, I believe this could be approached better by creating Linux module equivalents for the existing Windows modules. Below a conversion of [Evgenij Smirnov's list with regions](https://github.com/psconfeu/2025/blob/main/Evgenij%20Smirnov/Linux/00-inthebox/MissingCmdletsGroupedSorted.ps1)
 into Linux peer modules. Further reference will be based upon the Linux peer modules.

|Region | Noun | Windows module | Linux module |
|--|--|--|--|
|Disk|\*Disk\*|Storage|Storage.Linux|
|Disk|\*Partition\*|Storage|Storage.Linux|
|Disk|\*Volume\*|Storage|Storage.Linux|
|Printing|Print*|PrintManagement|PrintManagement.Linux|
|Networking|Net*|NetTCPIP|NetTCPIP.Linux|
|Services and Tasks|ScheduledTask*|ScheduledTasks|ScheduledTasks.Linux|
|Services and Tasks|Service*|Microsoft.PowerShell.Management|PowerShell.Management.Linux|
|Client functionality|Smb*|SmbShare|SmbShare.Linux|
|Client functionality|Nfs*|None|None|
|Security| Acl* | Microsoft.PowerShell.Security| PowerShell.Security.Linux|
|Security| Local* |Microsoft.PowerShell.LocalAccounts|PowerShell.LocalAccounts.Linux|
|Sundry| \*Certificate\*|PKI|PKI.Linux|
|Sundry|Computer|Microsoft.PowerShell.Management|PowerShell.Management.Linux|
|Sundry|Out-Printer| Microsoft.PowerShell.Utility| PowerShell.Utility.Linux|
|Sundry|Show-Command|Microsoft.PowerShell.Utility|PowerShell.Utility.Linux|

Furthermore, I believe that the above is missing cmdlets which are vital for day to day management of any system; patches and updates. And altough the basic command is quite simple on a Linix box, it would be a plus if the result is useable in PowerShell.

|Region | Noun | Windows module | Linux module |
|--|--|--|--|
|Update|\*|PSWindowsUpdate|Update.Linux|

Of lesser importance but still quite; package management. The downside is that PowerShell itself seems to be in an fluid state on this. I mean, we have packagemanagement, its succesor PSresource. And then there is winget. We won't touch WinGet as this is a command-line tool by itself with having severall PowerShell modules as being wrappers. But it might be smart to interogate those modules to check what others came up with.

|Region | Noun | Windows module | Linux module |
|--|--|--|--|
|PackageManagement|\*|PackageManagement|PackageManagement.Linux|
|PSResourceGet|\*|Microsoft.PowerShell.PSResourceGet|PowerShell.PSResourceGet.Linux|

## The low

Do not expect a complete finished series here ending in a 'command complete'  Linux ennvironment; it most likely will not. First and foremost this is a daunting task and lots of work. Too much to do it alone. Hence Evgenij Smirnov's call to action to contribute. I am doing this in my spare time, which is scarce these days.

I also tend not to follow through on stuff when there is no deadline or someone urging me to finish up. When doing stuff like this, I easily get sidetracked by something else.

As already noted, Linux still mostly seem to be 'undiscovered country'. There can be many reasons for this but at end, I can only conclude that the pickup is lacking. The same goes for the Crescendo module. With only 10 contributers and the last update about a year ago, there does not seem to be much going on.

So the question is; is anyone actually interested getting PowerShell stuff working on Linux?

## Next

Next post will detail more on prepping for the approach set out above.