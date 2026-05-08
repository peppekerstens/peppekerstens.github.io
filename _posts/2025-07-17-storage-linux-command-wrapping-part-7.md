---
title: Storage - Linux Command Wrapping Part 7
toc: true
---

After covering the utility cmdlets in parts 5 and 6, it was time to tackle something that felt more fundamental: storage. If you run `Get-Disk` on Linux you get nothing. Not an error — just nothing. The cmdlet does not exist. `Get-Volume`, `Get-Partition`, `Get-PhysicalDisk` — same story. The Windows `Storage` module is huge (161 cmdlets, 10 aliases) and relies entirely on Windows-specific WMI/CIM providers. None of it ports.

This part documents the `Storage.Linux` module: what we built, how, and the bugs that bit us along the way.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## The Storage module gap

On Windows, the `Storage` module gives you a rich object model for disk, partition and volume management. On Linux, PowerShell 7 does not ship any equivalent. You can reach for `fdisk`, `lsblk`, `df`, `blkid` — but those are raw text tools, not PowerShell cmdlets. Any script that calls `Get-Disk | Get-Partition | Get-Volume` simply fails.

The goal of `Storage.Linux` is to provide a drop-in that makes those cmdlets work on Linux, returning `PSCustomObject` output with the same property shape as their Windows counterparts.

## Starting with lsblk and Crescendo

The natural Linux tool for disk enumeration is `lsblk`. It can produce JSON output with `--json`, which makes parsing in PowerShell straightforward.

```bash
lsblk --json --output NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID,MODEL,SERIAL,ROTA,RM,PHY-SEC,LOG-SEC
```

Part 4 of this series introduced Crescendo as a way to wrap native CLI tools. For `lsblk`, it's a good fit: the output is structured JSON, the parameter mapping is straightforward, and Crescendo generates a `Get-LsBlk` function that we can call internally.

The Crescendo module lives under `Storage.Linux/Crescendo/lsblk.psm1` and is imported as a **nested module** inside `Storage.Linux.psm1`. The key thing here is that `Get-LsBlk` should be an internal helper — it must not appear in `FunctionsToExport` in the `.psd1`. Because the Crescendo module is imported with `Import-Module` inside the `.psm1`, PowerShell creates a nested module. The parent module's `.psd1` `FunctionsToExport` list acts as a filter, so as long as `Get-LsBlk` is not in that list, it stays hidden from consumers. This is the correct way to keep internal Crescendo wrappers private.

## The first real gotcha: lsblk SIZE without --bytes

The first implementation of `Get-Disk` was working — until I noticed something odd. The `Size` property was coming back as a string like `"388.6M"` instead of a number.

The problem: `lsblk` without `--bytes` returns SIZE as a human-readable string. With `--bytes`, it returns a numeric integer. Always use `--bytes`.

```powershell
# Wrong — Size is "388.6M"
lsblk --json --output NAME,SIZE,...

# Right — Size is 407896064
lsblk --json --output NAME,SIZE,... --bytes
```

After adding `--bytes`, `Size` is cast to `[uint64]` and everything lines up with the Windows property type.

## The four implemented cmdlets

### Get-Disk

Maps `lsblk` disk-type entries to the Windows `MSFT_Disk` property shape: `Number`, `FriendlyName`, `SerialNumber`, `Size`, `BusType`, `PartitionStyle`, `IsReadOnly`, `OperationalStatus`. Supports `-Number`, `-FriendlyName`, `-SerialNumber` filters.

```powershell
Get-Disk
```

```
Number FriendlyName     SerialNumber PartitionStyle Size
------ ------------     ------------ -------------- ----
0      Samsung SSD 870  S59JNJ0W...  GPT            500107862016
```

### Get-PhysicalDisk

Similar to `Get-Disk` but exposes the `rota` flag from `lsblk` to distinguish HDD from SSD:

```powershell
if ($d.rota -eq 1) { 'HDD' } else { 'SSD' }
```

### Get-Partition

Reads the `children` array from `lsblk --json` output — each child of a disk entry is a partition. Returns `DiskNumber`, `PartitionNumber`, `FileSystem`, `MountPoint`, `UniqueId`, `Path`.

### Get-Volume

Combines two sources: `lsblk --json --bytes` for filesystem type and UUID, and `df --block-size=1` for size, used and free byte counts. The two are joined on mountpoint.

The second gotcha appeared here.

## The second gotcha: [SWAP] in lsblk output

`lsblk` lists swap devices in its output. The MOUNTPOINT field for a swap device is `[SWAP]` — not a real filesystem path. The first version of `Get-Volume` was happily returning swap partitions as volumes.

Fix: filter entries with `-notmatch '^/'`. Real filesystem mountpoints start with `/`. `[SWAP]` does not.

```powershell
$d.mountpoint -match '^/'
```

A third quirk specific to WSL2: in Ubuntu 24.04, the root distro filesystem is mounted at `/mnt/wslg/distro`, not `/`. Pester tests that assumed `/` would always be a volume mountpoint needed to be updated.

## 157 stubs for the rest

The Windows Storage module has 161 cmdlets. We implemented 4. What about the other 157?

