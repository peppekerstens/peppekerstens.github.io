---
date: 2026-05-15
title: Testing the native layer - Linux Command Wrapping Part 19
toc: true
---

A `dotnet build` compiles the code. It produces a DLL. But when you try
to `Import-Module` that DLL into PowerShell, you get an error about a
missing assembly. That is because binary modules use NuGet packages —
`Tmds.DBus.Protocol` for D-Bus, or `System.Management.Automation` itself.

`dotnet build` copies the project output. It does not copy transitive
NuGet dependencies for library projects. `dotnet publish` does.

That distinction took me an afternoon to figure out the first time. This
post covers both ways to test the native modules: the fast way (WSL,
one command) and the thorough way (Docker, all five distros).

## Before you start

You need three things on your machine:

- **WSL 2 (Windows Subsystem for Linux)** — `wsl --install` in an admin
  PowerShell prompt enables it. Restart when prompted, then set up a
  username and password in the Ubuntu window that opens.
- **.NET 8 SDK** — install the Windows version from the official site,
  and inside WSL: `sudo apt update && sudo apt install -y dotnet-sdk-8.0`.
- **PowerShell 7.4+ inside WSL** — inside your WSL terminal:

{% raw %}```powershell
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update && sudo apt install -y powershell
```{% endraw %}

After these three steps, `pwsh` launches PowerShell inside WSL. Test it
by running `pwsh -c '1+1'`.

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

The docker-compose file defines five distros. Swap `ubuntu-24` for
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
the runtime configuration. Without `--output`, `dotnet build` produces a
bare DLL that PowerShell cannot resolve.

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

## What is next

All nine cmdlets are ported to the fork's `ServiceUnix.cs`. The D-Bus
refactor — name resolution before connection — is applied in both the
standalone module and the fork. The remaining work is Pester tests for
the new `New-Service` and `Remove-Service` cmdlets in the fork, a
rebase on the latest upstream master, and the upstream PR to
`PowerShell/PowerShell`.
