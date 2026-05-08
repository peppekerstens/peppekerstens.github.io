---
title: PowerShell.LocalAccounts.Linux - Local User Management - Linux Command Wrapping Part 13
toc: true
---

This one turned out simpler than most of the other modules. Not because local user management is trivial — it is not — but because the Linux tooling is consistent, well-documented, and all 15 cmdlets in `Microsoft.PowerShell.LocalAccounts` have a viable Linux equivalent. No stubs. No gaps. Everything implemented.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## Why LocalAccounts

`Microsoft.PowerShell.LocalAccounts` manages local users and groups — accounts that live on the machine rather than in Active Directory or LDAP. On Linux, the same concept exists: `/etc/passwd`, `/etc/group`, and the tools that manage them (`useradd`, `usermod`, `groupadd`, etc.) have been around since forever.

The module is 15 cmdlets. On a Windows machine managed with PowerShell, scripts commonly use `Get-LocalUser`, `New-LocalUser`, `Add-LocalGroupMember`, `Disable-LocalUser`. On a Linux box, the same operations are done with `useradd -m alice`, `usermod -aG sudo alice`, `usermod -L alice` — if you happen to know those. If you are coming from a Windows-first background, you probably do not.

So the goal is the same as the rest of this series: write the script once, run it on both platforms.

## What maps to what

| Cmdlet | Linux tool |
|---|---|
| `Get-LocalUser` | `getent passwd`, `passwd -S`, `chage -l` |
| `Get-LocalGroup` | `getent group` |
| `Get-LocalGroupMember` | `getent group`, `getent passwd` |
| `New-LocalUser` | `useradd`, `chpasswd` |
| `New-LocalGroup` | `groupadd` |
| `Set-LocalUser` | `usermod`, `chage`, `chpasswd` |
| `Set-LocalGroup` | — (see below) |
| `Enable-LocalUser` | `usermod -U` |
| `Disable-LocalUser` | `usermod -L` |
| `Remove-LocalUser` | `userdel` |
| `Remove-LocalGroup` | `groupdel` |
| `Add-LocalGroupMember` | `usermod -aG` |
| `Remove-LocalGroupMember` | `gpasswd -d` |
| `Rename-LocalUser` | `usermod -l` |
| `Rename-LocalGroup` | `groupmod -n` |

Unlike the Storage module (161 cmdlets, 4 implemented, 157 stubs), every cmdlet here does something real. That felt good.

## Naming decision — no aliases this time

Most other modules in this series use Linux-prefixed function names (`Get-LinuxAcl`, `Get-LinuxUpdate`) and export the Windows name as an alias. For this module I went the other way: the function names are identical to Windows.

The reason is that `LocalUser`, `LocalGroup`, and `LocalGroupMember` are already platform-neutral nouns. They do not say "Windows". `Get-LocalUser` on Linux doing exactly what `Get-LocalUser` on Windows does is not confusing — it is the whole point. There is no alias layer needed.

## Implementing Get-LocalUser

`getent passwd` returns all user accounts, including system accounts. Each line is colon-delimited:

```
root:x:0:0:root:/root:/bin/bash
peppe:x:1000:1000:Peppe Kerstens,,,:/home/peppe:/bin/bash
```

Fields: `username:password:uid:gid:gecos:home:shell`. The password field is always `x` (shadow passwords). The GECOS field is a comma-separated list where the first entry is the full name.

Password status and account lock state require a separate call to `passwd -S`:

```
peppe P 2026-01-15 0 99999 7 -1
```

The second field is the status: `P` (has password), `NP` (no password), `L` or `LK` (locked). That maps directly to `Enabled`.

Password expiry comes from `chage -l`:

```
Last password change                              : Jan 15, 2026
Password expires                                  : never
```

Parsing `chage -l` is slightly annoying because the date format varies by locale, but `[datetime]::Parse` handles most of it. `never` becomes `$null`.

