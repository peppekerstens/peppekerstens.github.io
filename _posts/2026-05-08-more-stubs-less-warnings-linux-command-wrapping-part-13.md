---
date: 2026-05-08  -0000
title: More stubs, less warnings - Linux Command Wrapping Part 13
toc: true
---

Part 12 ended with a to-do list. Stage 3 was going to be the "implement the remaining stubs" stage - turn those `Write-Warning "not yet implemented"` placeholders into something that actually runs. It also included two new modules from scratch: `SmbShare.Linux` and `PackageManagement.Linux`.

Here is what happened, and where it went sideways.

## What was on the list

The stubs that looked genuinely implementable going in:

- `Find-NetRoute`, `Get-NetNeighbor`, `Get-NetIPInterface`, `Test-NetConnection` and a few more - all `ip`-backed, same tool NetTCPIP.Linux already used
- `Get-PrintConfiguration`, `Set-Printer`, `Rename-Printer` and a handful more - CUPS via `lpoptions` and `lpadmin`
- `New-Service`, `Remove-Service`, `Set-TimeZone` - systemd unit file creation and `timedatectl`
- `Get-DiskImage`, `Clear-Disk`, `Format-Volume`, `New-Partition` and the rest of the storage write path - `losetup`, `wipefs`, `mkfs`, `sfdisk`, `fsck`

Plus two new modules built from nothing.

## The storage batch - where gotchas live

The storage cmdlets looked straightforward on paper. `Clear-Disk` is `wipefs -a`. `Repair-Volume` is `fsck`. `Format-Volume` is `mkfs.*` with a switch on filesystem type.

Two PSSA issues caught me before the tests did, and both were a bit embarrassing.

First: `$args` is an automatic variable in PowerShell. You cannot assign to it. I had written `$args = @('mkfs.ext4')` to build the mkfs argument list. PSSA flags this as `PSAvoidAssignmentToAutomaticVariable`. The fix is obvious - rename to `$mkfsArgs` - but it is the kind of thing you do not think about until the linter tells you. I have been writing PowerShell for years and I still typed `$args =` without blinking.

Second: PowerShell string interpolation treats `${sizeK}K` as a drive expression when `sizeK` looks like a drive letter to the parser. PSSA raises `InvalidVariableReferenceWithDrive`. The fix is string concatenation instead: `$partNumStr + ': ,' + $sizeSpec`. Inelegant, but clean.

`Dismount-DiskImage` had a subtler problem. The function needs to look up the loop device for a given image path before it can detach it - which means calling `losetup -j <imagepath>` first. Fine, except that lookup fires before `ShouldProcess`. So a test calling `Dismount-DiskImage -ImagePath '/tmp/test.img' -WhatIf` would throw "'/tmp/test.img' is not attached as a loop device" before the `What if:` line ever printed. The fix: check `$WhatIfPreference` at the top of the ImagePath branch and skip the losetup lookup entirely, going straight to `ShouldProcess` with the image path as the target.

`Get-DiskImage` had another one. When there are no loop devices, `losetup -l --json` returns `{"loopdevices":[]}` - an empty array, not null. But `foreach ($dev in $data)` over an empty array produces `$null` in a `$results = foreach...` assignment, not `@()`. The test captured output and tried `$result.GetType().IsArray`, which fails on null. Fix: wrap the foreach in `@(...)` to force array semantics regardless of item count. Not the last time I will make that mistake.

## PrintManagement - CUPS is not in WSL2

CUPS is entirely absent from the default Ubuntu WSL2 installation. `lpstat`, `lpoptions`, `lpadmin` - none of them exist on the dev machine.

So what do you test when the tool is not there? I settled on: test the error path, and test WhatIf. If `lpoptions` is not found, `Get-PrintConfiguration` should emit an error - test that. If `lpadmin` is not found, `Set-Printer` should emit an error - test that. For functions with `SupportsShouldProcess`, the WhatIf path does not touch the tool at all - `ShouldProcess` is called before any invocation - so those tests run everywhere.

The previous stub tests expected a `Write-Warning` from each function. All of those had to go.

`Rename-Printer` deserves its own note. CUPS has no rename operation. The implementation emulates it by copying the device URI to a new queue via `lpadmin -p <newname> -v <deviceuri> -E` and then deleting the old queue with `lpadmin -x <oldname>`. This loses the PPD and per-printer option defaults. The synopsis documents this honestly. It is the best available approximation on Linux - the alternative is an error that just says "not supported," which is less useful.

