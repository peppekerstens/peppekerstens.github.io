---
title: The list was a year old — Linux Command Wrapping Part 16
toc: true
---

I almost skipped this stage entirely.

Part 15 ended with Stage 6 in full swing — three C# binary modules, a D-Bus `*-Service` rewrite compiling clean, the multi-distro matrix green across all three native repos. The natural next post would have been about the `ServiceUnix.cs` blocker or the RFC conversation that needs to start before upstreaming anything.

But somewhere between finishing Part 15 and starting this one, I re-read the project plan. The original Stage 5 was not the C# work. Stage 5 was something else entirely: a cmdlet list refresh. Verify that the gap list from the 2025 European PowerShell Summit is still accurate before continuing.

I had never actually done that. I just assumed the list was still authoritative and kept building.

So I stopped. Went back. Ran the comparison. And found something I did not expect.

## The gap list

Evgenij Smirnov's [missing cmdlet list](https://github.com/psconfeu/2025/blob/main/Evgenij%20Smirnov/Linux/00-inthebox/MissingCmdletsGroupedSorted.ps1) is the foundation of this project. Two hundred and nine cmdlets that PowerShell ships on Windows but not on Linux. Some implementable (`Get-Disk` via `lsblk`), some Windows-specific forever (`Get-PnpDevice`), some in between.

The list was compiled for the 2025 summit. It is now May 2026. PowerShell has had multiple preview releases since then. Things could have changed.

My assumption was: the list is probably still accurate, but let me verify.

## The comparison script

I wrote `Export-PowerShellCmdlets.ps1` for exactly this. It downloads a fresh Ubuntu cloud image, installs the latest PowerShell preview (7.7.0-preview.1) in a dedicated WSL instance, exports cmdlet CSVs from both Windows and WSL, and generates a Markdown report scoped to shared modules.

I ran it. Here is what came out:

| Metric | Count |
|--------|-------|
| Cmdlets in WSL | 257 |
| Cmdlets in Windows (filtered) | 322 |
| Windows-only (not in WSL) | 66 |
| WSL-only (not in Windows) | 1 (`Switch-Process`) |

Then I cross-referenced every single one of the 209 cmdlets in Evgenij's list against the 257 native WSL cmdlets.

The result: **zero overlap.** Not one cmdlet from Evgenij's list has been added natively to PowerShell on Linux in the past year.

`Get-Service`? Still not native. `Out-GridView`? Nope. `Get-Acl`? Not there. `Resolve-DnsName`? Still absent. Every single one of the 209 cmdlets is exactly where it was a year ago.

That means all 14 modules from Stages 1 and 3 are still filling genuine gaps. The foundation is solid.

## The finding I missed

But that is not the whole story.

While I was comparing Evgenij's list against the WSL CSV, I noticed something: `Restart-Computer` and `Stop-Computer` were present in both the WSL CSV and in our `PowerShell.Management.Linux` module. They were never in Evgenij's missing list. They have been cross-platform cmdlets since before this project started. And our module has been overriding them the entire time.

Five minutes with the script confirmed it:

```
Restart-Computer  Microsoft.PowerShell.Management   ← native on Linux
Stop-Computer     Microsoft.PowerShell.Management   ← native on Linux
```

These need to come out. A third-party module should not override working native cmdlets — it creates confusion, adds a dependency, and makes debugging harder. If someone imports `PowerShell.Management.Linux` and suddenly `Restart-Computer` behaves differently, that is a bug, not a feature.

I also noticed that `PackageManagement.Linux` (Stage 3) overlaps with the built-in `PackageManagement` module on all 5 cmdlets: `Find-Package`, `Get-Package`, `Get-PackageSource`, `Install-Package`, `Uninstall-Package`. These were also never in Evgenij's list. Whether the native `PackageManagement` actually works with `apt` on Linux is a separate question I have not investigated yet.

## What changed

Two removals coming to `PowerShell.Management.Linux`:

- Delete `Restart-Computer.ps1`
- Delete `Stop-Computer.ps1`
- Remove from `.psm1` `FunctionsToExport`
- Update tests, README, bump minor version

Everything else stays. The other 12 modules had zero overlap with the native surface.

## The low

The blog post I was going to write — "nothing changed, we are good" — was partially right but partially incomplete. Evgenij's list is fine. But our own modules had a blind spot: we implemented cmdlets we should not have.

`Restart-Computer` and `Stop-Computer` ended up in `PowerShell.Management.Linux` because I was working from the Windows module surface, not from the gap list. The module was modelled after `Microsoft.PowerShell.Management` as a whole, and those cmdlets are part of that module. The assumption was: if it is in the Windows module and not obviously working on Linux, it needs a wrapper. But `Restart-Computer` and `Stop-Computer` do work on Linux. They have `ComputerUnix.cs` in the PowerShell source tree. They are partial (remote computer support is marked TODO), but they exist and function.

I should have checked this earlier. A quick `Get-Command Restart-Computer` in WSL2 would have told me everything I needed to know.

## What is next

Back to Stage 6. The `*-Service` D-Bus rewrite is the next deliverable. The `ServiceUnix.cs` compiles clean against `Tmds.DBus.Protocol 0.93.0` with 0 errors. The blocker is building it against the right .NET target framework for local testing, or skipping local validation and going straight to a PR.

But before that: `Restart-Computer` and `Stop-Computer` come out of `PowerShell.Management.Linux` first. That cleanup is the last remaining deliverable for Stage 5.

The comparison script stays at the repo root. I can re-run it against any future PowerShell release and know immediately whether the gap has changed:

```
.\Export-PowerShellCmdlets.ps1
```

Stage 5 delivered less than I hoped but more than I expected. Evgenij's list is validated. Two cmdlets that should not have been there are identified for removal. And the script works.
