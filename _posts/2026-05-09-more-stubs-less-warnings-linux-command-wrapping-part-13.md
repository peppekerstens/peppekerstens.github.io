---
title: More stubs, less warnings — Linux Command Wrapping Part 13
toc: true
---

Part 12 ended with a to-do list. Stage 3 was going to be the "implement the remaining stubs" stage — turn those `Write-Warning "not yet implemented"` placeholders into something that actually runs. It also included two new modules from scratch: `SmbShare.Linux` and `PackageManagement.Linux`.

Here is what happened.

## What was on the list

The stubs that were genuinely implementable, as noted at the end of Part 12:

- `Find-NetRoute`, `Get-NetNeighbor`, `Get-NetIPInterface`, `Test-NetConnection`, `Get-NetIPv4Protocol`, `Get-NetIPv6Protocol` — all `ip`-backed, same tool that NetTCPIP.Linux already used
- `Get-PrintConfiguration`, `Get-PrinterProperty`, `Set-PrintConfiguration`, `Set-Printer`, `Set-PrinterProperty`, `Rename-Printer` — CUPS via `lpoptions` and `lpadmin`
- `New-Service`, `Remove-Service`, `Set-TimeZone` — systemd unit file creation and `timedatectl`
- `Export-ScheduledTask` — `systemctl cat`
- `Get-DiskImage`, `Dismount-DiskImage`, `Clear-Disk`, `Format-Volume`, `New-Partition`, `Remove-Partition`, `Resize-Partition`, `Repair-Volume` — storage tools (`losetup`, `wipefs`, `mkfs`, `sfdisk`, `fsck`)

And then separately: two new modules built from nothing.

## The storage batch — where gotchas live

The storage cmdlets looked straightforward. `Clear-Disk` is just `wipefs -a`. `Repair-Volume` is just `fsck`. `Format-Volume` maps to `mkfs.*` with a switch on filesystem type.

Two PSSA issues caught me before the tests did.

The first: `$args` is an automatic variable in PowerShell. You cannot assign to it. I had written `$args = @('mkfs.ext4')` to build the mkfs argument list, which PSSA flags as `PSAvoidAssignmentToAutomaticVariable`. The fix is obvious — rename to `$mkfsArgs` — but it is the kind of thing you do not think about until the linter tells you.

The second: PowerShell string interpolation treats `${sizeK}K` as `${sizeK}` followed by the literal character `K` inside a drive expression. When `sizeK` looks like a drive letter to the parser, PSSA raises `InvalidVariableReferenceWithDrive`. The fix is string concatenation instead of interpolation: `$partNumStr + ': ,' + $sizeSpec`. Inelegant, but clean.

`Dismount-DiskImage` had a subtler problem. The function needed to look up the loop device for a given image path before it could detach it — which meant calling `losetup -j <imagepath>` first. Fine, except that lookup fires before `ShouldProcess`. So a test calling `Dismount-DiskImage -ImagePath '/tmp/test.img' -WhatIf` would throw `'/tmp/test.img' is not attached as a loop device` before the `What if:` line ever printed. The fix: check `$WhatIfPreference` at the top of the ImagePath branch and skip the losetup lookup entirely, going straight to `ShouldProcess` with the image path as the target.

`Get-DiskImage` had a different issue. When there are no loop devices, `losetup -l --json` returns `{"loopdevices":[]}` — an empty array, not null. But `foreach ($dev in $data)` over an empty array produces `$null` in a `$results = foreach...` assignment, not `@()`. The test captured `Get-DiskImage` output and tried to check `$result.GetType().IsArray`, which fails on null. The fix: wrap the foreach in `@(...)` to force array semantics regardless of item count.

Both issues were in the tests, not the functions. Or rather, both were in the interface between "what the function returns" and "what the test expected," which is a distinction that does not matter much in practice.

## PrintManagement — CUPS is not in WSL2

CUPS is entirely absent from the default Ubuntu WSL2 installation. `lpstat`, `lpoptions`, `lpadmin` — none of them exist.

This creates a real question: what do you test when the tool is not there?

The answer I settled on: test the error path, and test WhatIf. If `lpoptions` is not found, `Get-PrintConfiguration` should emit an error — test that. If `lpadmin` is not found, `Set-Printer` should emit an error — test that. For functions with `SupportsShouldProcess`, the `WhatIf` path does not need the tool at all — the `ShouldProcess` call happens before any tool invocation — so those tests run everywhere.

The previous stub tests expected a `Write-Warning` from each function. Those had to go, replaced with the error-path and WhatIf tests above.

`Rename-Printer` deserves a specific note. CUPS has no rename operation. The implementation emulates it by copying the device URI to a new queue via `lpadmin -p <newname> -v <deviceuri> -E` and then deleting the old one with `lpadmin -x <oldname>`. This loses the PPD and per-printer option defaults. The synopsis documents this honestly. It is the best available approximation on Linux.

## The two new modules

`PackageManagement.Linux` and `SmbShare.Linux` were both built from scratch.

`PackageManagement.Linux` wraps three package managers — `apt`/`apt-cache`/`dpkg-query` for Debian/Ubuntu, `dnf`/`rpm` for RHEL/Fedora, `zypper` for openSUSE — with auto-detection. Call `Get-Package` without `-ProviderName` on an Ubuntu system and it will find `dpkg-query`, use it, and return results. Same function, different distro, different tool, same output shape. That is the point.

