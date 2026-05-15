---
date: 2026-05-08 T -0000
title: Building twelve modules - Linux Command Wrapping Part 8
toc: true
---

This is the technical post. Twelve modules, all the patterns, all the gotchas. If you want the meta-story about AI-assisted development and why I am doing this at all, that is [part 7]({% post_url 2026-05-08-ai-assisted-linux-command-wrapping-part-7 %}). This post is about what we built and what we learned building it.

The modules, current as of this writing:

| Module | Version | Implemented | Stubs | GitHub |
|---|:---:|:---:|:---:|---|
| **Storage.Linux** | 0.5.0 | 4 | 157 | [repo][storage] |
| **PowerShell.Management.Linux** | 0.2.0 | 8 | 7 | [repo][mgmt] |
| **NetTCPIP.Linux** | 0.4.0 | 4 | 30 | [repo][nettcpip] |
| **DnsClient.Linux** | 0.1.0 | 4 | 17 | [repo][dnsclient] |
| **Update.Linux** | 0.2.0 | 3 | 19 | [repo][update] |
| **PowerShell.Security.Linux** | 0.1.0 | 2 | 4 | [repo][security] |
| **PowerShell.LocalAccounts.Linux** | 0.1.0 | 15 | 0 | [repo][localaccounts] |
| **ScheduledTasks.Linux** | 0.1.0 | 13 | 2 | [repo][scheduledtasks] |
| **PKI.Linux** | 0.3.1 | 8 | 9 | [repo][pki] |
| **PrintManagement.Linux** | 0.1.1 | 7 | 15 | [repo][printmgmt] |
| **PowerShell.Utility.Linux** | 0.4.0 | 4 | 0 | [repo][utility] |
| **NetAdapter.Linux** | 0.1.0 | 4 | 74 | [repo][netadapter] |

[storage]: https://github.com/peppekerstens/Storage.Linux/blob/d5706f15a7eb34d8bc8065c3e3e5f9586ea5d4da/README.md
[mgmt]: https://github.com/peppekerstens/PowerShell.Management.Linux/blob/a8401250885185e03f97422f44237ad2f2ba7cfe/README.md
[nettcpip]: https://github.com/peppekerstens/NetTCPIP.Linux/blob/bf01bdd4f81a10b5e33887dce972f703f3b1c0bd/README.md
[dnsclient]: https://github.com/peppekerstens/DnsClient.Linux/blob/240aa4baf866f7a71261cb1bd191fc37116e0058/README.md
[update]: https://github.com/peppekerstens/Update.Linux/blob/3e32935953f28c7ba04838c83618dced3a0bc947/README.md
[security]: https://github.com/peppekerstens/PowerShell.Security.Linux/blob/de11772fc00fe9f1dd35ed90a9f43d4e36419d10/README.md
[localaccounts]: https://github.com/peppekerstens/PowerShell.LocalAccounts.Linux/blob/bad3d99e1178009fc407528e6fe2bf76c4bcb181/README.md
[scheduledtasks]: https://github.com/peppekerstens/ScheduledTasks.Linux/blob/aeb6777fa24c15210fc5cbad24ae051d0a8261d3/README.md
[pki]: https://github.com/peppekerstens/PKI.Linux/blob/582b944/README.md
[printmgmt]: https://github.com/peppekerstens/PrintManagement.Linux/blob/56cf9a2/README.md
[utility]: https://github.com/peppekerstens/PowerShell.Utility.Linux/blob/ab80349958285ade7107873e8a64303fcf8fc5f9/README.md
[netadapter]: https://github.com/peppekerstens/NetAdapter.Linux/blob/5a12624/README.md

