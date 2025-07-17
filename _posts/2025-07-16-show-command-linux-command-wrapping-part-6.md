---
title: Show Command - Linux Command Wrapping Part 6
toc: true
---

After Out-Gridview, the Show-Command seemed a logical next candidate. This provided me the oppertunity to tip-toe into Terminal User Interface (TUI) design.

This turned out to be **a lot** harder then I anticipated! So a full replacement of the Show-Command will most likely become multi-article posts. This one limits itself to scaffolding and a pseudo interface.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY)

## The added value of Show-Command

Personally I do not use the Show-Command feature. Nor the integrated version of it in the classic PowerShell ISE. Especially in the terminal/command-line realm, the Get-Help function makes more sense to me.

If anything, it would make more sense to create a simple TUI replacement for the PowerShell ISE. In that case, there might be added value for cmdlet information. Still, on the Linux platform, there already are several fine command-line editors like Vim or Nano.

And Microsoft seems to have resurrected [Microsoft Edit, programmed in Rust](https://github.com/microsoft/edit). The easy install under Windows 11 is;

```cmd
winget install Microsoft.Edit
```

It is simple and intuitive. Would do exactly what I imagined my initial terminal version of PowerShell ISE would have done.

Or [check out YouTube on Microsoft Edit](https://www.youtube.com/results?search_query=microsoft+edit)

I embarked on this journey mainly because I wanted to get the [PowerShell.Utility.Linux](https://github.com/peppekerstens/PowerShell.Utility.Linux) completed and secondly I wanted to learn a bit about TUI programming.

## Show-Command

The Show-Command cmdlet presents a GUI in which you can search for PowerShell cmdlets. The GUI presents you the option to filter based on module but also search based on a partial name. Lastly, a ordered list of every cmdlet, complying with those search or filter parameters, is being shown.

Whenever a cmdlet is chosen, the GUI changes its interface to help you out with refining the actual command

A longer explanation is documented here: https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/show-command

>At time of this writing, on my machine the Show-Command cmdlet within PowerShell 7 seems to contain a bug. When I choose a command in the GUI, the following error appears:

```powershell
Show-Command: Object reference not set to an instance of an object.
```

>The interface then never changes to the second stage where you can refine your actual command parameters. All examples and references have been done with the PS5 version in order to move forward.

The next sections try to get the actual functionality working.

### List the commands

This is the first stage of Show-Command; a list of all commands it can find. This one is simple:

```powershell
$commands = Get-Command
$commands | Select-Object -Property Name
```

### The modules selector

On the top of the User Interface, there is a ListView called 'Modules', which shows the modules where commands are from.

```powershell
#all
$commands.Source | Select-Object -Unique

#single
$commands | Where-Object -Property Source -eq $selectedModule | Select-Object -Unique
```

### The name filter

The second line on the interface, called 'Name', seems to be a text field in which you can enter a partial command name. This will filter the shown commands in the commands ListView below.

```powershell
#all
$commands.Source | Select -unique

#single
$filteredCommand = $commands | Where-Object {$_.Name -like $partialName}
$filteredCommand | Select-Object -Property Name
```

### Get the parameter sets

When a command is selected, the Show-Command User Interface changes. It displays the parameters details per parameters set. Secondly it displays the option to set common parameters. Let's start with detecting the parameter sets

Is stumbled upon [a blog from Patrick Gruenauer which interrogates Get-Command results](https://sid-500.com/2017/07/25/powershell-cmdlets-list-all-availabe-parameters-without-using-the-help/).

I am using Get-Content as an example below because it has (only) two Parameter Sets.

```powershell
$commands.where{$_.name -eq 'Get-Content'}|fl

Name             : Get-Content
CommandType      : Cmdlet
Definition       :
                   Get-Content [-Path] <string[]> [-ReadCount <long>] [-TotalCount <long>] [-Tail <int>] [-Filter <string>]
                   [-Include <string[]>] [-Exclude <string[]>] [-Force] [-Credential <pscredential>] [-UseTransaction] [-Delimiter
                   <string>] [-Wait] [-Raw] [-Encoding <FileSystemCmdletProviderEncoding>] [-Stream <string>] [<CommonParameters>]

                   Get-Content -LiteralPath <string[]> [-ReadCount <long>] [-TotalCount <long>] [-Tail <int>] [-Filter <string>]
                   [-Include <string[]>] [-Exclude <string[]>] [-Force] [-Credential <pscredential>] [-UseTransaction] [-Delimiter
                   <string>] [-Wait] [-Raw] [-Encoding <FileSystemCmdletProviderEncoding>] [-Stream <string>] [<CommonParameters>]

Path             :
AssemblyInfo     :
DLL              : C:\WINDOWS\Microsoft.Net\assembly\GAC_MSIL\Microsoft.PowerShell.Commands.Management\v4.0_3.0.0.0__31bf3856ad364e3
                   5\Microsoft.PowerShell.Commands.Management.dll
HelpFile         : Microsoft.PowerShell.Commands.Management.dll-Help.xml
ParameterSets    : {[-Path] <string[]> [-ReadCount <long>] [-TotalCount <long>] [-Tail <int>] [-Filter <string>] [-Include
                   <string[]>] [-Exclude <string[]>] [-Force] [-Credential <pscredential>] [-UseTransaction] [-Delimiter <string>]
                   [-Wait] [-Raw] [-Encoding <FileSystemCmdletProviderEncoding>] [-Stream <string>] [<CommonParameters>],
                   -LiteralPath <string[]> [-ReadCount <long>] [-TotalCount <long>] [-Tail <int>] [-Filter <string>] [-Include
                   <string[]>] [-Exclude <string[]>] [-Force] [-Credential <pscredential>] [-UseTransaction] [-Delimiter <string>]
                   [-Wait] [-Raw] [-Encoding <FileSystemCmdletProviderEncoding>] [-Stream <string>] [<CommonParameters>]}
ImplementingType : Microsoft.PowerShell.Commands.GetContentCommand
Verb             : Get
Noun             : Content

$parameterSets = $commands.where{$_.name -eq 'Get-Content'}.ParameterSets
$parameterSets.Name
Path
LiteralPath
```

Further disquised is another pointer to which parameter set a parameter belongs to:

```powershell
$parameterSets[0].Parameters.Attributes.ParameterSetName
__AllParameterSets
__AllParameterSets
__AllParameterSets
Path
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
__AllParameterSets
```

### Get the parameters from a parameter set

Once the parameter set is filtered, it becomes easy which parameters belong to that set:

```powershell
$parameterSets[0].Parameters.Name
ReadCount
TotalCount
Tail
Path
Filter
Include
Exclude
Force
Credential
Verbose
Debug
ErrorAction
WarningAction
InformationAction
ErrorVariable
WarningVariable
InformationVariable
OutVariable
OutBuffer
PipelineVariable
UseTransaction
Delimiter
Wait
Raw
Encoding
Stream
```

### Get the common parameters

I have found no clear .NET object or enumerator which lists [the PowerShell common parameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters). So the easiest way is to create our own:

```powershell
enum commonParameters{
    Debug
    ErrorAction
    ErrorVariable
    InformationAction    
    InformationVariable
    OutVariable
    OutBuffer
    PipelineVariable
    ProgressAction
    Verbose
    WarningAction
    WarningVariable
}
```

The above will also help isolating the actual parameters for a given cmdlet, like so:

```powershell
$parameterSets[0].Parameters.where{$_.Name -notin [commonParameters].GetEnumNames()}.Name
ReadCount
TotalCount
Tail
Path
Filter
Include
Exclude
Force
Credential
UseTransaction
Delimiter
Wait
Raw
Encoding
Stream
```

### Get more parameter properties

In order to populate the different tabs which represent the parameter sets with actual parameter fields, we need to know what type of parameter we are dealing with.

```powershell
$parameterSets[0].Parameters[0].ParameterType

IsPublic IsSerial Name                                     BaseType
-------- -------- ----                                     --------
True     True     Int64                                    System.ValueType
```

## Simple user interface

Below code is a very simple and basic. It should be viewed as a concept or flow scaffolding. At end, it is not a complete or working solution; it does not provide the option to enter values for parameters.

```powershell
Import-Module Microsoft.PowerShell.ConsoleGuiTools

# Get available commands
$commands = Get-Command | Where-Object { $_.CommandType -eq 'Cmdlet' -or $_.CommandType -eq 'Function' }
$commandNames = $commands | Select-Object -ExpandProperty Name

# Select a command using Out-ConsoleGridView
$selectedCmd = $commandNames | Out-ConsoleGridView -Title 'Select a command to show parameters' -OutputMode Single
if (-not $selectedCmd) { return }

# Get parameter sets
$selectedCmd = Get-Command -Name $selectedCmd
$parameterSets = @()
$parameterSets += $selectedCmd.ParameterSets
if ($parameterSets.count -gt 1) {
    $selectedParameterSet = $parameterSets.Name | Out-ConsoleGridView -Title 'Select a Parameter Set' -OutputMode Single
    if (-not $selectedParameterSet) { return }
} else {
    $selectedParameterSet = $parameterSets[0].Name
}

# Strip the common parameters from the parameter set
enum commonParameters{
    Debug
    ErrorAction
    ErrorVariable
    InformationAction    
    InformationVariable
    OutVariable
    OutBuffer
    PipelineVariable
    ProgressAction
    Verbose
    WarningAction
    WarningVariable
}
$selectedParameterSet = $selectedCmd.ParameterSets | Where-Object { $_.Name -eq $selectedParameterSet }
$actualParameters = $selectedParameterSet.Parameters.Where{$_.Name -notin [commonParameters].GetEnumNames()}

# Get parameter info
$paramInfo = $actualParameters | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Type = $_.ParameterType.Name
        IsMandatory = $_.IsMandatory
        DefaultValue = $_.DefaultValue
    }
}

# Prepare input form for parameters
$formFields = $paramInfo | ForEach-Object {
    [PSCustomObject]@{
        Parameter = $_.Name
        Value = $_.DefaultValue
    }
}

# Show parameter input grid
$inputParams = $formFields | Out-ConsoleGridView -Title "Enter parameter values for $selectedCmd (edit Value column)" -OutputMode Multiple
if (-not $inputParams) { return }

# Build command line
$paramString = $inputParams | Where-Object { $_.Value -ne $null -and $_.Value -ne '' } | ForEach-Object {
    "-$_($._.Parameter) $_($._.Value)"
} | Join-String ' '

$finalCommand = "$selectedCmd $paramString"

# Show final command and offer to run
Write-Host "Command to run: $finalCommand" -ForegroundColor Cyan
$run = Read-Host 'Run this command? (y/n)'
if ($run -eq 'y') {
    Invoke-Expression $finalCommand
}
```