One thing that bit me: the built-in `PackageManagement` module is available on Linux and exports its own `Get-Package`. When both modules are loaded, there is a resolution conflict. `PackageManagement.Linux\Get-Package` works fine when called with the module qualifier, and in the Pester session the import order should make ours win — but a test that called `Get-Package` without qualification got confused in some Pester contexts. The fix was mundane: make the test call the function in a way that does not depend on resolution order. The underlying conflict is real and worth documenting.

`SmbShare.Linux` is more constrained. Samba is not installed in WSL2. Neither is `nfsstat`. `Get-SmbConnection` wraps `smbstatus -b` — which means on most development machines, the integration tests will skip. `Get-NfsSession` tries `/proc/net/rpc/nfs` first (kernel-provided, no tools needed) and falls back to `nfsstat` if the proc file is absent. In WSL2, both are absent, so it errors cleanly.

`Get-NfsClientConfiguration` reads `/etc/nfs.conf` and `/etc/fstab`. Those files exist on any Linux system. The `/etc/fstab` parsing only picks up NFS-type entries (`nfs`, `nfs4`), so on a vanilla WSL2 system it returns an empty array — not an error. There is a difference. An empty result is a valid answer. An error means something went wrong.

## Update.Linux — what is actually implementable

Update.Linux already had three real implementations: `Get-LinuxUpdate` (apt list --upgradable), `Install-LinuxUpdate` (apt-get upgrade), `Get-LinuxUpdateHistory` (dpkg.log parsing). The remaining 19 were stubs.

Looking at the stub list honestly, five of them have sensible Linux equivalents:

- `Get-WURebootStatus` — check `/var/run/reboot-required` and `/var/run/reboot-required.pkgs`. Debian/Ubuntu writes these files after any package operation that requires a reboot. One line to check, one line to read.
- `Get-WULastResults` — parse `/var/log/apt/history.log` for the last operation's `Start-Date`, `End-Date`, `Commandline`, `Install`, and `Upgrade` fields.
- `Hide-LinuxUpdate` — `apt-mark hold <package>`. Pin a package at its current version.
- `Show-LinuxUpdate` — `apt-mark unhold <package>`. Undo a hold.
- `Remove-LinuxUpdate` — `apt-get remove` with an optional `--purge` for configuration files.

The other fourteen — `Add-WUServiceManager`, `Get-WUApiVersion`, `Reset-WUComponents`, `Invoke-WUJob`, and so on — are Windows Update Agent concepts. There is no Linux equivalent of the Windows Update Agent. These are not stubs waiting to be implemented; they are stubs that accurately describe the situation.

That is a useful distinction. Some stubs are "not yet done." Others are "not applicable." Both look the same from the outside (`Write-Warning "not yet implemented"`) but represent different things. The Windows-only ones should probably say so more explicitly in their descriptions — "This cmdlet requires the Windows Update Agent, which has no Linux equivalent" rather than "Contributions welcome."

## Numbers

| Module | Version | Tests |
|---|---|---|
| Storage.Linux | v0.6.0 | 489 pass |
| PrintManagement.Linux | v0.2.0 | 18 pass, 16 skip (no CUPS) |
| NetTCPIP.Linux | — | already done in earlier sessions |
| DnsClient.Linux | — | already done in earlier sessions |
| PowerShell.Management.Linux | — | already done in earlier sessions |
| ScheduledTasks.Linux | — | already done in earlier sessions |
| Update.Linux | v0.3.0 | 116 pass |
| PackageManagement.Linux | v0.1.0 | 16 pass, 1 skip |
| SmbShare.Linux | v0.1.0 | 8 pass, 4 skip (no Samba/NFS) |

All at 0 PSSA issues, 0 failures.

## One thing that keeps coming up

Tests that run in WSL2 have a persistent friction: some tools are not installed. CUPS, Samba, NFS tools — all absent from the default Ubuntu image. The skip-with-condition pattern (`-Skip:(-not (Get-Command lpstat -ErrorAction SilentlyContinue))`) works, but it means a significant portion of the test suite is always skipped on the development machine. You push code, see 16 skipped, and have to remember whether that is expected or a sign of a problem.

This is the motivation for Stage 4: a proper multi-distro test matrix. GitHub Actions running the tests inside containers that actually have CUPS, Samba, NFS tools installed. That way the skips become real test runs, and the gap between "passes on my machine" and "actually works" closes a bit.

Stage 4 involves Docker, GitHub Actions workflows, and pre-built container images per distro. That is a different kind of work from what has been done so far — less "write the function," more "wire the infrastructure." Whether that is more or less interesting probably depends on the day.

## Next

Stage 4. Infrastructure. Dockerfiles. CI workflows. Container images at `ghcr.io/peppekerstens/`. One per distro (Ubuntu, Debian, Fedora, openSUSE, Arch), each with PowerShell and Pester pre-installed. Then `.github/workflows/pester.yml` in each module repo, running the full test suite against the matrix.

The goal: every module tested on five distros on every push. Any skip that fires because a tool is missing from the container image is a gap to fill, not a condition to accept.