## The two new modules

`PackageManagement.Linux` wraps three package managers: `apt`/`apt-cache`/`dpkg-query` for Debian/Ubuntu, `dnf`/`rpm` for RHEL/Fedora, `zypper` for openSUSE. Auto-detection picks the right one at runtime. Call `Get-Package` on Ubuntu and it finds `dpkg-query`. Same function, different distro, same output shape. That is the point.

One thing that bit me: the built-in `PackageManagement` module is available on Linux and exports its own `Get-Package`. When both modules are loaded, there is a name resolution conflict. `PackageManagement.Linux\Get-Package` works fine when called with the module qualifier, but a test that called `Get-Package` without qualification got confused in some Pester contexts depending on import order. The fix was mundane: make the test call it in a way that does not depend on resolution order. The underlying conflict is real, though. Worth documenting.

`SmbShare.Linux` is more constrained. Samba is not installed in WSL2. Neither is `nfsstat`. `Get-SmbConnection` wraps `smbstatus -b` - which means on most development machines, the integration tests will skip. `Get-NfsSession` tries `/proc/net/rpc/nfs` first (kernel-provided, no tools needed) and falls back to `nfsstat` if the proc file is absent. In WSL2, both are absent, so it errors cleanly.

`Get-NfsClientConfiguration` reads `/etc/nfs.conf` and `/etc/fstab`. Those files exist on any Linux system. The `/etc/fstab` parsing only picks up NFS-type entries, so on a vanilla WSL2 system it returns an empty array - not an error. An empty result is a valid answer. An error means something went wrong. There is a difference, and it matters.

## Update.Linux - what is actually implementable vs. what never will be

Update.Linux already had three real implementations from Stage 1. The remaining 19 were stubs. Looking at the stub list honestly, five of them have sensible Linux equivalents:

- `Get-WURebootStatus` - check `/var/run/reboot-required` and `/var/run/reboot-required.pkgs`. Debian/Ubuntu writes these files after any package operation that needs a reboot.
- `Get-WULastResults` - parse `/var/log/apt/history.log` for the last operation's dates, commandline, installed and upgraded packages.
- `Hide-LinuxUpdate` - `apt-mark hold <package>`. Pin a package.
- `Show-LinuxUpdate` - `apt-mark unhold <package>`. Undo a hold.
- `Remove-LinuxUpdate` - `apt-get remove`, with optional `--purge`.

The other fourteen - `Add-WUServiceManager`, `Get-WUApiVersion`, `Reset-WUComponents`, `Invoke-WUJob` and so on - are Windows Update Agent concepts. There is no Linux equivalent of the Windows Update Agent. These are not stubs waiting to be implemented; they are stubs that accurately describe the situation. That is a useful distinction. Both look the same from the outside (`Write-Warning "not yet implemented"`) but represent completely different things. The Windows-only ones should probably say so more explicitly - "This cmdlet requires the Windows Update Agent, which has no Linux equivalent" rather than a generic placeholder.

## Numbers

| Module | Version | Tests |
|---|---|---|
| Storage.Linux | v0.6.0 | 489 pass |
| PrintManagement.Linux | v0.2.0 | 18 pass, 16 skip (no CUPS) |
| Update.Linux | v0.3.0 | 116 pass |
| PackageManagement.Linux | v0.1.0 | 16 pass, 1 skip |
| SmbShare.Linux | v0.1.0 | 8 pass, 4 skip (no Samba/NFS) |

All at 0 PSSA issues, 0 failures.

## One thing that keeps coming up

Tests that run in WSL2 have a persistent friction: some tools are not installed. CUPS, Samba, NFS tools - all absent from the default Ubuntu image. The skip-with-condition pattern works, but it means a significant portion of the test suite is always skipped on the development machine. You push code, see 16 skipped, and have to remember whether that is expected or a sign of something broken.

That is the motivation for Stage 4: a proper multi-distro test matrix. GitHub Actions running the tests inside containers that actually have CUPS, Samba, NFS tools installed. The skips become real test runs. The gap between "passes on my machine" and "actually works" closes.

## Next

Stage 4. Infrastructure. Dockerfiles. CI workflows. Container images at `ghcr.io/peppekerstens/`. One per distro, each with PowerShell and Pester pre-installed and the relevant Linux tools actually present. Then `.github/workflows/pester.yml` in each module repo, running the full test suite against the matrix.

The goal: every module tested on five distros on every push. Any skip that fires because a tool is missing from the container is a gap to fill, not a condition to accept.