All repositories are public under [peppekerstens](https://github.com/peppekerstens). All modules have been tested on WSL2 Ubuntu 24.04. Each README has a detailed "How we built this" section if you want the full story on a specific module.

---

## Coverage

Before getting into the per-module detail: a brief note on scope. The baseline for this project is [Evgenij Smirnov's gap analysis](https://github.com/psconfeu/2025/blob/main/Evgenij%20Smirnov/Linux/00-inthebox/MissingCmdletsGroupedSorted.ps1) from the 2025 European PowerShell Summit — a list of cmdlets that exist in Windows PowerShell but are missing from PS7.5 on Linux. The list has 209 cmdlets across seven regions.

91 of those are genuinely Windows-specific with no useful Linux equivalent: the Windows VPN stack, IPsec policy management, Teredo, the Windows Defender Firewall model, the Windows NDIS hardware offload driver API. Stripping those leaves 118 cmdlets worth pursuing.

Current status across the 118 in-scope cmdlets:

| Status | Count | % |
|---|:---:|:---:|
| ✅ Implemented | 63 | 53 % |
| 🔶 Stubbed (warns on call) | 51 | 43 % |
| ❌ Not covered | 4 | 3 % |

The 4 uncovered cmdlets are all NFS/SMB client cmdlets (`Get-NfsSession`, `Get-NfsClientConfiguration`, `Disconnect-NfsSession`, `Block-SmbClientAccessToServer`) — deprioritized. The networking ❌ gap (NetAdapter) is now fully covered. Security is 100% covered. Networking is 100% covered. That feels solid.

---

## Cross-cutting patterns

There are patterns that apply to every module. Establishing them early and keeping them consistent was probably the most valuable decision in the project.

### Linux-only guard in `.psm1`

Every module throws immediately if loaded on Windows:

```powershell
#Requires -Version 7.2
if (-not $IsLinux) {
    throw "Storage.Linux cannot be loaded on Windows. On Windows, use the built-in Storage module."
}
```

This is at the very top of `.psm1`, before dot-sourcing anything. The alternative — transparently delegating to the real Windows cmdlets — sounds appealing but creates a maintenance burden. You end up maintaining two execution paths. The Windows path drifts. Tests stop covering Linux behaviour because the module loads fine on Windows and the Windows cmdlets pass. Clean failure is better than silent drift.

### `Where-Object` instead of `-Filter -Exclude`

Early modules used `-Filter` and `-Exclude` parameters on `Get-ChildItem` inside `.psm1`. On Linux, the FileSystem provider silently ignores `-Filter` and `-Exclude` — it uses the provider-native filtering which on Linux does nothing for those parameters. Replaced everywhere with explicit `Where-Object { $_.Name -notlike '*.Tests.ps1' }` expressions.

### Stub strategy

Windows modules export large surfaces. `Storage` has 161 cmdlets. `NetTCPIP` covers 34 and `DnsClient` adds 21 more. We cannot implement all of them — and do not need to. The pattern: export every cmdlet name, implement the ones that cover real-world usage, emit `Write-Warning "not yet implemented on Linux"` for the rest.

This keeps `Get-Command -Module Storage.Linux` consistent with the Windows version. Scripts that call a stub get a warning rather than a "command not found" error. If someone needs one of the stubs, the warning message is the signal.

### `BeforeDiscovery` in test files

Every test file has:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeDiscovery {
    $script:OnLinux = $IsLinux
}

BeforeAll {
    if ($IsLinux) {
        Import-Module $PSScriptRoot/ModuleName.psd1 -Force
    }
}
```

`BeforeDiscovery` sets the platform flag used by `-Skip:(-not $script:OnLinux)` on every `Describe` block. `Import-Module` is inside `BeforeAll` rather than `BeforeDiscovery` because `$PSScriptRoot` is reliable at runtime but can be `$null` during Pester's discovery phase depending on how the test run was invoked.

### `ShouldProcess` on mutating cmdlets

Every cmdlet that modifies system state supports `-WhatIf` and `-Confirm`. This is done via `[CmdletBinding(SupportsShouldProcess)]` and a `$PSCmdlet.ShouldProcess(...)` guard before any system call. It costs almost nothing to add and makes every module safe to explore with `-WhatIf` before committing.

### Structured `ErrorRecord` everywhere

No bare `throw "some string"` and no `Write-Error "some string"`. Every error path constructs a typed exception, wraps it in an `ErrorRecord` with a unique error ID and an `ErrorCategory` enum value, and calls `$PSCmdlet.WriteError(...)` or `$PSCmdlet.ThrowTerminatingError(...)`. This makes errors catchable by type and filterable in logs.

```powershell
$ex = [System.InvalidOperationException]::new("CUPS not found. Install: apt install cups")
$er = [System.Management.Automation.ErrorRecord]::new(
    $ex, 'PrintManagement.Linux.CupsNotFound',
    [System.Management.Automation.ErrorCategory]::NotInstalled, $null)
$PSCmdlet.ThrowTerminatingError($er)
```

### `IDisposable` in `try/finally`

Any .NET object implementing `IDisposable` (X509Store, X509Chain, RSA key, stream) is opened inside a `try` block and disposed in the `finally` block — unconditionally, whether the body threw or not. This was audited in session 17 ([part 10]({% post_url 2026-05-08-reading-the-manual-linux-command-wrapping-part-10 %})) and applied consistently from PKI.Linux onwards.

---

## Storage.Linux

**Disk, volume, and partition management.** Wraps `lsblk`, `df`, `mount`, and Crescendo-powered block device helpers. 4 implemented, 157 stubs. [README][storage]

### `lsblk --bytes`

`lsblk` returns sizes like `465.8G` and `512M` by default — human-readable strings. Without `--bytes`, `Size` ends up as a string and anything that compares or sorts by size breaks silently. The `--bytes` flag was missing from the first version; tests caught it because `$disk.Size -gt 0` was always `$false` against a string.

### `[SWAP]` in output

`lsblk` lists swap partitions with `[SWAP]` as the mount point. The volume parser skips any entry whose mount point does not start with `/` — this excludes swap and unmounted devices cleanly.

### Crescendo as a private helper

`Microsoft.PowerShell.Crescendo` wraps `lsblk` JSON output internally. It is an implementation detail — not listed as a required module, not exposed in the public surface.

---

## PowerShell.Management.Linux

**Service management and computer information.** 8 implemented: `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service`, `Set-Service`, `Get-ComputerInfo`, `Rename-Computer`, `Restart-Computer`. [README][mgmt]

### Joining two `systemctl` outputs

`Get-Service` needs both service status (running/stopped) and the service description. `systemctl list-units --type=service --all` gives the first. `systemctl list-unit-files --type=service` gives the second. Neither gives both. Two calls, joined on service name, merged into one object.

### `Get-ComputerInfo` from `/proc`

On Linux, the data that Windows returns from a single WMI call comes from six different files: `/proc/version`, `/proc/cpuinfo`, `/proc/meminfo`, `/etc/os-release`, `/proc/uptime`, and `hostname`. The result assembles into a `PSCustomObject` covering the properties scripts actually use.

---

## NetTCPIP.Linux

**IP addresses, routing, and TCP connections.** 4 implemented: `Get-NetIPAddress`, `Get-NetIPConfiguration`, `Get-NetRoute`, `Get-NetTCPConnection`. 30 stubs. DNS cmdlets live in the separate `DnsClient.Linux` module. [README][nettcpip]

### `ip -json` for structured output

`ip -json addr show` and `ip -json route show` return proper JSON. No text parsing. This is the advantage of `iproute2` since version 4.12 (2017). `Get-NetIPAddress`, `Get-NetRoute`, and `Get-NetIPConfiguration` all use this.

### LISTEN sockets and the `*` port

`ss -tnap` shows listening sockets with `0.0.0.0:*` or `[::]:*` as the remote peer. The `*` is not a valid port number. A regex that extracts digits from the port field silently returns nothing for all LISTEN sockets — they are just dropped from output. Detect `:\*$` explicitly and return `0` for the remote port.

### Loop variable shadowing

Inside `Get-NetTCPConnection`, the loop variable was named `$localPort` — same as the `-LocalPort` parameter. Inside the loop, `$localPort` resolved to the current iteration value. The filter always matched everything or nothing. Renamed to `$_localPort`. PowerShell parameter names and pipeline variables share the same scope.

### `Get-NetRoute` needs two calls

`ip -json route show` returns IPv4 only. IPv6 requires `ip -6 -json route show`. The `default` route has no destination prefix — mapped to `0.0.0.0/0` (IPv4) or `::/0` (IPv6) to match Windows behavior.

---

## DnsClient.Linux

**DNS resolution and client configuration.** Mirrors the Windows `DnsClient` module — kept separate from NetTCPIP.Linux to match the Windows module boundary. 4 implemented: `Resolve-DnsName`, `Clear-DnsClientCache`, `Get-DnsClientServerAddress`, `Get-DnsClientGlobalSetting`. 17 stubs for NRPT, DoH, and remaining configuration cmdlets. [README][dnsclient]

### Why a separate module

On Windows, `DnsClient` and `NetTCPIP` are separate modules — you load them independently and they have distinct scopes. An earlier version merged the DnsClient cmdlets into NetTCPIP.Linux v0.3.0 for convenience. That was wrong. Scripts that do `Import-Module DnsClient` on Windows cannot replicate that with `Import-Module NetTCPIP.Linux` — the names do not match and the intent does not match. v0.4.0 of NetTCPIP.Linux removed all DnsClient cmdlets; DnsClient.Linux v0.1.0 took them as its initial release.

### `Resolve-DnsName` via `dig`

`dig +noall +answer +authority +additional +ttlid +comments` gives structured section output. The module parses the section markers and maps record types to typed `PSCustomObject` entries with `Name`, `Type`, `TTL`, and `IPAddress` (or `NameHost` for CNAME/PTR, etc.). If `dig` is not installed, the function throws a terminating error with the package install command in the message — unlike most stubs, DNS resolution with a missing tool is not a graceful degradation situation.

### `Clear-DnsClientCache` with fallback

`resolvectl flush-caches` works on systemd-resolved systems. On systems without systemd-resolved, the fallback is `nscd --invalidate=hosts`. If neither is available, a warning is emitted. The function is fully `ShouldProcess`-aware — `-WhatIf` reports what would be flushed without running anything.

### `Get-DnsClientServerAddress` from two sources

`/etc/resolv.conf` gives the global nameserver list. `resolvectl status` per interface gives per-interface DNS server assignments. The function merges both, deduplicating where the global and per-interface entries agree. Interface-specific overrides are returned with the interface name populated; the global fallback uses `InterfaceAlias = 'Global'`.

---

## Update.Linux

**Package update management as a PSWindowsUpdate peer.** 3 implemented: `Get-LinuxUpdate` / `Get-WindowsUpdate`, `Install-LinuxUpdate` / `Install-WindowsUpdate`, `Get-LinuxUpdateHistory` / `Get-WUHistory`. [README][update]

### The `Listing...` header

`apt list --upgradable 2>/dev/null` always emits a `Listing...` line before the package data. One `Where-Object { $_ -notmatch '^Listing' }` removes it.

### dpkg.log action verbs

dpkg.log records `install`, `upgrade`, `remove`, `purge`, and `configure` actions. `configure` is a post-install step that appears for every package — include it and every install shows up twice in history. Filter to `install` and `upgrade` only.

---

## PowerShell.Security.Linux

**File ACL management.** `Get-LinuxAcl` / `Get-Acl`, `Set-LinuxAcl` / `Set-Acl`. Stubs for Authenticode and catalog functions. [README][security]

### `stat` vs `getfacl`

`stat --format='%a|%A|%U|%G|%F|%n'` is universally available. It gives octal mode, symbolic mode, owner, group, file type, and filename. `getfacl` adds named-user and named-group ACL entries but requires the `acl` package. The module uses `stat` as baseline and enriches with `getfacl` if present.

### PSPath provider prefix

`Get-ChildItem` produces objects with `PSPath` set to `Microsoft.PowerShell.Core\FileSystem::/etc/hosts`. Passing this to `stat` fails — strip the provider prefix first. This only surfaces during pipeline input testing (`Get-ChildItem /etc | Get-LinuxAcl`), not when passing literal paths.

---

## PowerShell.LocalAccounts.Linux

**All 15 LocalAccounts cmdlets implemented.** No stubs needed — Linux has tools for everything: `useradd`, `usermod`, `userdel`, `groupadd`, `groupmod`, `groupdel`, `gpasswd`, `getent`, `passwd -S`, `chage`. [README][localaccounts]

### Three sources per user

`Get-LocalUser` calls `getent passwd` for basic user data, `passwd -S` for lock status, and `chage -l` for expiry dates. Three commands, one object per user. On systems where `passwd -S` requires root, the module catches the permission error and defaults `Enabled` to `$true` with a warning.

### Primary group membership gap

`/etc/group` only lists supplementary memberships — not primary group membership. `Get-LocalGroupMember` also scans `/etc/passwd` for users whose primary GID matches the requested group. Without this, querying a user's primary group returns empty results.

---

## ScheduledTasks.Linux

**13 of 15 ScheduledTasks cmdlets via systemd timers.** `Get-ScheduledTask`, `Register-ScheduledTask`, `Unregister-ScheduledTask`, `Start-ScheduledTask`, `Stop-ScheduledTask`, `Enable-ScheduledTask`, `Disable-ScheduledTask`, `Get-ScheduledTaskInfo`, plus the four `New-ScheduledTask*` factory functions. Stubs for `Set-ScheduledTask` and `Export-ScheduledTask`. [README][scheduledtasks]

### Why systemd, not cron

Cron was the obvious answer. systemd timers were chosen because they integrate with `systemctl` — `Start-ScheduledTask`, `Stop-ScheduledTask`, `Enable-ScheduledTask`, and `Disable-ScheduledTask` all map directly to `systemctl start/stop/enable/disable`. Cron has no lifecycle management equivalent. Systemd also provides `journald` log integration and `systemctl list-timers` for structured status.

### Timer + service unit pair

Each task creates two files: a `.timer` unit with the schedule (`OnCalendar=` or `OnBootSec=`) and a `.service` unit with the command to run. They share the same base name. `Register-ScheduledTask` writes both and runs `systemctl daemon-reload`.

### User vs system scope

Tasks go to `/etc/systemd/system/` (system scope, requires root) or `~/.config/systemd/user/` (user scope). Scope is inferred from `id -u` when not explicitly provided.

---

## PKI.Linux

**Certificate management via .NET cryptography APIs — no openssl CLI dependency.** 7 cmdlets fully implemented: `New-SelfSignedCertificate`, `Export-Certificate`, `Export-PfxCertificate`, `Get-PfxData`, `Import-Certificate`, `Import-PfxCertificate`, `Test-Certificate`. `Get-Certificate` partially implemented (LocalStore parameter set). 9 stubs for Windows-only enrollment/AD cmdlets. [README][pki]

### Pure .NET — no openssl

`System.Security.Cryptography.X509Certificates` is fully cross-platform in .NET 6+. Every operation — generating keys, signing, encoding DER/PEM/PFX — is done through the .NET API. This means no dependency on `openssl` being installed, no parsing of `openssl` text output, and consistent behaviour across distributions. It also means the module works on distros where `openssl` is not in PATH or has a non-standard version.

### IDisposable audit

After the initial implementation, a review against the PowerShell SDK development guidelines found that `X509Chain`, `X509Store`, `RSA`, and `ECDsa` objects were being created but never disposed. These implement `IDisposable` and hold cryptographic memory that should be released deterministically. All were wrapped in `try/finally { .Dispose() }`. The detailed write-up is in [part 10]({% post_url 2026-05-08-reading-the-manual-linux-command-wrapping-part-10 %}).

### Partial implementation model

Some cmdlets have multiple parameter sets — some implementable on Linux, some not. `Get-Certificate` has `LocalStore` (reads from `X509Store`, fully Linux-compatible), `SubmitRequest` (sends to a CA via RPC — Windows-specific), and `PendingRetrieval` (retrieves a pending cert via DCOM — Windows-specific). The Linux module implements `LocalStore` fully and throws `PlatformNotSupportedException` for the others, with an error message that names `LocalStore` as the supported alternative. This is the **partial implementation model**: between a full implementation and a stub, documented per-parameter-set.

---

## PrintManagement.Linux

**Print queue management via CUPS.** 7 cmdlets implemented: `Get-Printer`, `Get-PrintJob`, `Add-Printer`, `Remove-Printer`, `Remove-PrintJob`, `Suspend-PrintJob`, `Resume-PrintJob`. 15 stubs for driver and port management. [README][printmgmt]

### CUPS as the backend

Every print operation on Linux goes through CUPS. The module wraps `lpstat` (query), `lpadmin` (configure), and `cancel` (job control). These are the standard CUPS command-line tools available on any system with CUPS installed.

`Get-Printer` parses three separate `lpstat` calls — `lpstat -p` for status, `lpstat -v` for device URIs, `lpstat -a` for accepting state — and joins them into one object per printer. There is no single `lpstat` flag that returns all three in one call.

### CUPS not installed

If CUPS is not installed, `lpstat` is not available. The module checks with `Get-Command lpstat -ErrorAction SilentlyContinue` before any CUPS operation and throws a structured `ErrorRecord` with `ErrorCategory.NotInstalled` and the package install command in the message.

### Suspend is `cancel -H hold`

CUPS does not have a dedicated "pause job" command. Suspending a job is done via `cancel -H hold <jobid>`. Resuming is `cancel -H resume <jobid>`. The Windows cmdlet names `Suspend-PrintJob` / `Resume-PrintJob` map to these CUPS hold/release operations.

---

## PowerShell.Utility.Linux

**UI cmdlets.** `Out-GridView` and `Show-Command` via `Microsoft.PowerShell.ConsoleGuiTools`. `Out-Printer` via CUPS `lp`. `ConvertFrom-SddlString` as a Linux-aware stub. [README][utility]

### ConsoleGuiTools, not PSTuiTools

Two terminal UI frameworks exist: `Microsoft.PowerShell.ConsoleGuiTools` (Terminal.Gui v1.16, read-only grid) and `PSTuiTools` (Terminal.Gui v1.19, editable forms). They cannot be loaded in the same PS session — assembly version conflict. We chose ConsoleGuiTools because it is the Microsoft-supported one and `Out-GridView` only needs read/select capability. `Show-Command` is a functional approximation — it lists available commands in the grid rather than rendering a true GUI form.

### `Out-Printer` via `lp`

`lp -d <printer> -` takes stdin. `Out-Printer` formats the input object as text (`| Out-String`) and pipes it to `lp`. The `-PrinterName` parameter maps to `-d`. If no printer is specified, `lp` uses the system default.

---

## NetAdapter.Linux

**Network adapter management.** 4 implemented: `Get-NetAdapter`, `Get-NetAdapterStatistics`, `Enable-NetAdapter`, `Disable-NetAdapter`. 74 stubs for NDIS hardware offload and other Windows-specific cmdlets. This module closes the last ❌ gap in the networking region. [README][netadapter]

### `ip -json link show`

`iproute2` has supported `--json` since kernel 4.12 (2017). `Get-NetAdapter` uses `ip -json link show` — no text parsing. Each link object has `ifindex`, `ifname`, `address` (MAC), `operstate`, `flags`, `mtu`, and `link_type`.

### Link speed from `/sys/class/net`

`ip link show` does not include link speed. Speed is read from `/sys/class/net/<name>/speed`. Virtual adapters (loopback, bridges, tunnels) return -1 or an error — these are reported as `Unknown`. Physical adapters on a live link return the speed in Mbps.

### Statistics from `ip -s -json link show`

The `-s` flag adds a `stats64` subtree to each link object with `rx` and `tx` sub-objects containing `bytes`, `packets`, `errors`, and `dropped`. `Get-NetAdapterStatistics` maps these directly to `ReceivedBytes`, `SentBytes`, etc.

### NDIS offload cmdlets — out of scope

The majority of the Windows NetAdapter surface covers Windows NDIS hardware offload: checksum offload, LSO, RSS, VMQ, SR-IOV, etc. Linux has equivalent features but they are controlled via `ethtool`, `sysfs`, and driver-specific interfaces — not a unified API. All 74 non-implemented cmdlets are stubbed with `Write-Warning`.

---

## Test coverage

All 12 modules were run through their full Pester test suites on both Windows (PS 7.5.1, Pester 5.3.3) and WSL2 Ubuntu 24.04 (PS 7.5.1, Pester 5.7.1). 1513 tests total. Zero failures on either platform.

| Module | Tests | Win Pass | Win Skip | WSL Pass | WSL Skip |
|---|:---:|:---:|:---:|:---:|:---:|
| `Storage.Linux` | 534 | 15 | 519 | 533 | 1 |
| `PowerShell.Management.Linux` | 89 | 15 | 74 | 89 | 0 |
| `NetTCPIP.Linux` | 167 | 15 | 152 | 167 | 0 |
| `DnsClient.Linux` | 103 | 12 | 91 | 97 | 6 |
| `Update.Linux` | 134 | 63 | 71 | 134 | 0 |
| `PowerShell.Security.Linux` | 78 | 37 | 41 | 78 | 0 |
| `PowerShell.LocalAccounts.Linux` | 71 | 10 | 61 | 70 | 1 |
| `ScheduledTasks.Linux` | 56 | 17 | 39 | 39 | 17 |
| `PKI.Linux` | 37 | 1 | 36 | 36 | 1 |
| `PrintManagement.Linux` | 45 | 1 | 44 | 21 | 24 |
| `PowerShell.Utility.Linux` | 28 | 18 | 10 | 26 | 2 |
| `NetAdapter.Linux` | 171 | 0 | 171 | 171 | 0 |
| **TOTAL** | **1513** | **204** | **1309** | **1461** | **52** |

Windows skips are all Linux-only tests. WSL skips are tool-conditional: CUPS not installed (PrintManagement, 24), `dig` not installed (DnsClient, 6), systemd task tests require non-root elevation (ScheduledTasks, 17), and a handful of single-test edge cases across other modules.

---

## Coverage analysis

After ten modules, going back to [Evgenij Smirnov's gap list](https://github.com/psconfeu/2025/blob/main/Evgenij%20Smirnov/Linux/00-inthebox/MissingCmdletsGroupedSorted.ps1) from the 2025 European PowerShell Summit. The list has 209 cmdlets. 91 are genuinely Windows-specific with no useful Linux equivalent (VPN stack, IPsec policy engine, Teredo, Windows Firewall model, NDIS hardware offload API). The remaining 118 are the target.

Legend: ✅ Implemented · 🔶 Stubbed (warns, returns nothing) · ❌ No module · ⛔ Windows-specific

### Summary

| Region | Total | ✅ | 🔶 | ❌ | ⛔ |
|---|:---:|:---:|:---:|:---:|:---:|
| Disk / Storage | 26 | 3 | 23 | 0 | 0 |
| Printing | 18 | 6 | 12 | 0 | 0 |
| Networking | 105 | 11 | 9 | 0 | 85 |
| Services / Tasks | 22 | 16 | 6 | 0 | 0 |
| Client (SMB/NFS) | 4 | 0 | 0 | 4 | 0 |
| Security | 17 | 17 | 0 | 0 | 0 |
| Sundry | 17 | 10 | 1 | 0 | 6 |
| **Total** | **209** | **63** | **51** | **4** | **91** |

Of the 118 in-scope cmdlets: **53% implemented, 43% stubbed, 3% not yet covered (SMB/NFS client).**

---

### Disk / Storage (26 cmdlets)

| Cmdlet | Module | Status |
|---|---|:---:|
| `Get-Disk` | Storage.Linux | ✅ |
| `Get-Partition` | Storage.Linux | ✅ |
| `Get-PhysicalDisk` | Storage.Linux | ✅ |
| `Add-PartitionAccessPath` | Storage.Linux | 🔶 |
| `Add-PhysicalDisk` | Storage.Linux | 🔶 |
| `Clear-Disk` | Storage.Linux | 🔶 |
| `Connect-IscsiTarget` | Storage.Linux | 🔶 |
| `Connect-VirtualDisk` | Storage.Linux | 🔶 |
| `Convert-PhysicalDisk` | Storage.Linux | 🔶 |
| `Disconnect-IscsiTarget` | Storage.Linux | 🔶 |
| `Dismount-DiskImage` | Storage.Linux | 🔶 |
| `Format-Volume` | Storage.Linux | 🔶 |
| `Get-DiskImage` | Storage.Linux | 🔶 |
| `Get-PartitionSupportedSize` | Storage.Linux | 🔶 |
| `New-Partition` | Storage.Linux | 🔶 |
| `New-Volume` | Storage.Linux | 🔶 |
| `Remove-Partition` | Storage.Linux | 🔶 |
| `Remove-PartitionAccessPath` | Storage.Linux | 🔶 |
| `Remove-PhysicalDisk` | Storage.Linux | 🔶 |
| `Repair-VirtualDisk` | Storage.Linux | 🔶 |
| `Repair-Volume` | Storage.Linux | 🔶 |
| `Reset-PhysicalDisk` | Storage.Linux | 🔶 |
| `Resize-Partition` | Storage.Linux | 🔶 |
| `Set-Partition` | Storage.Linux | 🔶 |
| `Set-PhysicalDisk` | Storage.Linux | 🔶 |
| `Update-Disk` | Storage.Linux | 🔶 |

---

### Printing (18 cmdlets)

| Cmdlet | Module | Status |
|---|---|:---:|
| `Add-Printer` | PrintManagement.Linux | ✅ |
| `Get-Printer` | PrintManagement.Linux | ✅ |
| `Get-PrintJob` | PrintManagement.Linux | ✅ |
| `Remove-Printer` | PrintManagement.Linux | ✅ |
| `Remove-PrintJob` | PrintManagement.Linux | ✅ |
| `Resume-PrintJob` | PrintManagement.Linux | ✅ |
| `Add-PrinterDriver` | PrintManagement.Linux | 🔶 |
| `Add-PrinterPort` | PrintManagement.Linux | 🔶 |
| `Get-PrintConfiguration` | PrintManagement.Linux | 🔶 |
| `Get-PrinterDriver` | PrintManagement.Linux | 🔶 |
| `Get-PrinterPort` | PrintManagement.Linux | 🔶 |
| `Get-PrinterProperty` | PrintManagement.Linux | 🔶 |
| `Rename-Printer` | PrintManagement.Linux | 🔶 |
| `Remove-PrinterDriver` | PrintManagement.Linux | 🔶 |
| `Remove-PrinterPort` | PrintManagement.Linux | 🔶 |
| `Set-PrintConfiguration` | PrintManagement.Linux | 🔶 |
| `Set-Printer` | PrintManagement.Linux | 🔶 |
| `Set-PrinterProperty` | PrintManagement.Linux | 🔶 |

---

### Networking (105 cmdlets)

**Implemented (11)**

| Cmdlet | Module | Linux tool |
|---|---|---|
| `Resolve-DnsName` | DnsClient.Linux | `dig` |
| `Clear-DnsClientCache` | DnsClient.Linux | `resolvectl` / `nscd` |
| `Get-DnsClientServerAddress` | DnsClient.Linux | `/etc/resolv.conf` + `resolvectl` |
| `Get-NetIPAddress` | NetTCPIP.Linux | `ip -json addr` |
| `Get-NetIPConfiguration` | NetTCPIP.Linux | `ip -json addr` + `ip -json route` |
| `Get-NetRoute` | NetTCPIP.Linux | `ip -json route` |
| `Get-NetTCPConnection` | NetTCPIP.Linux | `ss -tnap` |
| `Get-NetAdapter` | NetAdapter.Linux | `ip -json link show` |
| `Get-NetAdapterStatistics` | NetAdapter.Linux | `ip -s -json link show` |
| `Enable-NetAdapter` | NetAdapter.Linux | `ip link set up` |
| `Disable-NetAdapter` | NetAdapter.Linux | `ip link set down` |

**Stubbed — in-module, potentially Linux-implementable (9)**

| Cmdlet | Module | Future tool |
|---|---|---|
| `Find-NetRoute` | NetTCPIP.Linux | `ip route get` |
| `Get-DnsClient` | DnsClient.Linux | `resolvectl` |
| `Get-DnsClientCache` | DnsClient.Linux | `resolvectl statistics` |
| `Get-NetIPInterface` | NetTCPIP.Linux | `ip link` |
| `Get-NetIPv4Protocol` | NetTCPIP.Linux | `sysctl` |
| `Get-NetIPv6Protocol` | NetTCPIP.Linux | `sysctl` |
| `Get-NetNeighbor` | NetTCPIP.Linux | `ip neigh` |
| `Get-NetTCPSetting` | NetTCPIP.Linux | `sysctl net.ipv4.tcp_*` |
| `Test-NetConnection` | NetTCPIP.Linux | `ping` / `nc` |

**Not covered — no module yet, implementable (0)**

All networking cmdlets from Evgenij's list are now covered (implemented or stubbed in a module).

**Out of scope — Windows-specific (85)**

| Group | Count | Reason |
|---|:---:|---|
| VPN (`Add-VpnConnection*`) | 5 | Windows VPN stack |
| NetIPsec (`*-NetIPsec*`, `Copy-NetIPsec*`, `Find-NetIPsecRule`) | 20 | Windows IPsec policy engine |
| Teredo (`Get-NetTeredo*`) | 2 | Windows IPv6 tunneling |
| NetFirewall (`*-NetFirewall*`) | 14 | Windows Defender Firewall model |
| NetAdapter hardware offload (`Disable/Enable-NetAdapter{Checksum,Encap,IPsec,LSO,PacketDirect,PowerMgmt,QoS,RDMA,RSC,RSS,SRIOV,URO,USO,VMQ}`) | 29 | Windows NDIS driver model |
| NetAdapter advanced Get-* (`Get-NetAdapter{AdvancedProperty,Binding,HardwareInfo,IPsecOffload,LSO,PacketDirect,PowerMgmt,QoS,RDMA,RSC,RSS,SRIOV,SriovVf,URO,USO}`) | 15 | Windows NDIS driver model |

---

### Services / Tasks (22 cmdlets)

| Cmdlet | Module | Status |
|---|---|:---:|
| `Get-Service` | PowerShell.Management.Linux | ✅ |
| `Restart-Service` | PowerShell.Management.Linux | ✅ |
| `Set-Service` | PowerShell.Management.Linux | ✅ |
| `Start-Service` | PowerShell.Management.Linux | ✅ |
| `Stop-Service` | PowerShell.Management.Linux | ✅ |
| `Disable-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `Enable-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `Get-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `Get-ScheduledTaskInfo` | ScheduledTasks.Linux | ✅ |
| `New-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `New-ScheduledTaskAction` | ScheduledTasks.Linux | ✅ |
| `New-ScheduledTaskPrincipal` | ScheduledTasks.Linux | ✅ |
| `New-ScheduledTaskSettingsSet` | ScheduledTasks.Linux | ✅ |
| `New-ScheduledTaskTrigger` | ScheduledTasks.Linux | ✅ |
| `Register-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `Start-ScheduledTask` | ScheduledTasks.Linux | ✅ |
| `Export-ScheduledTask` | ScheduledTasks.Linux | 🔶 |
| `New-ScheduledJobOption` | ScheduledTasks.Linux | 🔶 |
| `New-Service` | PowerShell.Management.Linux | 🔶 |
| `Remove-Service` | PowerShell.Management.Linux | 🔶 |
| `Resume-Service` | PowerShell.Management.Linux | 🔶 |
| `Suspend-Service` | PowerShell.Management.Linux | 🔶 |

---

### Client functionality — SMB / NFS (4 cmdlets)

| Cmdlet | Status | Notes |
|---|:---:|---|
| `Block-SmbClientAccessToServer` | ❌ | SmbShare.Linux deprioritized |
| `Disconnect-NfsSession` | ❌ | No module |
| `Get-NfsClientConfiguration` | ❌ | No module — `nfsstat` available |
| `Get-NfsSession` | ❌ | No module — `showmount` available |

---

### Security (17 cmdlets)

| Cmdlet | Module | Status |
|---|---|:---:|
| `Get-Acl` | PowerShell.Security.Linux | ✅ |
| `Set-Acl` | PowerShell.Security.Linux | ✅ |
| `Add-LocalGroupMember` | PowerShell.LocalAccounts.Linux | ✅ |
| `Disable-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `Enable-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `Get-LocalGroup` | PowerShell.LocalAccounts.Linux | ✅ |
| `Get-LocalGroupMember` | PowerShell.LocalAccounts.Linux | ✅ |
| `Get-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `New-LocalGroup` | PowerShell.LocalAccounts.Linux | ✅ |
| `New-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `Remove-LocalGroup` | PowerShell.LocalAccounts.Linux | ✅ |
| `Remove-LocalGroupMember` | PowerShell.LocalAccounts.Linux | ✅ |
| `Remove-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `Rename-LocalGroup` | PowerShell.LocalAccounts.Linux | ✅ |
| `Rename-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |
| `Set-LocalGroup` | PowerShell.LocalAccounts.Linux | ✅ |
| `Set-LocalUser` | PowerShell.LocalAccounts.Linux | ✅ |

---

### Sundry (17 cmdlets)

| Cmdlet | Module | Status | Notes |
|---|---|:---:|---|
| `Export-Certificate` | PKI.Linux | ✅ | |
| `Export-PfxCertificate` | PKI.Linux | ✅ | |
| `Get-ComputerInfo` | PowerShell.Management.Linux | ✅ | |
| `Get-PfxData` | PKI.Linux | ✅ | |
| `New-SelfSignedCertificate` | PKI.Linux | ✅ | |
| `Out-GridView` | PowerShell.Utility.Linux | ✅ | |
| `Out-Printer` | PowerShell.Utility.Linux | ✅ | |
| `Rename-Computer` | PowerShell.Management.Linux | ✅ | |
| `Show-Command` | PowerShell.Utility.Linux | ✅ | |
| `Test-Certificate` | PKI.Linux | ✅ | |
| `Set-TimeZone` | PowerShell.Management.Linux | 🔶 | Not available in PS7.5 on Linux natively |
| `Get-DisplayResolution` | — | ⛔ | WinPS only (noted by Evgenij) |
| `Get-PlatformIdentifier` | — | ⛔ | No standard PS cmdlet |
| `Get-PnpDevice` | — | ⛔ | Windows PnP subsystem |
| `Get-PnpDeviceProperty` | — | ⛔ | Windows PnP subsystem |
| `Get-SystemDriver` | — | ⛔ | Windows driver model |
| `Set-SystemPreferredUILanguage` | — | ⛔ | Windows UI language stack |

---

The remaining ❌ cmdlets are SMB/NFS client cmdlets — deprioritized given the complexity of SMB server-side infrastructure and the low value of NFS client wrappers at this stage.

---

All twelve module repositories are at [github.com/peppekerstens](https://github.com/peppekerstens). The links in the table at the top of this post go to specific commits, so they will show the code as it was when this post was written. Pull requests welcome.

---

## PSScriptAnalyzer — Getting to Zero

After all twelve modules were test-complete, we ran [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) across every module to systematically clean up code quality issues.

**Baseline:** Error=6, Warning=399 across 12 modules.

### Real bugs fixed

The errors and actionable warnings turned out to be genuine defects worth fixing:

**Automatic variable collisions:**
- `Get-LocalUser.ps1`: variable `$home` overwrites PowerShell's read-only automatic variable (`$HOME`). Renamed to `$homeDir`.
- `New-LocalUser.ps1`, `Rename-LocalUser.ps1`: variable `$args` overwrites the automatic `$args` array. Renamed to `$cmdArgs`.

**Empty catch blocks:**
Seven empty `catch { }` blocks across `Get-LocalUser.ps1`, `Get-ComputerInfo.ps1`, and `Get-ScheduledTaskInfo.ps1` swallowed exceptions silently. Changed to `catch { Write-Debug $_.Exception.Message }` — still non-fatal, but now debuggable.

**Pipeline functions without `process {}`:**
Eleven functions declared `ValueFromPipeline` or `ValueFromPipelineByPropertyName` on parameters but had no `process {}` block, meaning only the *last* piped value would be processed. Fixed by wrapping the entire function body (including the Windows delegation path) in `process {}`. The affected functions were spread across `Storage.Linux`, `PowerShell.Management.Linux`, `ScheduledTasks.Linux`, `PKI.Linux`, and `PowerShell.Utility.Linux`.

One subtle trap: putting code *before* `process {}` in a function body causes PowerShell (and PSSA) to interpret the `process` keyword as the `Get-Process` cmdlet alias. The `process {}` named block must be the first statement in the function body.

**Manifest issues:**
`PowerShell.LocalAccounts.Linux.psd1` had `CmdletsToExport = '*'` — changed to `CmdletsToExport = @()` since the module exports functions, not compiled cmdlets.

**Credential parameter type:**
`Get-Certificate.ps1` had `[object] $Credential`. Changed to `[PSCredential]` with the `[System.Management.Automation.Credential()]` attribute, matching the correct PowerShell credential pattern.

**Unused variables:**
`Stop-Service.ps1`: `$params = @{}` built but then bypassed. `Get-Service.ps1`: `$loadState` captured but never used. `Resolve-DnsName.ps1`: a first `$lines` capture was immediately overwritten by a better `$rawLines` call. All removed.

### Intentional patterns — suppressed, not fixed

A large chunk of the warnings were correct rule violations but *intentional by design*:

| Rule | Count | Reason |
|---|:---:|---|
| `PSAvoidOverwritingBuiltInCmdlets` | 18 | That's literally what the modules do |
| `PSUseShouldProcessForStateChangingFunctions` | 110 | Stub functions don't change state — they emit a warning |
| `PSShouldProcess` | 75 | Same stubs: `SupportsShouldProcess` without calling `$PSCmdlet.ShouldProcess()` |
| `PSReviewUnusedParameter` | 79 | Stub parameters exist for interface parity with Windows cmdlets |
| `PSUseBOMForUnicodeEncodedFile` | 66 | Cross-platform UTF-8 without BOM is intentional |

These were suppressed by adding a `PSScriptAnalyzerSettings.psd1` at the root of each of the twelve module repos with an `ExcludeRules` list. This is cleaner than sprinkling `[SuppressMessageAttribute]` on every stub function.

The `run-pssa.ps1` runner was updated to pass `-Settings` per module, and to filter results from `Helpers\` and `Crescendo\` directories (scratch/generated files that are not part of the module surface).

**Final result:** Error=0, Warning=0 across all 12 modules. 0 test regressions (204 pass, 1309 skip on Windows; 1513 total unchanged).


