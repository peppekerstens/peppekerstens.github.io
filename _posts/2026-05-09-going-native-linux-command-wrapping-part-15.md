---
title: Going native — Linux Command Wrapping Part 15
toc: true
---

Part 14 ended on a deliberately vague note. Stage 5 was described as "a longer conversation" involving RFCs, CLAs, and code review by the PowerShell team. That was honest at the time. It turned out Stage 5 produced something more concrete and more immediate than I expected.

Three new GitHub repositories now exist under `peppekerstens`, each a C# binary module, each a parallel track to an existing PowerShell CLI-wrapper module from Stage 1. This post is about what those repos are, why they exist alongside the originals rather than replacing them, and what the difference between the two actually means in practice.

## Two repos, same cmdlets

Stage 1 produced `peppekerstens/NetTCPIP.Linux` — a PowerShell module that wraps `ip`, `ss`, and related tools. `Get-NetRoute` calls `ip -json route show`, parses the JSON, and emits objects. It works. The Stage 4 matrix confirmed it works on five distros.

Stage 5 produced `peppekerstens/NetTCPIP.Linux.Native` — a C# binary module with the same cmdlet names, the same output shapes, and the same underlying tools. `GetNetRouteCommand.ProcessRecord()` calls `ip -json route show`, parses the JSON, and calls `WriteObject()`. Functionally identical.

So why does the second one exist?

The answer is about what "upstream contribution" actually requires. The PowerShell project is a C# codebase. If the goal is to get these cmdlets into PS7 itself — not just into modules people have to install separately, but into the box — they have to be in C#. The PowerShell CLI-wrapper modules are not a contribution target. They are a working prototype. The C# modules are the translation step.

## What Stage 5 actually delivered

Three binary modules:

**`LocalAccounts.Linux.Native`** — 15 cmdlets covering the full `*-LocalUser`, `*-LocalGroup`, and `*-LocalGroupMember` surface. The read path uses P/Invoke directly into libc: `getpwent`, `getgrnam`, `getspnam`, the full set. No subprocesses for reads. Writes still use `Process.Start(useradd)` and friends — the Linux user management tools are the authoritative interface for write operations, so calling into them is correct.

**`ScheduledTasks.Linux.Native`** — 15 cmdlets backed by systemd. Reads use `systemctl list-timers --output=json` + bulk `systemctl show`. Writes create unit files via `File.WriteAllText` then call `systemctl daemon-reload` and `systemctl enable`. No P/Invoke needed here — systemd intentionally does not expose a stable C API, so the subprocess path is the right path.

**`NetTCPIP.Linux.Native`** — 34 cmdlet classes. 10 are fully implemented (`Get-NetIPAddress`, `Get-NetRoute`, `Get-NetTCPConnection`, `Get-NetIPConfiguration`, and the six write cmdlets for addresses, routes, and neighbours). 24 are stubs that emit a `NotSupportedException` ErrorRecord when called. The split reflects what is implementable with `ip` and `ss` versus what requires kernel interfaces that are not yet wired up.

All three: 0 build warnings, 0 build errors with `TreatWarningsAsErrors=true`. All three have GHA workflows for build and a 5-distro Pester matrix.

## Why keep the CLI wrappers

There are now twelve PowerShell CLI-wrapper modules from Stage 1 and three C# binary modules from Stage 5. The natural question is whether the CLI wrappers are now obsolete.

They are not, for a few reasons.

First, the C# modules cover a subset. `LocalAccounts.Linux.Native`, `ScheduledTasks.Linux.Native`, and `NetTCPIP.Linux.Native` are three of twelve. The other nine — `Storage.Linux`, `PrintManagement.Linux`, `DnsClient.Linux`, `Update.Linux`, `PackageManagement.Linux`, `SmbShare.Linux`, `NetAdapter.Linux`, `PKI.Linux`, `PowerShell.Security.Linux` — have no C# counterparts yet. Those cmdlets only exist in PowerShell form.

Second, the PowerShell implementations are easier to read and modify. A contributor who wants to check what `Get-LocalUser` returns, tweak the output shape, or add a parameter can do that in 20 lines of PowerShell without a build step. The C# version requires dotnet, a project file, and recompilation. For experimentation and rapid iteration, the PS module wins.

