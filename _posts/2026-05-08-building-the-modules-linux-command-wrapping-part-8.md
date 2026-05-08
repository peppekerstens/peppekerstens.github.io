---
title: Building seven modules - Linux Command Wrapping Part 8
toc: true
---

This is the technical post. Seven modules, all the patterns, all the gotchas. If you want the meta-story about AI-assisted development and why I am doing this at all, that is [part 7]({% post_url 2026-05-08-ai-assisted-linux-command-wrapping-part-7 %}). This post is about what we built and what we learned building it.

The modules:

- **Storage.Linux** — disk, volume, partition management (`lsblk`, `df`, `mount`)
- **PowerShell.Management.Linux** — service management, computer info, process management
- **NetTCPIP.Linux** — IP addresses, routing, TCP connections (`ip`, `ss`)
- **Update.Linux** — package updates as a PSWindowsUpdate peer (`apt`)
- **PowerShell.Security.Linux** — file ACLs (`stat`, `chmod`, `chown`, `getfacl`)
- **PowerShell.LocalAccounts.Linux** — user and group management (`useradd`, `getent`, etc.)
- **ScheduledTasks.Linux** — scheduled task management via systemd timers

All repositories are public under [peppekerstens](https://github.com/peppekerstens). All modules have been tested on WSL2 Ubuntu. Each README has a detailed "How we built this" section if you want the full story on any individual module.

---

## Cross-cutting patterns

Before getting into per-module details: there are patterns that apply to every module. We established them early and kept them consistent throughout. This is probably the most useful part of the post if you are building something similar.

### Linux-only guard in `.psm1`

Every module throws immediately if loaded on Windows:

```powershell
if ($IsWindows) {
    throw "Storage.Linux requires Linux. On Windows, use the built-in Storage module."
}
```

This is at the very top of `.psm1`, before anything else. The alternative — delegating to Windows cmdlets — sounds appealing but creates a maintenance burden: you end up maintaining two execution paths, and the Windows path diverges over time. We chose clean failure over false compatibility.

The only exception is the delegation of `Get-LinuxAcl` / `Set-LinuxAcl` to `Microsoft.PowerShell.Security\Get-Acl` / `Set-Acl` on Windows, because those cmdlets work fine there and the module name implies Linux-only anyway.

### `Where-Object` instead of `-Filter -Exclude`

Early modules used `-Filter` on `Where-Object`. Turns out `-Filter` uses the provider's native filtering, which on Linux silently does nothing for most providers. The switch to explicit `Where-Object { $_ -match ... }` expressions was made after noticing that some filter parameters had no effect whatsoever. Subtle, annoying, easily missed.

### Stub strategy

Windows modules export large surfaces. `Storage` has 161 cmdlets. `NetTCPIP` has 34. We cannot implement all of them — and do not need to. The strategy: export all of them, implement the ones that cover real-world usage, emit `Write-Warning "not yet implemented on Linux"` for the rest and return nothing.

This keeps `Get-Command -Module Storage.Linux` consistent with the Windows version. Scripts that call a stub get a warning rather than a "command not found" error. If someone really needs one of the stubs, the warning is clear and actionable.

### Naming conventions

For most modules, Linux-native function names with Windows names as aliases:

```powershell
function Get-LinuxAcl { ... }
Set-Alias -Name Get-Acl -Value Get-LinuxAcl
```

The native name documents intent. The alias ensures drop-in compatibility.

Exception: **PowerShell.LocalAccounts.Linux** uses the Windows names directly (`Get-LocalUser`, `New-LocalGroup`, etc.) because those nouns are platform-neutral — `LocalUser` is a perfectly sensible concept on Linux too. Adding "Linux" to the name would be noise.

### `BeforeDiscovery` in test files

Pester 5.3.x has a specific quirk: `$PSScriptRoot` is `$null` during the discovery phase if you are not careful about when the module import happens. The fix is to wrap any module import in a `BeforeDiscovery` block:

```powershell
BeforeDiscovery {
    $isLinux = $IsLinux
    Import-Module $PSScriptRoot/../ModuleName/ModuleName.psd1 -Force
}
```

Then pass `$isLinux` into `Describe` blocks via `-ForEach @{isLinux = $isLinux}` or use `-Skip:(-not $isLinux)` at the `Describe` level.

Every test file also has:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
```

This prevents the tests from running on ancient Pester 4.x installs and dying in confusing ways.

### `param()` first in example scripts

Every script in the `Examples\` folder that has parameters must have `param()` as the very first statement — before any `#Requires`, before any comments. PowerShell's parameter binding requires this. If you put a `#Requires` block first, the parameters are silently ignored. We caught this via `Examples\Examples.Tests.ps1`, which runs each example script and checks for thrown exceptions.

---

## Storage.Linux

**What it is**: Disk, volume, and partition management. Wraps `lsblk`, `df`, `df -i`, `mount`, and `Crescendo`-powered helpers for block device enumeration.

**Implemented**: `Get-Disk`, `Get-Partition`, `Get-Volume`, `Get-PSDrive` (enhanced). 157 stubs for everything else.

**Full details**: [Storage.Linux README](https://github.com/peppekerstens/Storage.Linux#how-we-built-this)

### The `lsblk --bytes` problem

`lsblk` by default returns sizes like `465.8G` and `512M` — human-readable strings. If you want a number you can do math with, you need `lsblk --bytes`. Without `--bytes`, every `Size` property ends up as a string, and anything that tries to compare or sort by size breaks silently. The `--bytes` flag was not in the first version. Tests caught it because they asserted `$disk.Size -gt 0` and that comparison was always false against a string.

### `[SWAP]` in `lsblk` output

`lsblk` lists swap partitions too. They show up with `[SWAP]` as the mount point. The partition parser needs to skip them or handle them specially — they are not regular mounted filesystems and trying to call `Get-Volume` on them produces nonsense.

### Crescendo as a private helper

Microsoft.PowerShell.Crescendo is used internally to wrap `lsblk` JSON output into typed objects. It is listed as a private dependency rather than a public one — it is an implementation detail, not something consumers of the module need to know about.

---

## PowerShell.Management.Linux

**What it is**: Service management, process management, computer information. The PowerShell Management module on Windows covers a lot of ground; on Linux we focused on the cmdlets used most in automation: `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service`, `Get-Process`, `Get-ComputerInfo`.

**Implemented**: 8 cmdlets. Stubs for the rest.

**Full details**: [PowerShell.Management.Linux README](https://github.com/peppekerstens/PowerShell.Management.Linux#how-we-built-this)

### Joining two `systemctl` outputs

`Get-Service` needs both the service status (running/stopped) and the service description. `systemctl list-units --type=service --all` gives status. `systemctl list-unit-files --type=service` gives the unit file names and whether they are enabled. Neither gives both in one call. The solution: call both, join on service name, merge into one object. It works, it is just two calls instead of one.

### `Get-ComputerInfo` from `/proc`

`Get-ComputerInfo` on Windows returns a rich object with OS version, hardware info, BIOS info, etc. On Linux, all of this lives in different places: `/proc/version` for OS info, `/proc/cpuinfo` for CPU, `/proc/meminfo` for RAM, `/etc/os-release` for distro details. Assembling it all into one object that resembles the Windows output required reading from about six different files. The result is a `PSCustomObject` that covers the properties scripts actually use: `OsName`, `OsVersion`, `CsName`, `TotalPhysicalMemory`, `CsProcessors`.

### Elevation check

`Rename-Computer` requires elevated privileges on Linux. Rather than letting the underlying command fail with a cryptic error, we check `id -u` first and throw a clear "must be run as root" error. This pattern was then applied to any other cmdlet that modifies system state.

---

## NetTCPIP.Linux

**What it is**: IP address enumeration, routing table, TCP connections. The four most-used cmdlets from the Windows `NetTCPIP` module.

**Implemented**: `Get-NetIPAddress`, `Get-NetIPConfiguration`, `Get-NetRoute`, `Get-NetTCPConnection`. 30 stubs.

**Full details**: [NetTCPIP.Linux README](https://github.com/peppekerstens/NetTCPIP.Linux#how-we-built-this)

### `ip -json` for structured output

`ip -json addr show` and `ip -json route show` return proper JSON. No text parsing needed. This is the big advantage of `iproute2` over older tools like `ifconfig` — structured output has been there since version 4.12 (2017). `Get-NetIPAddress`, `Get-NetRoute`, and `Get-NetIPConfiguration` all use this.

### LISTEN sockets have a wildcard remote address

`ss -tnap` for listening sockets shows the remote address column as `0.0.0.0:*` or `[::]:*`. The `*` is not a valid port number. Any code that tries to extract a port with a "digits only" regex on that field will silently fail — or worse, return `0` for all ports including established connections. The fix: detect the wildcard pattern explicitly and return `0` for the port rather than trying to parse it.

### Loop variable shadowing

Inside `Get-NetTCPConnection`, the pipeline loop originally used `$localPort` as the loop variable — same name as the `-LocalPort` parameter. Inside the loop body, `$localPort` resolved to the current iteration value, not the parameter. The filter always matched (or never matched, depending on data). Renamed to `$_localPort` / `$_remotePort`. This is a classic PowerShell trap: parameter names and variable names in the same scope are the same namespace.

### `Get-NetRoute` needs two calls

`ip -json route show` returns IPv4 routes only. IPv6 requires `ip -6 -json route show`. The `default` route entry has no destination prefix — it maps to `0.0.0.0/0` for IPv4 and `::/0` for IPv6. Both result sets are merged and returned together.

---

## Update.Linux

**What it is**: Package update management, mimicking PSWindowsUpdate. `Get-WindowsUpdate` lists available apt updates, `Install-WindowsUpdate` runs `apt-get upgrade`, `Get-WUHistory` reads `/var/log/dpkg.log`.

**Implemented**: 3 cmdlets with PSWindowsUpdate aliases. 16 stubs.

**Full details**: [Update.Linux README](https://github.com/peppekerstens/Update.Linux#how-we-built-this)

### The "Listing..." header line

`apt list --upgradable 2>/dev/null` always emits a `Listing...` progress line before the package data. If you pipe straight into the parser, your first object is broken. One `Where-Object { $_ -notmatch '^Listing' }` fixes it. The type of thing you only discover by actually running the command and looking at what comes out.

### dpkg.log action verbs

dpkg.log uses `install`, `upgrade`, `remove`, `purge`, and `configure` as action words. `configure` is a post-install step that appears for every installed package. If you include it in history output, every install shows up twice. Filter for `install` and `upgrade` only.

### PSWindowsUpdate alias naming

PSWindowsUpdate is not fully consistent in its naming — some cmdlets use `Get-Windows*`, some use `Get-WU*`. The alias table covers both patterns. `Get-WindowsUpdate` → `Get-LinuxUpdate`, `Get-WUHistory` → `Get-LinuxUpdateHistory`, etc.

---

## PowerShell.Security.Linux

**What it is**: File ACL management. `Get-Acl` returns file permissions as a structured object. `Set-Acl` applies permissions.

**Implemented**: `Get-LinuxAcl` / `Get-Acl`, `Set-LinuxAcl` / `Set-Acl`. Stubs for Authenticode and catalog functions.

**Full details**: [PowerShell.Security.Linux README](https://github.com/peppekerstens/PowerShell.Security.Linux#how-we-built-this)

### `stat` vs `getfacl`

`stat --format='%a|%A|%U|%G|%F|%n'` is universally available — no optional packages needed. It gives octal mode, symbolic mode, owner, group, file type, and filename in one call. `getfacl` adds extended named-user and named-group ACL entries, but requires the `acl` package to be installed. The module uses `stat` as baseline and enriches with `getfacl` if it is present. Works on a minimal install, gets richer if the tools are there.

### PSPath provider prefix

`Get-ChildItem` output objects carry a `PSPath` property formatted as `Microsoft.PowerShell.Core\FileSystem::/etc/hosts`. If you naively pass this to `stat`, it fails — `stat` wants a real filesystem path. The fix: strip the provider prefix before handing anything to a Linux tool. This surfaced during pipeline input testing — `Get-ChildItem /etc | Get-LinuxAcl` — and only when piping, not when passing a literal path. Easy fix, frustrating to track down.

### POSIX → Windows FileSystemRights mapping

The `Access` entries return a `FileSystemRights` property with Windows-style labels: `FullControl`, `Modify`, `ReadAndExecute`, `Read`, `WriteAndExecute`, `Write`, `ExecuteFile`, `None`. These map from the three-character POSIX permission strings (`rwx`, `rw-`, etc.). It is an approximation — the two ACL models are not equivalent — but close enough for the scripts that actually use these properties.

---

## PowerShell.LocalAccounts.Linux

**What it is**: All 15 cmdlets from `Microsoft.PowerShell.LocalAccounts` implemented on Linux. `Get-LocalUser`, `New-LocalUser`, `Set-LocalUser`, `Enable-LocalUser`, `Disable-LocalUser`, `Remove-LocalUser`, and the same for groups plus membership management.

**Implemented**: All 15. No stubs needed — the Linux tools exist for everything.

**Full details**: [PowerShell.LocalAccounts.Linux README](https://github.com/peppekerstens/PowerShell.LocalAccounts.Linux#how-we-built-this)

### No renaming

Unlike other modules, this one exports the Windows cmdlet names directly. `Get-LocalUser`, `New-LocalGroup`, etc. — no "Linux" prefix, no aliases. The nouns (`LocalUser`, `LocalGroup`) are platform-neutral concepts. Renaming them would add noise without adding clarity.

### `getent passwd` + `passwd -S` + `chage -l`

`Get-LocalUser` assembles its output from three sources. `getent passwd` provides the basic user entry: name, UID, GID, home directory, shell, GECOS field. `passwd -S` provides password status (locked, unlocked, no password). `chage -l` provides expiry information: last password change, expiry date, account expiry. Three commands, one user object. On systems where `passwd -S` requires root, the module catches permission errors and defaults `Enabled` to `$true` with a warning.

### Primary-group members in `Get-LocalGroupMember`

Linux `/etc/group` only lists a user's supplementary group memberships — not their primary group. If user `alice` has primary GID 1000 (group `alice`), she is not listed in the `alice` group's member list in `/etc/group`. `Get-LocalGroupMember` needs to also check each user's primary GID and include them if it matches. Without this, `Get-LocalGroupMember alice` returns no one, which is wrong.

### `Set-LocalGroup` is a no-op

Linux groups have no description field. `Set-LocalGroup -Description "something"` cannot do anything meaningful. The implementation validates the group exists, emits a warning if `-Description` was passed, and returns without error. This is correct behavior for cross-platform script compatibility — you want a warning, not an exception that breaks the script.

---

## ScheduledTasks.Linux

**What it is**: 13 of the 15 Windows `ScheduledTasks` cmdlets, implemented via systemd timer units. Create, list, query, start, stop, enable, disable, and remove scheduled tasks.

**Implemented**: 13 cmdlets. 2 stubs (`Set-ScheduledTask`, `Export-ScheduledTask`).

**Full details**: [ScheduledTasks.Linux README](https://github.com/peppekerstens/ScheduledTasks.Linux#how-we-built-this)

### Why systemd timers, not cron

Cron was the obvious answer. We chose systemd timers because they integrate with `systemctl` — which means `Start-ScheduledTask`, `Stop-ScheduledTask`, `Enable-ScheduledTask`, and `Disable-ScheduledTask` all map directly to `systemctl start/stop/enable/disable`. Cron has no equivalent lifecycle management. Systemd also gives you `systemctl list-timers` for structured status output and `journald` for logging. Cron gives you... a file and maybe an email.

### Timer + service unit pair

Each task creates two files: a `.timer` unit with the schedule (`OnCalendar=` or `OnBootSec=`) and a `.service` unit with the command to run. They share the same base name. `Register-ScheduledTask` writes both, runs `systemctl daemon-reload`, and enables the timer. `Unregister-ScheduledTask` disables the timer and deletes both files.

### User vs system scope

System tasks go to `/etc/systemd/system/` and need `sudo`. User tasks go to `~/.config/systemd/user/`. The module uses `id -u` to determine scope when no explicit `TaskPath` is provided: running as root defaults to system scope, otherwise user scope. The `TaskPath = '\'` convention from Windows (root task folder) also maps to system scope.

### Multiple actions not supported

Windows tasks can have multiple `Action` objects. systemd service units have one `ExecStart`. If multiple actions are passed, only the first is used and a warning is emitted. This is a documented limitation, not a silent one.

---

## Coverage analysis

After building all seven modules, I went back to Evgenij Smirnov's list from the 2025 Summit — the gap analysis of cmdlets missing from PS7.5 on Linux. The good news: PS7.5 provides exactly zero of the gap cmdlets natively on Linux. All seven modules fill real gaps, not redundant ones.

The next priorities on the list — things that could reasonably become part 9:

- **PKI.Linux** — wrapping `openssl` for certificate management (`Get-PfxCertificate`, `Get-Certificate`, etc.)
- **PrintManagement.Linux** — wrapping CUPS for print queue management
- **DnsClient.Linux** — wrapping `resolvectl` / `dig` for DNS queries

But honestly, seven modules is a solid chunk of the list closed. The goal was always to close the gap, not to close it all at once.

---

All seven module repositories are at [github.com/peppekerstens](https://github.com/peppekerstens). Pull requests welcome — particularly for the many stubs that still need implementing.
