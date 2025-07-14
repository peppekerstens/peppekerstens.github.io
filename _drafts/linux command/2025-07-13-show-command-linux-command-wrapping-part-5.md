---
title: Show Command - Linux Command Wrapping Part 5
toc: true
---

After Out-Gridview, the Show-Command seems a logical next candidate.

Although I really got inspired by the great work 



This article is part of a series on command wrapping.

The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY) 

## Show-Command

The Show-Command cmdlet presents a GUI in which you can search for PowerShell cmdlets. The GUI presents you the option to filter based on module but also search based on a partial name. Lastly, a ordered list of every cmdlet, complying with those search or filter parameters, is being shown.

Whenever a cmdlet is chosen, the GUI changes its interface to help you out with refining the actual command

A longer explanation is documented here: https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/show-command

>At time of this writing, on my machine the Show-Command cmdlet within PowerShell 7 seems to contain a bug. When I choose a command in the GUI, the following error appears:
```powershell
Show-Command: Object reference not set to an instance of an object.
```
>The interface then never changes to the second stage where you can refine your actual command parameters. All examples and references have been done with the PS5 version in order to move forward.

## Microsoft.PowerShell.ConsoleGuiTools

Although I really like [the work being done by Shawn Lawrie](https://pwshspectreconsole.com/) as presented [here](https://www.youtube.com/watch?v=xEkjsXzKu-E&t=777s), it makes more sense to expand on the Microsoft.PowerShell.ConsoleGuiTools module. This module is needed to run Out-GridView.

There is 

https://blog.ironmansoftware.com/tui-powershell/

There is the option to use a designer. The information in this blog is a littlebit outdated; [the designer is in it's own module now](https://github.com/ironmansoftware/terminal-gui-designer).

I have played around with the designer quite a while ago when it was in its beta phase. I found it ok-isch but certainly not perfect. Even though the designer has its own module, the version is 0.0.1. Not much development has taken place since in its inception I guess? 

So, the 

https://gui-cs.github.io/Terminal.GuiV1Docs/


## Setting up the TUI

```powershell
Import-Module Microsoft.PowerShell.ConsoleGuiTools 
$module = (Get-Module Microsoft.PowerShell.ConsoleGuiTools -List).ModuleBase
Add-Type -Path (Join-path $module Terminal.Gui.dll)
[Terminal.Gui.Application]::Init()
$Window = [Terminal.Gui.Window]::new()
$Window.Title = "Commands"
[Terminal.Gui.Application]::Top.Add($Window)
[Terminal.Gui.Application]::Run()

# Button definitions
$BtnRun = [Terminal.Gui.Button]::new()
$BtnRun.Text = "Run" 
$Window.Add($BtnRun)

$BtnCopy = [Terminal.Gui.Button]::new()
$BtnCopy.Text = "Copy" 
$Window.Add($BtnCopy)

$BtnCancel = [Terminal.Gui.Button]::new()
$BtnCancel.Text = "Cancel" 
$Window.Add($BtnCancel)

# Frames
$Frame1 = [Terminal.Gui.FrameView]::new()
$Frame1.Width = [Terminal.Gui.Dim]::Fill()
$Frame1.Height = [Terminal.Gui.Dim]::Percent(20)
$Window.Add($Frame1)

$Frame2 = [Terminal.Gui.FrameView]::new()
$Frame2.Width = [Terminal.Gui.Dim]::Fill()
$Frame2.Height = [Terminal.Gui.Dim]::Fill()
$Frame2.Y = [Terminal.Gui.Pos]::B
$Window.Add($Frame2)