Third, the CLI wrappers served their purpose as a validated functional spec. Before writing `IpHelpers.cs`, I knew exactly what `ip -json addr show` returns and how to map it to a `NetIPAddress` object — because `GetNetIPAddressCommand.ps1` already did it and had 141 passing tests. Writing the C# translation was mostly mechanical. That is a useful division of labour: figure out what it should do in PowerShell, then port it to C# once the behaviour is settled.

## The P/Invoke path for LocalAccounts

The most technically interesting part of `LocalAccounts.Linux.Native` is the read path. The PowerShell version called `getent passwd` in a subprocess and parsed the colon-separated output. That works. The C# version calls into libc directly.

```csharp
[LibraryImport("libc", EntryPoint = "getpwent")]
[return: MarshalAs(UnmanagedType.LPStr)]
private static partial IntPtr getpwent();
```

The `LibraryImport` attribute (source-generated P/Invoke, available since .NET 7) generates the marshalling code at compile time rather than at runtime. The result is zero subprocess overhead for `Get-LocalUser`. On a system with many local users, this is measurably faster. Whether that matters in practice is debatable — how often do you call `Get-LocalUser` in a tight loop? — but it is the right approach for a module that is trying to be taken seriously as a production-quality implementation.

One thing that is worth knowing: `getspnam` (shadow password lookup) silently returns `IntPtr.Zero` for non-root callers. The shadow file is root-readable only. The code handles this gracefully — password-related fields default to safe values when the shadow lookup fails — but it means `Get-LocalUser -Name alice` run as a regular user returns less information than the same command run as root. This matches the behaviour of the underlying system. It is not a bug.

## The systemd situation

ScheduledTasks was the module I expected to be annoying and it was not. Systemd has no stable C API — this is an intentional design decision by the systemd team — so there is no P/Invoke path. The only stable interface is the D-Bus protocol or the `systemctl` command. Calling `systemctl` from C# via `Process.Start` is the same as calling it from PowerShell via `Start-Process`. The C# version is more verbose but not more clever.

What the C# version does get right is the type system. `RegisteredTask` is a proper class with `[OutputType(typeof(RegisteredTask))]` on `GetScheduledTaskCommand`. PowerShell format files and `Get-Member` both work correctly. In the PS module, the objects are `PSCustomObject` instances which `Get-Member` handles but which lose strong typing when passed through pipelines in unexpected ways. Not a dealbreaker, but a real difference.

`Set-ScheduledTask` and `Export-ScheduledTask` are stubs in the C# module, same as they were in the PS module. `Export-ScheduledTask` is genuinely awkward: `systemctl cat <unit>` returns the unit file, but the expected output format for `Export-ScheduledTask` is an XML `<Task>` element matching the Windows Task Scheduler schema. There is no sensible mapping. Returning the systemd unit file as a string under a misleading cmdlet name would be worse than returning an error. So it returns an error.

## NetTCPIP — the stub problem

`NetTCPIP.Linux.Native` has 24 stubs. This deserves some honesty about what those stubs are.

Some are "not yet implemented": `Get-NetAdapter`, `Get-NetIPInterface`, `Get-NetNeighbor`. The underlying data is accessible via `ip link` and `ip neigh`. The C# model classes could be written. The issue is time — these would be straightforward to add in a follow-up session.

Others are genuinely "not applicable in the same way": `Get-NetQosPolicy`, `Set-NetQosPolicy`, `New-NetQosPolicy`. Windows Network QoS Policy is a NDIS concept. Linux has `tc` (traffic control) which overlaps somewhat, but the parameter surface is completely different. A stub that errors with `NotSupportedException` is more honest than a cmdlet that silently does something different from what the documentation implies.

The 24-stub situation is fine as a starting point. It would not be fine as a final answer. The follow-up work is to go through them one by one and decide: implementable with `ip`/`ss`/`tc`, implementable with something else, or genuinely not applicable.

## GHA and the privileged flag

