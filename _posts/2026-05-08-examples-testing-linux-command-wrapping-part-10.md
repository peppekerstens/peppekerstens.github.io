---
title: Examples, Testing Across Platforms, and Linux-Only Modules - Linux Command Wrapping Part 10
toc: true
---

Parts 8 and 9 covered the initial implementation of `Storage.Linux` and `PowerShell.Management.Linux`. This part steps back from adding new cmdlets and focuses on three things that came out of revisiting `Storage.Linux`: building a reusable example script pattern, dealing with Pester version differences between Windows and WSL2, and a design decision about whether a Linux wrapping module should even load on Windows.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## The example scripts requirement

After shipping the core implementations, a natural question arose: do these cmdlets actually behave the way a real script would expect? Unit tests verify properties and types, but they do not verify that the data makes sense end-to-end.

The answer was to add an `Examples\` folder to each module. The rules:

1. **Research first** — look at Microsoft Docs, community blogs, Stack Overflow, and GitHub for the most common real-world patterns that use the cmdlets.
2. **Write scripts that work on Windows first** — using the real built-in module as the reference implementation.
3. **Test on Linux** — run the same scripts against the Linux module in WSL2 and compare the output.
4. **Pester tests** — create `Examples\Examples.Tests.ps1` that validates key assertions about the output. Tests that require Linux are guarded with `-Skip:(-not $IsLinux)`.

For `Storage.Linux`, the research turned up five recurring patterns:

- **Disk inventory** — `Get-Disk` with formatted GB sizes
- **Low-space volume detection** — `Get-Volume | Where-Object { ($_.SizeRemaining / $_.Size) -lt 0.15 }`
- **Disk-to-partition layout** — `Get-Disk | ForEach-Object { Get-Partition -DiskNumber $_.Number }`
- **SSD/HDD filter** — `Get-PhysicalDisk -MediaType SSD`
- **Storage summary report** — combined totals from `Get-Disk`, `Get-PhysicalDisk`, and `Get-Volume`

One subtlety in the low-space example: `Get-Volume` on Linux can return volumes with `Size = 0` (pseudo-filesystems like `tmpfs` or `devtmpfs`). A division-by-zero guard is needed:

```powershell
Get-Volume |
    Where-Object { $_.Size -gt 0 } |
    Where-Object { ($_.SizeRemaining / $_.Size) -lt $ThresholdPercent / 100 }
```

This is a case where the Windows implementation would never produce a zero-size volume, but the Linux implementation can. The example script documents this Linux-specific guard with a comment.

## Pester across platforms: 5.3.3 vs 5.7.1

Before writing `Examples.Tests.ps1`, it was worth checking whether the test tooling itself was consistent across environments.

| Environment | Pester version |
|---|---|
| Windows (development) | 5.3.3 |
| WSL2 Ubuntu 24.04 | 5.7.1 |

Both are Pester 5 — the major version matches and the test syntax is compatible. But there is a subtle difference in how `$PSScriptRoot` behaves during the discovery phase.

### The problem: $PSScriptRoot is $null at discovery time in Pester 5.3.x

Pester 5 splits test execution into two phases: **discovery** (find all `Describe`, `It`, and `-ForEach` blocks) and **runtime** (execute the tests). Data used in `-ForEach` on a `Describe` block must be available at discovery time — not at runtime.

In Pester 5.7.x, `$PSScriptRoot` is available during discovery. In Pester 5.3.x, when the test file is passed via `PesterConfiguration` (rather than directly as a path argument), `$PSScriptRoot` is `$null` during discovery. Setting it at bare script scope or in `BeforeAll` is too late.

The first version of `Examples.Tests.ps1` set the examples directory at script scope:

```powershell
$script:ExamplesDir = $PSScriptRoot  # $null in Pester 5.3.x at discovery time
```

The result: all 31 tests failed immediately with `Cannot bind argument to parameter 'Path' because it is null`.

### The fix: BeforeDiscovery

`BeforeDiscovery` was introduced in Pester 5.2 specifically for this purpose. It runs before discovery begins and is the correct place to set variables that feed `-ForEach` data:

```powershell
BeforeDiscovery {
    $script:ExamplesDir = if ($PSScriptRoot) {
        $PSScriptRoot
    } else {
        Split-Path $PSCommandPath -Parent
    }
    $script:ExampleFiles = @(
        'Get-DiskInventory.ps1'
        'Get-LowSpaceVolumes.ps1'
        'Get-DiskLayout.ps1'
        'Get-SsdHddFilter.ps1'
        'Get-StorageSummary.ps1'
    )
}
```

The fallback to `$PSCommandPath` handles the 5.3.x case where `$PSScriptRoot` is `$null`. After this fix: 15 tests passed on Windows (file existence and syntax checks), 16 correctly skipped (Linux-only execution tests).

### Minimum version requirement in test files

Both `Storage.Linux.Tests.ps1` and `Examples.Tests.ps1` now declare a minimum Pester version:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
```

