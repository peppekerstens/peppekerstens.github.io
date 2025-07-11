---
title: Crescendo - Linux Command Wrapping  Part 3
toc: true
---

This is a follow up article in a series on command wrapping. I'm rambling about Crescendo and whether I deem it to be of added value for creating PowerShell cmdlets for Linux. Although I try to make sense of what I do here whilst trying to figure stuff out, this is not meant to be an absolute beginners introduction the Crescendo.

I will assume that you have at least read [the documentation](https://learn.microsoft.com/powershell/utility-modules/crescendo/get-started/install-crescendo?view=ps-modules) and/or checked out [Jason Helmick's video series](https://www.youtube.com/playlist?list=PLdESG89G24aMfg9LHFfpdi4TsKoOZ1iUH) or [Adam Driscol's video](https://www.youtube.com/watch?v=c9m7ZdSwgkQ)



After viewing [Adam Driscol's video](https://www.youtube.com/watch?v=c9m7ZdSwgkQ), it made more sense to me.

has produced a more extensive series of videos
Although he only used a single cmdlet from the module.

[Documentation states](https://learn.microsoft.com/powershell/module/microsoft.powershell.crescendo/about/about_crescendo?view=ps-modules): The PowerShell Crescendo module provides a novel way to create proxy functions for native commands via JSON configuration files.

The module itself has not been updated for about a year at time of this writing and only has 10 maintainers.

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




## Converting the 