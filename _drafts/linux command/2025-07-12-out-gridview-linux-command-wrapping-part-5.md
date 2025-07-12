---
title: Out-Gridview - Linux Command Wrapping Part 4
toc: true
---

This is a follow up article in a series on command wrapping. This time, i'll try to get my first cmdlet to a more or less final state.

## Out-Gridview

In [an earlier post](https://peppekerstens.github.io/proxy-functions-linux-command-wrapping-part-3/), I checked my existing [proxy function](https://gist.github.com/peppekerstens/b6553910fa316cfe9bdab2d73a3476a5) for Out-Gridview.

As that point, two issues surfaced:

1. The [Microsoft.PowerShell.Commands.OutputModeOption] error
2. The .out-gridview.settings error, see below

```powershell
#.out-gridview.settings error
Get-Content: C:\Users\peppe\OneDrive\GitHub\Storage.Linux\Helpers\Out-Gridview.ps1:67
Line |
  67 |  … stomObject](Get-Content -Path "$($env:USERPROFILE)\.out-gridview.sett …"
     |                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Cannot find path 'C:\Users\peppe\.out-gridview.settings' because it does not exist.
```

Both should be relative easy to fix.