The strategy from the beginning of this series is to export the same API surface as the Windows module, even for cmdlets we have not implemented yet. Stubs emit a `Write-Warning` on Linux to tell the caller the cmdlet is not yet implemented. On Windows they delegate to the real cmdlet using the module-qualified name (`Storage\<CmdletName>`).

```powershell
function Get-StorageJob {
    [CmdletBinding()]
    param()
    if ($IsLinux) {
        Write-Warning "Get-StorageJob is not implemented in Storage.Linux."
    } else {
        Storage\Get-StorageJob @PSBoundParameters
    }
}
```

A helper script (`Helpers/Set-StubFunctions.ps1`) generates these stubs automatically from the list of Windows cmdlet names. One important lesson: always use a plain `param()` for stubs. Do not try to extract the Windows cmdlet's param block by regex — the Windows proxy functions have deeply nested, multi-line param blocks that are very easy to truncate. `@PSBoundParameters` splatting on Windows works fine even without typed params.

## Module structure and a psm1 gotcha

The `.psm1` dot-sources all function files:

```powershell
Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter '*.ps1' |
    Where-Object { $_.Name -notlike '*.Tests.ps1' } |
    ForEach-Object { . $_.FullName }
```

Note the `Where-Object` instead of `-Exclude`. On the Windows FileSystem provider, combining `-Filter '*.ps1'` with `-Exclude '*.Tests.ps1'` silently returns **nothing**. This one took a while to find. Always use `Where-Object` for post-filter exclusion in `.psm1` root modules.

## 503 Pester tests

The test file covers:

- Module surface: exported function count is exactly 161, alias count is exactly 10, `Get-LsBlk` is not exported
- All 10 alias→target mappings
- Property shape and filter tests for the 4 implemented cmdlets
- Per-stub: exported check, no-throw check, emits-warning check — for all 157 stubs

That comes to 503 tests, all passing on WSL2 Ubuntu 24.04.2 with PowerShell 7.5.

## Next up

With `Storage.Linux` in a solid state, the next module is `PowerShell.Management.Linux`: service management, computer info and related cmdlets. That story is in part 8.

---

## Updates since initial publication

### v0.4.0 — Example scripts

Following a new requirement across the whole project, `Storage.Linux` gained an `Examples\` folder with five ready-to-run scripts covering the most common real-world patterns:

| Script | Pattern |
|---|---|
| `Get-DiskInventory.ps1` | List all disks with sizes formatted in GB |
| `Get-LowSpaceVolumes.ps1` | Find volumes below a configurable free-space threshold |
| `Get-DiskLayout.ps1` | Hierarchical disk → partition report |
| `Get-SsdHddFilter.ps1` | Physical disks grouped or filtered by media type |
| `Get-StorageSummary.ps1` | Combined capacity and usage report across all cmdlets |

Each script works identically on Windows and Linux. An `Examples.Tests.ps1` Pester test file accompanies them — 31 tests total. File-existence and syntax checks run on Windows; live execution tests run on Linux only (guarded with `-Skip:(-not $IsLinux)`).

Writing cross-platform Pester tests revealed a platform version mismatch: Windows had Pester **5.3.3** and WSL2 had Pester **5.7.1**. Both are v5, but `$PSScriptRoot` behaves differently at discovery time in 5.3.x — it can be `$null` when the test file is passed via `PesterConfiguration`. The fix is `BeforeDiscovery`, introduced in Pester 5.2, which runs before test discovery and is the correct place to set data that feeds `-ForEach` on `Describe` blocks. More on this in part 9.

### v0.5.0 — Linux-only module guard

Up to v0.4.0, every implemented cmdlet contained an `if (-not $IsLinux)` branch that delegated to the real Windows cmdlet using the module-qualified name (`Storage\Get-Disk`). The intent was that the module could be imported on Windows and would silently pass through to the built-in.

On reflection, this design is unnecessary and potentially confusing. There is no reason to load a Linux wrapping module on Windows — the built-in `Storage` module is already there and is far more complete. The dual-path code adds dead weight and obscures the module's purpose.

From v0.5.0, the module refuses to load on Windows with a clear error:

```
Storage.Linux cannot be loaded on Windows. On Windows, use the built-in
'Storage' module: Import-Module Storage
Storage.Linux is a Linux-only peer module that wraps lsblk and df.
```

This is implemented as a single check at the top of `Storage.Linux.psm1`, before any functions are dot-sourced:

```powershell
if (-not $IsLinux) {
    throw (
        "Storage.Linux cannot be loaded on Windows. " +
        "On Windows, use the built-in 'Storage' module: Import-Module Storage`n" +
        "Storage.Linux is a Linux-only peer module that wraps lsblk and df."
    )
}
```

The test files were updated accordingly: `Storage.Linux.Tests.ps1` now uses `BeforeDiscovery` to detect the platform and skips all 503 tests on Windows (rather than attempting to import a module that will throw). `Examples.Tests.ps1` drops `Storage.Linux` from its `#Requires` statement and guards the import with `if ($IsLinux)` so the file/syntax checks still run on Windows. Both files now declare a minimum Pester version of 5.2.0 via `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }`.