The output object mirrors the Windows `Get-LocalUser` shape: `Name`, `FullName`, `Description`, `Enabled`, `PasswordRequired`, `PasswordExpires`, `PasswordLastSet`, `AccountExpires`, `HomeDirectory`, `Shell`, `UID`, `GID`. SID is `$null` — Linux has no SIDs.

## Implementing Get-LocalGroupMember

This one required a bit of thought. On Linux, group membership comes in two forms:

1. **Explicit members** — listed in the fourth field of `/etc/group`: `sudo:x:27:alice,bob`
2. **Primary group members** — users whose primary GID (field 4 of `/etc/passwd`) matches the group's GID

The Windows `Get-LocalGroupMember` includes both. `id alice` will show both the primary group and supplementary groups. So the implementation calls `getent group` for explicit members, then walks `getent passwd` to find users whose primary GID matches:

```powershell
$primaryMembers = & getent passwd 2>/dev/null |
    ForEach-Object {
        $f = $_ -split ':'
        if ($f.Count -ge 4 -and [int]$f[3] -eq $gid) { $f[0] }
    }

$allMembers = ($members + $primaryMembers) | Sort-Object -Unique
```

## The Set-LocalGroup gap

Linux groups genuinely do not have a description field. There is no equivalent of the Windows group description stored anywhere. `Set-LocalGroup -Name developers -Description 'Development team'` has no Linux backing.

The implementation validates the group exists, emits a `Write-Warning` if `Description` is passed, and does nothing. This is the honest thing to do — better than silently discarding input, and better than throwing an error that breaks a cross-platform script.

## Write operations and permissions

Every write cmdlet wraps its destructive call in `SupportsShouldProcess`, so `-WhatIf` and `-Confirm` work:

```powershell
New-LocalUser -Name alice -FullName 'Alice Smith' -WhatIf
# What if: Performing the operation "New-LocalUser" on target "alice".

Remove-LocalUser -Name alice -RemoveHome -Confirm
# Are you sure you want to perform this action?
# Performing the operation "Remove-LocalUser" on target "alice".
```

Most operations require `root` or `sudo`. The module does not escalate privileges — it calls the underlying tool directly and lets the exit code speak for itself. If `useradd` fails because you do not have permission, `$LASTEXITCODE` will be non-zero and a `Write-Error` follows.

## Test results

| Environment | Passed | Skipped | Failed |
|---|---|---|---|
| Windows (Pester 5.3.3) | 10 | 61 | 0 |
| WSL2 Ubuntu (Pester 5.7.1) | 70 | 1 | 0 |

The 61 skipped on Windows are the Linux-execution tests. The 1 skipped on WSL2 is the Linux-only guard test (which only makes sense to run on Windows). Everything else runs and passes.

One thing that caught me during test development: `$script:` variables set in `BeforeDiscovery` are not reliably available in `It` blocks in all Pester 5.x versions. The workaround is to set path variables in `BeforeAll` instead, where `$PSScriptRoot` is guaranteed to be populated. This is now standard practice across all modules in this series and is documented in the [series plan](https://github.com/peppekerstens/opencode).

## Example scripts

Four examples in the `Examples\` folder:

- **`Get-LocalUsers.ps1`** — table of all users with name, enabled state, UID, shell, home
- **`Get-LocalGroups.ps1`** — all groups with GID and comma-separated member list
- **`Get-UserGroupMembership.ps1`** — per-user group membership audit
- **`Get-DisabledUsers.ps1`** — find locked accounts

All four run on both platforms: on Windows they import `Microsoft.PowerShell.LocalAccounts`, on Linux they import this module.

## Repository

[https://github.com/peppekerstens/PowerShell.LocalAccounts.Linux](https://github.com/peppekerstens/PowerShell.LocalAccounts.Linux) — v0.1.0

## Next

`ScheduledTasks.Linux` — wrapping `cron` and `systemd` timers as `Get-ScheduledTask`, `Register-ScheduledTask`, and friends.
