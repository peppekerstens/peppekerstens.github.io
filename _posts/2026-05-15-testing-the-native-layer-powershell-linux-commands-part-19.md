---
date: 2026-05-15 10:00:00 -0000
title: testing the native layer — powershell linux commands part 19
toc: true
redirect_from:
  - /testing-the-native-layer-linux-command-wrapping-part-19/
---

Part 18 ended with 18 NuGet packages published to GitHub Packages. A
consumer can now install `Storage.Linux` or `NetTCPIP.Linux.Native`
with `Install-PSResource` and start using it. The distribution
pipeline works.

But this project does not end with distribution. The whole point of
Stage 6 was to write C# binary modules that could eventually land in
the PowerShell source tree. Four native modules exist now —
`LocalAccounts.Linux.Native`, `ScheduledTasks.Linux.Native`,
`NetTCPIP.Linux.Native`, and `Services.Linux.Native`. They pass
code review. They build green across five distros.

The question this post answers is: how do you test one of these
modules before the NuGet package exists, when you are still
iterating on code?

Script modules are easy to test — they are `.psm1` files.
`Import-Module ./Module.psm1` works anywhere. Binary modules need
a build step. And not just `dotnet build` — that produces a bare DLL
that PowerShell cannot resolve because the NuGet dependencies live
in NuGet caches, not next to the output.

This is the workflow I settled on after burning an afternoon on that
exact `dotnet build` vs `dotnet publish` distinction.

## Before you start

You need three things on your machine:

- **WSL 2** — `wsl --install` in an admin PowerShell prompt. Restart,
  set up a username and password.
- **.NET 8 SDK** — install the Windows version from the official site,
  and inside WSL: `sudo apt update && sudo apt install -y dotnet-sdk-8.0`.
- **PowerShell 7.4+ inside WSL**:

{% raw %}```powershell
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update && sudo apt install -y powershell
```{% endraw %}

After these three steps, `pwsh` launches PowerShell inside WSL.

## Workflow A: Interactive container (recommended)

Each module repo has a `docker-compose.test.yml` that spins up the same
container images used in CI. No dependency conflicts, no missing tools,
no "works on my machine."

```powershell
# From the module root (e.g., Services.Linux.Native)
docker compose -f docker-compose.test.yml run ubuntu-24 pwsh
```

Inside the container the module is mounted at `/module`. Build and load:

```powershell
dotnet build /module/src/Services.Linux.Native --configuration Release
Import-Module /module/bin/Release/net8.0/Services.Linux.Native.dll
Get-Service
```

The Compose file defines five distros. Swap `ubuntu-24` for
`debian-12`, `fedora-40`, `opensuse-tumbleweed`, or `arch`.

## Workflow B: Bare WSL (fastest for small edits)

Skip Docker if you already have .NET and pwsh inside WSL. Navigate to
the module folder and publish:

```powershell
# From Windows: cd C:\Users\you\OneDrive\GitHub\Services.Linux.Native
# From WSL: cd /mnt/c/Users/you/OneDrive/GitHub/Services.Linux.Native

dotnet publish src/Services.Linux.Native --configuration Release --output bin/Release/net8.0/publish
pwsh
Import-Module ./bin/Release/net8.0/publish/Services.Linux.Native.dll
Get-Service
```

`dotnet publish` copies everything — the DLL, the NuGet dependencies,
the runtime config. Without `--output`, `dotnet build` produces a bare
DLL that PowerShell cannot resolve.

If you run into `Tmds.DBus.Protocol` load errors, check that you used
`publish`, not `build`. That is the most common mistake.

## What to test

The Pester test file at `tests/Services.Linux.Native.Tests.ps1` covers:

| Describe block | What it verifies |
|---|---|
| Module surface | 9 cmdlets are exported |
| Output types | Returned objects have correct types |
| Get-Service | Enumerate, wildcard filter, exact match |
| Start/Stop/Restart -WhatIf | ShouldProcess does not require D-Bus |
| New/Remove -WhatIf | ShouldProcess works as non-root |
| Suspend/Resume stubs | PlatformNotSupported error |
| Module loads on Windows | Assembly imports without error on Windows CI |

Run it:

```powershell
Invoke-Pester -Path tests/Services.Linux.Native.Tests.ps1 -Output Detailed
```

The `-WhatIf` tests now pass without a D-Bus socket — the cmdlets
resolve unit names before touching the system bus. That was the last
design issue before the upstream contribution.

## Summary: what to skip

| Current setup | Skip setup? | Recommended workflow |
|---|---|---|
| Fresh Windows install | No | Setup, then Workflow A or B |
| Has WSL and .NET SDK | Partially | Workflow B |
| Has Docker Desktop | Yes | Workflow A |

## Where this fits

Parts 1 through 13 built the PowerShell script modules. Part 14 added
the 5-distro test matrix. Parts 15-17 delivered the C# native modules.
Part 18 published everything to a NuGet feed.

This part closes the loop for the contributor who clones one of the
native repos and wants to verify the build. The next part picks up
the upstream contribution story — rebasing the fork, signing the CLA,
filing the RFC, and submitting the PR to `PowerShell/PowerShell`.