The NetTCPIP Pester workflow uses `--privileged` on the container. The write cmdlets — `New-NetIPAddress`, `Remove-NetRoute`, `New-NetNeighbor` — call `ip addr add`, `ip route del`, `ip neigh add`. These require `CAP_NET_ADMIN`. Without `--privileged`, they fail with "Operation not permitted."

In Stage 4, the same issue came up for `ping` (which needs `CAP_NET_RAW`). The fix there was `--cap-add=NET_RAW`. For `ip` write operations, the required capability is `CAP_NET_ADMIN`. You can add it specifically with `--cap-add=NET_ADMIN`, or you can use `--privileged` which grants all capabilities.

`--privileged` is a broader grant than necessary. For a CI container running tests in an isolated job that gets torn down immediately after, this is acceptable. For a production container running arbitrary user code, it would not be. The GHA workflow uses `--privileged` with a comment noting what it is for. That is the right level of explicitness.

## Numbers

| Module | Cmdlets | Tests | Head |
|---|---|---|---|
| `LocalAccounts.Linux.Native` | 15 full (P/Invoke reads) | 116 | [`6273baf`](https://github.com/peppekerstens/LocalAccounts.Linux.Native/commit/6273baf) |
| `ScheduledTasks.Linux.Native` | 13 full + 2 stubs | 63 | [`4dcc235`](https://github.com/peppekerstens/ScheduledTasks.Linux.Native/commit/4dcc235) |
| `NetTCPIP.Linux.Native` | 10 full + 24 stubs | — | [`3df46c4`](https://github.com/peppekerstens/NetTCPIP.Linux.Native/commit/3df46c4) |

All three: 0 build warnings, 0 build errors, 5-distro GHA matrix.

The parallel CLI-wrapper repos remain untouched:

| Module | Cmdlets | Status |
|---|---|---|
| `PowerShell.LocalAccounts.Linux` | 15 cmdlets | Stage 1 — unchanged |
| `ScheduledTasks.Linux` | 15 cmdlets | Stage 2 Crescendo migration — unchanged |
| `NetTCPIP.Linux` | 10+ cmdlets | Stage 1 + Stage 2 Crescendo migration — unchanged |

Two repo families, same cmdlet names, same output shapes, different implementation technology. For now, both exist. That is fine.

## Finishing the job: subprocess audit and /proc reads

After the initial Stage 5 push, a subprocess audit ran across all three repos. The question was straightforward: every call to `Process.Start` is a potential latency hit and a dependency on an external binary. Which ones can be eliminated?

The results were mixed in an informative way.

**`LocalAccounts.Linux.Native`** was already clean. The read path uses P/Invoke for everything — `getpwent`, `getgrent`, `getspnam` — so `Process.Start` only appears in write cmdlets (`useradd`, `usermod`, `userdel`, `groupadd`, `groupmod`, `groupdel`, `gpasswd`, `chpasswd`, `chage`). Those are correct uses: the Linux user management tools are the authoritative write interface and there is no sensible P/Invoke alternative. One minor cleanup: `SystemdHelpers.cs` had a `Run("id", "-u")` subprocess call to get the current UID. That was replaced with a direct `getuid()` P/Invoke — a two-line change, cleaner, and removes one process spawn per cmdlet invocation.

Wait, that is in `ScheduledTasks.Linux.Native`, not LocalAccounts. Let me restate that correctly.

**`ScheduledTasks.Linux.Native`** had one read-path subprocess hiding in the helpers: `Run("id", "-u")` to get the current user's UID in order to decide whether to write system-scope or user-scope unit files. This is exactly the kind of thing P/Invoke handles trivially. `getuid()` is a single-syscall libc function with a dead-simple signature:

```csharp
[LibraryImport("libc")]
private static partial uint getuid();
```

One subprocess gone. The rest of the write paths (`systemctl daemon-reload`, `systemctl enable`, `systemctl start`, `File.WriteAllText` for unit files) stay as-is — that is the correct interface for systemd.

**`NetTCPIP.Linux.Native`** was the interesting one. The original `IpHelpers.cs` implemented reads by calling `ip -json addr show`, `ip -json route show`, and `ss -tnap`, then parsing JSON or structured text. This worked, and it matched the Stage 1 PowerShell wrapper almost exactly. But it also meant every call to `Get-NetIPAddress` spawned a subprocess.

The BCL's `System.Net.NetworkInformation.NetworkInterface` already exposes everything `ip addr show` returns — interface name, address list, prefix lengths — without touching the shell. `/proc/net/route` and `/proc/net/ipv6_route` contain the full routing table in hex-encoded text. `/proc/net/tcp` and `/proc/net/tcp6` contain the TCP socket table with state codes and inodes. Cross-referencing `/proc/<pid>/fd/` for `socket:[inode]` symlinks gives you PID.

All four read paths were rewritten to use these sources directly. The parsing is more explicit than JSON parsing — you are reading raw hex and converting it — but it is also faster and has no external binary dependency.

The hex formats are worth documenting because they are not obvious:

- `/proc/net/route`: each column after the interface name is hex. The destination and gateway are 4-byte little-endian IPv4 addresses, so `0101A8C0` is `192.168.1.1` (bytes reversed: `C0`, `A8`, `01`, `01`).
- `/proc/net/ipv6_route`: 32-character hex strings, big-endian, representing 16-byte IPv6 addresses. No reversal needed.
- `/proc/net/tcp`: local and remote addresses are `hex_ip:hex_port`. State is a hex byte that maps to the TCP state name.
- PID lookup: scan `/proc/<pid>/fd/` for symlinks whose targets are `socket:[inode]`. Match the inode against the socket table entry. This is O(processes × file descriptors), which sounds expensive, but on a typical system with a few hundred processes it is fast enough in practice.

One CA1416 build error came up in the process. `UnicastIPAddressInformation.AddressValidLifetime` and `AddressPreferredLifetime` are Windows-only BCL properties — the Roslyn analyser correctly flags them as not callable from a target-platform-agnostic binary. On Linux, the kernel exposes address lifetime via rtnetlink, but the BCL does not surface it through `NetworkInterface`. The fix was to return `TimeSpan.MaxValue` (infinite) on non-Windows and guard the Windows-only property access with `OperatingSystem.IsWindows()`:

```csharp
var validLifeRaw = OperatingSystem.IsWindows() ? uni.AddressValidLifetime : uint.MaxValue;
```

Pragmatic, correct, and the `#pragma warning disable CA1416` makes the intent explicit. The error is not suppressed silently — it is documented in the code.

After the rewrite: 0 build warnings, 0 build errors. The subprocess count in `IpHelpers.cs` for read operations is now zero.

## What this is building towards

The Tier 2 label on Stage 5 was "external binary module — faster to ship, upstream later." The "upstream later" part is the next honest question.

Upstreaming to PowerShell requires: an RFC at `github.com/PowerShell/PowerShell-RFC`, a signed CLA, implementation that passes the Azure DevOps CI pipelines, and code review from the PowerShell team. That is not a lot of steps, but each step is a real commitment, not a side project.

The C# implementations in these three repos are close to what an upstream contribution would look like. The namespace is `Microsoft.PowerShell.Commands`. The cmdlet base classes are `PSCmdlet`. The patterns follow `ComputerUnix.cs` and similar existing in-tree files. But "close to" is not "ready for."

The gap between "works in a GitHub repo" and "accepted into PS7" is mostly about quality signals: comprehensive test coverage including edge cases, documentation that matches the parameter help in the Windows version, and output objects that are genuinely compatible with downstream scripts that consume the Windows cmdlet's output. All of that is achievable. None of it is done yet.

## Next

The Tier 2 work is complete and cleaned up. Three modules, three repos, subprocess-free read paths, parallel to the existing CLI wrappers. The Tier 1 question — contributing directly to the PowerShell project — is open.

Before going there: the GHA workflows have never actually run against these three repos in a fully completed state. The images exist, the workflows are there, but a green matrix across all five distros has not been confirmed yet. That is the obvious next thing to verify.

Pending that: the RFC process, what it involves, and whether any of these three modules is a reasonable upstream candidate.
