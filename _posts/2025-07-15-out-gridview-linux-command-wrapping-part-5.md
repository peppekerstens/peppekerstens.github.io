---
title: Out-Gridview - Linux Command Wrapping Part 5
toc: true
---

This is a follow up article in a series on command wrapping. This time, i'll try to get my first cmdlet to a more or less final state.

## Out-Gridview

In [an earlier post](https://peppekerstens.github.io/proxy-functions-linux-command-wrapping-part-3/), I checked my existing [proxy function](https://gist.github.com/peppekerstens/b6553910fa316cfe9bdab2d73a3476a5) for Out-Gridview.

As that point, two issues surfaced:

1. The [Microsoft.PowerShell.Commands.OutputModeOption] error
2. The .out-gridview.settings error, see below

Both should be relative easy to fix, so let's try to do that.

## Microsoft.PowerShell.Commands.OutputModeOption

[Microsoft.PowerShell.Commands.OutputModeOption is an enumerator and part of the Microsoft.PowerShell.Commands.Utility.dll](https://learn.microsoft.com//dotnet/api/microsoft.powershell.commands.outputmodeoption). It is a very simple one, enumerating None, Sinlge, Multiple. 

Afaik it is only used for the Out-Gridview cmdlet. But a simple test shows that it also surfaces on Linux:

```powershell
Import-Module Microsoft.PowerShell.Utility
[Microsoft.PowerShell.Commands.OutputModeOption]::Multiple
Multiple
```

As it is part of PowerShell *and* present on every platform, the error is a bit strange. There are a few ways around this:

1. Load the binaries beforehand, like above, somehow. Via [#requires](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_requires5) for instance.
2. Create a replacement [enumerator](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_enum)
3. Use a parameter [validator](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.5#validateset-attribute)

I wanted to get a bit fancy, and chose to define a enumerator like so:

```powershell
enum OutputModeOption{
    None
    Single
    Multiple
}
```

...and changed the parameter

```powershell
        [Parameter(ParameterSetName='OutputMode')]
        [OutputModeOption]
        ${OutputMode},
```

## out-gridview.settings

The original proxy function was meant to replace Out-Gridview with Out-ConsoleGridview on the Windows platform. The .out-gridview.settings file, saved in the usr profile, provided the option to switch between the console variant (or not) whenever Out-Gridview was called in a script.

The code itself *should* already be checking on the presence of that file and act accordingly:

```powershell
                Try{
                    $OutGridviewSettings = [PSCustomObject](Get-Content -Path "$($env:USERPROFILE)\.out-gridview.settings" | ConvertFrom-Json)
                }Catch{
                    #none found, set everything up for first time use
                    $OutGridviewSettings = [PSCustomObject]@{
                        ViewDefault = 'Gui'
                    }
                    $OutGridviewSettings | ConvertTo-Json | Set-Content -Path "$($env:USERPROFILE)\.out-gridview.settings" -Force
                }
```

but this try/catch clause is nested in another try/catch clause which is sketchy coding at best. That may be the reason why an error gets thrown:

```powershell
#.out-gridview.settings error
Get-Content: C:\....\Out-Gridview.ps1:67
Line |
  67 |  … stomObject](Get-Content -Path "$($env:USERPROFILE)\.out-gridview.sett …"
     |                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Cannot find path 'C:\...\.out-gridview.settings' because it does not exist.
```

Although I put it in a seperate funcion for readability, the solution ended up being that I forgot te force a stop action like so:

```powershell
    Try{
        $OutGridviewSettings = [PSCustomObject](Get-Content -Path "$($env:USERPROFILE)\.out-gridview.settings" -ErrorAction Stop| ConvertFrom-Json)
    }Catch{
```

## Module microsoft.powershell.consoleguitools

The script installs the module microsoft.powershell.consoleguitools. Again, this is normally not the purest PowerShell way. In an ideal world it would suffice to put *#requires -module microsoft.powershell.consoleguitools* at the beginning of the script.

In our case, this leads to having to install the module under PowerShell 5 under which it does not work. The installation by itself does work however, but it would lead to clutter. 

Also, module dependency in PowerShell has been a headache for a long time. With tha advent of PSResourceGet this should have been solved. Then again, there are still issues being reported in that area.

Hence I choose to install it via the function itself.

## Dynamic parameters

I wanted the 'ViewDefault' parameter only to surface in the PowerShell Core under Windows. This requires Dynamic Parameters. So this was my first tip-toe-ing into that. 

The [documentation on Dynamic Parameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.5#dynamic-parameters) is not very clear to me, so I read [this old article from 2014](https://powershellmagazine.com/2014/05/29/dynamic-parameters-in-powershell/) which explains it much better.

I gracefuly used a bit of code VSCode supplied me, et presto there we are:

```powershell
    DynamicParam {
        $paramDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        If ($IsWindows -and $IsCoreCLR){
            $paramAttributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $paramAttributes.Add((New-Object System.Management.Automation.ParameterAttribute -Property @{ Mandatory = $false; HelpMessage = "Set the default view for Out-GridView. Options are 'Console' or 'Gui'. Default is 'Gui'." }))
            $paramDictionary.Add('ViewDefault', (New-Object System.Management.Automation.RuntimeDefinedParameter('ViewDefault', [ViewDefaultOption], $paramAttributes)))
        }
        return $paramDictionary
    }
```

## Tests

I toped it off with having CoPilot writing Pester tests. Be aware that you'll need to install the latest Pester module for this. By default, Windows is shipped with a very old module.

## The result

You can find the result here: https://github.com/peppekerstens/PowerShell.Utility.Linux/tree/main/PowerShell.Utility.Linux 

Be mindfull that at this point in time, the module is work-in-progress and only the Out-GridView function is finished.