This makes the dependency on `BeforeDiscovery` explicit. Pester 5.2 is the earliest version that supports it. Running with an older version will now produce a clear error rather than a confusing discovery failure.

## Should a Linux module load on Windows?

Up to `Storage.Linux` v0.4.0, every implemented cmdlet had two branches:

```powershell
function Get-Disk {
    if (-not $IsLinux) {
        Storage\Get-Disk @PSBoundParameters  # delegate to Windows
        return
    }
    # ... lsblk parsing ...
}
```

The intention was that `Storage.Linux` could be safely imported on Windows and would silently pass through to the real cmdlet. In practice this is not useful:

- Anyone on Windows already has the `Storage` module — they do not need a wrapper.
- The Windows code paths in the Linux module are never tested (the test suite runs on Linux).
- The dual-path code obscures the module's purpose and adds maintenance weight.
- A developer who accidentally imports `Storage.Linux` on Windows gets subtly wrong behavior if the output shapes differ even slightly.

The better design is to make the module **Linux-only** and fail loudly on Windows. From v0.5.0:

```powershell
#Requires -Version 7.2

if (-not $IsLinux) {
    throw (
        "Storage.Linux cannot be loaded on Windows. " +
        "On Windows, use the built-in 'Storage' module: Import-Module Storage`n" +
        "Storage.Linux is a Linux-only peer module that wraps lsblk and df."
    )
}
```

The error message tells the user exactly what to do instead. The check is at the top of `Storage.Linux.psm1`, before any functions are dot-sourced, so it runs the moment `Import-Module Storage.Linux` is called on a Windows machine.

## Impact on the test suite

Making the module Linux-only meant the test files needed updating.

`Storage.Linux.Tests.ps1` previously ran the module surface and alias tests on both platforms (the module could be loaded on Windows). With the new guard, `Import-Module Storage.Linux` throws on Windows. The fixes:

```powershell
BeforeDiscovery {
    $script:OnLinux = $IsLinux
}

BeforeAll {
    if ($IsLinux) {
        Import-Module (Join-Path $PSScriptRoot 'Storage.Linux.psd1') -Force
    }
}

Describe 'Module surface' -Skip:(-not $script:OnLinux) { ... }
Describe 'Aliases'        -Skip:(-not $script:OnLinux) { ... }
Describe 'Stub functions' -Skip:(-not $script:OnLinux) { ... }
```

On Windows: 503 tests, all skipped, 0 failed.  
On Linux: 503 tests, all run and pass.

`Examples.Tests.ps1` had `#Requires -Modules Pester, Storage.Linux`. The `Storage.Linux` entry in `#Requires` causes PowerShell to attempt to import the module before the script begins — which now throws on Windows. Removing it and guarding the import in `BeforeAll` preserves the useful cross-platform tests (file existence, syntax parse) while keeping the Linux execution tests safely skipped:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    if ($IsLinux) {
        $modulePath = Join-Path (Split-Path $script:ExamplesDir -Parent) 'Storage.Linux' 'Storage.Linux.psd1'
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -ErrorAction Stop
        }
    }
}
```

## Lessons for the other modules

The patterns established here apply to all future modules in this series:

- **Examples first** — research common patterns, write scripts that work on Windows, then test on Linux.
- **`BeforeDiscovery` for all cross-platform test files** — never set `-ForEach` data at bare script scope or in `BeforeAll`.
- **Declare `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }`** in every test file.
- **Linux-only guard in `.psm1`** — if the module wraps Linux CLI tools, it should refuse to load on Windows with a clear error and a pointer to the Windows alternative.
- **Remove `Storage.Linux` (or any Linux peer module) from `#Requires`** in test files that also run on Windows. Guard the import with `if ($IsLinux)` in `BeforeAll` instead.

## Next up

With `Storage.Linux` polished and documented, the queue has `NetTCPIP.Linux` waiting for its first WSL2 test run, and `PowerShell.Management.Linux`, `NetTCPIP.Linux`, and `PowerShell.Utility.Linux` all still need their `Examples\` folders. The approach is now standardised — part 11 will put it into practice.
