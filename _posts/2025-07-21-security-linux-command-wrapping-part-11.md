---
title: PowerShell.Security.Linux - Get-Acl and Set-Acl on Linux - Linux Command Wrapping Part 11
toc: true
---

Part 10 wrapped `apt` as a peer for PSWindowsUpdate. Part 11 tackles **file system permissions** — specifically `Get-Acl` and `Set-Acl` from `Microsoft.PowerShell.Security`, implemented as `Get-LinuxAcl` and `Set-LinuxAcl` in a new module: `PowerShell.Security.Linux`.

## Command wrapping series

This article is part of a series on command wrapping for Linux. The goal is to expand the list of common cmdlets being supported on the Linux platform. Inspired by a call to action from Evgenij Smirnov during the [2025 European PowerShell Summit](https://www.youtube.com/watch?v=RlzinWYIjBY).

## The security gap on Linux

On Windows, `Get-Acl` and `Set-Acl` are workhorses. They read and write the security descriptor (Access Control List) of any file, directory, registry key, or service. On Linux, PowerShell 7's `Microsoft.PowerShell.Security` module is present but stripped:

```powershell
Get-Command -Module Microsoft.PowerShell.Security
```

The Linux version exports only: `ConvertFrom-SecureString`, `ConvertTo-SecureString`, `Get-Credential`, `Get-ExecutionPolicy`, `Set-ExecutionPolicy`, and a few CMS cmdlets. `Get-Acl` and `Set-Acl` do **not exist**. The same is true for `Get-AuthenticodeSignature`, `Set-AuthenticodeSignature`, `New-FileCatalog`, and `Test-FileCatalog` — all code-signing and catalog functions are Windows-only.

```powershell
# On Linux PS7:
Get-Acl /etc/hosts       # CommandNotFoundException
Set-Acl /tmp/test -AclObject $acl  # CommandNotFoundException
```

Any cross-platform script that reads or sets permissions needs a Linux alternative.

## What gets mapped

`Microsoft.PowerShell.Security` exports these cmdlets relevant to file system permissions and code signing:

| Cmdlet | Status | Linux tool |
|---|---|---|
| `Get-Acl` → `Get-LinuxAcl` | ✅ Implemented | `stat`, optional `getfacl` |
| `Set-Acl` → `Set-LinuxAcl` | ✅ Implemented | `chmod`, `chown`, optional `setfacl` |
| `Get-AuthenticodeSignature` | 🔧 Stub | — |
| `Set-AuthenticodeSignature` | 🔧 Stub | — |
| `New-FileCatalog` | 🔧 Stub | — |
| `Test-FileCatalog` | 🔧 Stub | — |

Authenticode signatures and catalog files are Windows-specific concepts. They will remain stubs unless a meaningful Linux equivalent (e.g. GPG signatures) is contributed.

## Choosing the Linux tool: stat vs getfacl

The obvious choice for reading file ACLs on Linux is `getfacl`. It exposes full POSIX extended ACL entries. The problem: `getfacl` is not installed by default on most distributions. It lives in the `acl` package:

```bash
sudo apt install acl
```

On a minimal server or CI image, `acl` is likely absent. Using `getfacl` as the sole tool means the module would fail for most users out of the box.

The solution: use `stat` as the **primary tool** (universally available), and use `getfacl` as an **optional supplement** when installed.

```bash
stat --format='%a|%A|%U|%G|%F|%n' /etc/hosts
```

Output:
```
644|-rw-r--r--|root|root|regular file|/etc/hosts
```

This single call provides:
- `%a` — octal permission mode (`644`, `755`, etc.)
- `%A` — symbolic mode string (`-rw-r--r--`)
- `%U` — owner username
- `%G` — group name
- `%F` — file type description
- `%n` — file path

That is everything needed to reconstruct the core of a `Get-Acl` output object. If `getfacl` is installed, a second call adds named user and group extended ACL entries to the `Access` array.

## The output object shape

Windows `Get-Acl` returns a `System.Security.AccessControl.FileSecurity` or `DirectorySecurity` object. These are .NET types that do not exist on Linux. The Linux implementation returns a `[PSCustomObject]` with matching property names:

```powershell
[PSCustomObject]@{
    PSTypeName = 'Security.Linux.FileAcl'
    Path       = $realPath
    Owner      = 'root'
    Group      = 'root'
    Access     = @( ... )   # array of access entries
    UnixMode   = '-rw-r--r--'
    OctalMode  = '644'
    FileType   = 'regular file'
    Sddl       = $null      # Windows SDDL string — null on Linux
}
```

The `Access` array contains one entry per POSIX permission set (owner, group, other), plus any named ACL entries if `getfacl` is available:

```powershell
[PSCustomObject]@{
    IdentityReference = 'root'
    EntryType         = 'user'       # 'user', 'group', or 'other'
    FileSystemRights  = 'Read'       # mapped Windows-style label
    AccessControlType = 'Allow'
    Permissions       = 'r--'        # raw 3-char POSIX string
    IsInherited       = $false
}
```

The `FileSystemRights` label uses the same vocabulary as `System.Security.AccessControl.FileSystemRights`:

| POSIX bits | `FileSystemRights` |
|---|---|
| `rwx` | `FullControl` |
| `rw-` | `Modify` |
| `r-x` | `ReadAndExecute` |
| `r--` | `Read` |
| `-wx` | `WriteAndExecute` |
| `-w-` | `Write` |
| `--x` | `ExecuteFile` |
| `---` | `None` |

This mapping is intentionally approximate. POSIX and Windows ACL models differ fundamentally — POSIX is discretionary with three fixed identity slots (owner/group/other), while Windows ACEs can apply to arbitrary SIDs with fine-grained rights. The goal is "good enough for cross-platform scripts" rather than a perfect semantic translation.

## Implementing Get-LinuxAcl

The function supports both named parameter input and pipeline input from `Get-ChildItem`:

```powershell
Get-ChildItem /etc | Get-LinuxAcl | Where-Object { $_.Owner -ne 'root' }
```

Pipeline input from `Get-ChildItem` binds via `ValueFromPipelineByPropertyName`. This exposed a subtle gotcha.

### The PSPath provider prefix problem

When `Get-ChildItem` returns `FileInfo` objects, PowerShell adds a `PSPath` synthetic property. Its value is not just the file path — it is prefixed with the provider name:

```
Microsoft.PowerShell.Core\FileSystem::/etc/hosts
```

The function has `[Alias('PSPath')]` on its `$LiteralPath` parameter, so pipeline input from `Get-ChildItem` binds to `$LiteralPath` with this provider-prefixed value. Passing that string directly to `stat` produces:

```
stat: cannot stat 'Microsoft.PowerShell.Core\FileSystem::/etc/hosts'
```

The fix is straightforward — strip the prefix in the `ByLiteralPath` code path:

```powershell
$LiteralPath | ForEach-Object {
    if ($_ -match '^Microsoft\.PowerShell\.Core\\FileSystem::(.+)$') { $Matches[1] }
    else { $_ }
}
```

This pattern appeared before in earlier modules of this series. It is worth treating as a standard defensive measure whenever `ValueFromPipelineByPropertyName` binds paths.

## Implementing Set-LinuxAcl

`Set-LinuxAcl` supports two parameter sets:

**`ByOctalMode`** — direct permission string:
```powershell
Set-LinuxAcl -Path /tmp/script.sh -OctalMode '755'
```

**`ByAclObject`** — accepts output from `Get-LinuxAcl`:
```powershell
$acl = Get-LinuxAcl /etc/hosts
Set-LinuxAcl -Path /tmp/newfile -AclObject $acl
```

The `ByAclObject` path applies both `chown` (owner:group) and `chmod` (permission bits from `OctalMode`). `chown` requires root or `sudo` — a warning is emitted if it fails, without throwing, because permission changes on owned files are still applied.

`SupportsShouldProcess` is included, so `-WhatIf` works:

```powershell
Set-LinuxAcl -Path /tmp/script.sh -OctalMode '600' -WhatIf
# What if: Performing the operation "chmod 600" on target "/tmp/script.sh".
```

## Windows delegation

Both `Get-LinuxAcl` and `Set-LinuxAcl` detect the platform at the top of their `process` block. On Windows, they delegate to the built-in cmdlets:

```powershell
process {
    if (-not $IsLinux) {
        Microsoft.PowerShell.Security\Get-Acl -Path $Path
        return
    }
    # ... Linux implementation
}
```

This means a cross-platform script can `Import-Module PowerShell.Security.Linux` unconditionally and use `Get-LinuxAcl` on both Windows and Linux — on Windows it silently delegates, on Linux it uses `stat`.

The module manifest's Linux-only guard (`throw` if not `$IsLinux`) is present in `.psm1`, but the individual functions handle Windows gracefully. The guard prevents accidental `Import-Module` on Windows without intent, while still allowing deliberate delegation.

## The aliases

As with previous modules in this series, the actual Windows cmdlet names are exported as aliases:

```powershell
Set-Alias -Name 'Get-Acl' -Value 'Get-LinuxAcl'
Set-Alias -Name 'Set-Acl' -Value 'Set-LinuxAcl'
```

A script written for Windows that calls `Get-Acl /etc/hosts` will work on Linux after importing this module, with no modification.

## Tests

The test file covers module structure, manifest parsing, function file syntax, and Linux runtime behaviour. One test deserves specific mention:

```powershell
It 'pipeline input from Get-ChildItem works' {
    $results = Get-ChildItem /etc -File | Select-Object -First 3 | Get-LinuxAcl
    ($results | Measure-Object).Count | Should -BeGreaterOrEqual 1
    $results[0].PSObject.Properties.Name | Should -Contain 'Path'
}
```

This test caught the PSPath prefix bug described above. Before the fix, it returned 0 results (all `stat` calls failed silently). After the fix: 78/78 tests pass on WSL2, 37/37 on Windows (the remaining 41 are Linux-only and skipped on Windows).

## Example scripts

Four examples ship with the module under `Examples\`:

| Script | Demonstrates |
|---|---|
| `Get-DirectoryPermissions.ps1` | List file ACLs in a directory as a formatted table |
| `Find-NonRootFiles.ps1` | Filter for files not owned by root — basic security audit |
| `Find-WorldWritable.ps1` | Find world-writable files — another common security audit |
| `Copy-FilePermissions.ps1` | `Get-LinuxAcl` / `Set-LinuxAcl` round-trip |

The `Find-WorldWritable` example illustrates how to inspect the `Access` array:

```powershell
Get-ChildItem /tmp |
    Get-LinuxAcl |
    Where-Object {
        $otherEntry = $_.Access | Where-Object { $_.EntryType -eq 'other' }
        $otherEntry -and $otherEntry.Permissions[1] -eq 'w'
    }
```

The `other` entry's `Permissions[1]` is the write bit character (`w` or `-`). `/tmp` is world-writable on Linux (`drwxrwxrwt`) so this always returns at least `/tmp` itself when scanning that directory.

## What is not implemented

- **Extended ACL entries via `setfacl`** — `Set-LinuxAcl` applies named ACL entries from `AclObject.Access` if `setfacl` is installed, but only if named entries are present. In practice, named entries are rare without explicit use of `setfacl`.
- **Recursive ACL application** — `Set-Acl` on Windows supports `-Recurse`. Not yet implemented.
- **Authenticode / catalog** — genuinely not applicable on Linux. Stubs are exported for cross-platform import compatibility.

## Repository

[https://github.com/peppekerstens/PowerShell.Security.Linux](https://github.com/peppekerstens/PowerShell.Security.Linux)

## Next

Part 12 will implement `PowerShell.LocalAccounts.Linux` — `Get-LocalUser`, `New-LocalUser`, `Set-LocalUser`, `Remove-LocalUser`, and the group equivalents, backed by `useradd`, `usermod`, `passwd`, and `groupadd`.
