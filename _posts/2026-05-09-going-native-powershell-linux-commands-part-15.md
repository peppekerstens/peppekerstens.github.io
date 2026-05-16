---
date: 2026-05-09
title: Going native — PowerShell Linux Commands Part 15
toc: true
redirect_from:
  - /going-native-linux-command-wrapping-part-15/
---

Part 14 ended on a deliberately vague note. Stage 5 was described as "a longer conversation" involving RFCs, CLAs, and code review by the PowerShell team. That was honest at the time. It turned out Stage 5 produced something more concrete and more immediate than I expected.

Three new GitHub repositories now exist under `peppekerstens`, each a C# binary module, each a parallel track to an existing PowerShell CLI-wrapper module from Stage 1. This post is about what those repos are, why they exist alongside the originals rather than replacing them, and what the difference between the two actually means in practice. And then some follow-up work that happened after the initial push — because the first version had subprocesses in places they did not need to be, and tests that were thinner than they should be.

## Two repos, same cmdlets

Stage 1 produced `peppekerstens/NetTCPIP.Linux` — a PowerShell module that wraps `ip`, `ss`, and related tools. `Get-NetRoute` calls `ip -json route show`, parses the JSON, and emits objects. It works. The Stage 4 matrix confirmed it works on five distros.

Stage 5 produced `peppekerstens/NetTCPIP.Linux.Native` — a C# binary module with the same cmdlet names, the same output shapes, and the same underlying tools. Functionally identical at the surface.

So why does the second one exist?

The answer is about what "upstream contribution" actually requires. The PowerShell project is a C# codebase. If the goal is to get these cmdlets into PS7 itself — not into modules people have to install separately, but into the box — they have to be in C#. The PowerShell CLI-wrapper modules are not a contribution target. They are a working prototype. The C# modules are the translation step.

## What Stage 5 actually delivered

Three binary modules.

**`LocalAccounts.Linux.Native`** — 15 cmdlets covering the full `*-LocalUser`, `*-LocalGroup`, and `*-LocalGroupMember` surface. The read path uses P/Invoke directly into libc: `getpwent`, `getgrnam`, `getspnam`. No subprocesses for reads. Writes still use `Process.Start(useradd)` and friends — the Linux user management tools are the authoritative write interface, so calling them is correct.

**`ScheduledTasks.Linux.Native`** — 15 cmdlets backed by systemd. Reads use `systemctl list-timers --output=json` plus bulk `systemctl show`. Writes create unit files via `File.WriteAllText` then call `systemctl daemon-reload` and `systemctl enable`. No P/Invoke needed here — systemd intentionally does not expose a stable C API, so the subprocess path is the right path.

**`NetTCPIP.Linux.Native`** — 34 cmdlet classes. 10 are fully implemented: `Get-NetIPAddress`, `Get-NetRoute`, `Get-NetTCPConnection`, `Get-NetIPConfiguration`, and the six write cmdlets for addresses, routes, and neighbours. 24 are stubs that emit a `NotSupportedException` ErrorRecord when called. The split reflects what is implementable with `ip` and `ss` versus what requires kernel interfaces that are not yet wired up.

All three: 0 build warnings, 0 build errors with `TreatWarningsAsErrors=true`. All three have GHA workflows for build and a 5-distro Pester matrix.

## Why keep the CLI wrappers

There are now twelve PowerShell CLI-wrapper modules from Stage 1 and three C# binary modules from Stage 5. The natural question is whether the CLI wrappers are obsolete.

They are not, for a few reasons.

First, the C# modules cover a subset. The other nine — `Storage.Linux`, `PrintManagement.Linux`, `DnsClient.Linux`, `Update.Linux`, `PackageManagement.Linux`, `SmbShare.Linux`, `NetAdapter.Linux`, `PKI.Linux`, `PowerShell.Security.Linux` — have no C# counterparts yet.

Second, the PowerShell implementations are easier to read and modify. A contributor who wants to check what `Get-LocalUser` returns, tweak the output shape, or add a parameter can do that in 20 lines of PowerShell without a build step. The C# version requires dotnet, a project file, and recompilation.

Third, the CLI wrappers served their purpose as a validated functional spec. Before writing `IpHelpers.cs`, I knew exactly what `ip -json addr show` returns and how to map it to a `NetIPAddress` object — because `GetNetIPAddressCommand.ps1` already did it and had 141 passing tests. Writing the C# translation was mostly mechanical. Figure out what it should do in PowerShell, then port it to C# once the behaviour is settled. That is a useful division of labour.

## The P/Invoke path for LocalAccounts

The most interesting part of `LocalAccounts.Linux.Native` is the read path. The PowerShell version called `getent passwd` in a subprocess and parsed colon-separated output. The C# version calls into libc directly:

```csharp
[LibraryImport("libc", EntryPoint = "getpwent")]
[return: MarshalAs(UnmanagedType.LPStr)]
private static partial IntPtr getpwent();
```

`LibraryImport` (source-generated P/Invoke, available since .NET 7) generates the marshalling code at compile time rather than at runtime. Zero subprocess overhead for `Get-LocalUser`. Whether that matters in practice is debatable — how often do you call `Get-LocalUser` in a tight loop? — but it is the right approach for something that is trying to be taken seriously as a production-quality implementation.

One thing worth knowing: `getspnam` (shadow password lookup) silently returns `IntPtr.Zero` for non-root callers. The shadow file is root-readable only. The code handles this gracefully — password-related fields default to safe values when the shadow lookup fails — but it means `Get-LocalUser -Name alice` run as a regular user returns less information than the same command run as root. This matches the behaviour of the underlying system. It is not a bug.

## The systemd situation

ScheduledTasks was the module I expected to be annoying and it was not. Systemd has no stable C API — this is an intentional design decision by the systemd team — so there is no P/Invoke path. The only stable interface is D-Bus or `systemctl`. Calling `systemctl` from C# via `Process.Start` is the same as calling it from PowerShell via `Start-Process`. The C# version is more verbose but not more clever.

What the C# version does get right is the type system. `RegisteredTask` is a proper class with `[OutputType(typeof(RegisteredTask))]` on `GetScheduledTaskCommand`. In the PS module, the objects are `PSCustomObject` instances — `Get-Member` handles them but they lose strong typing when passed through pipelines in unexpected ways. Not a dealbreaker, but a real difference.

`Set-ScheduledTask` and `Export-ScheduledTask` are stubs. `Export-ScheduledTask` is genuinely awkward: the expected output format is an XML `<Task>` element matching the Windows Task Scheduler schema. There is no sensible mapping from systemd unit files. Returning the unit file as a string under a misleading cmdlet name would be worse than returning an error. So it returns an error.

## NetTCPIP — the stub situation

`NetTCPIP.Linux.Native` has 24 stubs. Some are "not yet implemented": `Get-NetIPInterface`, `Get-NetNeighbor`. The underlying data is accessible via `ip`. The C# model classes could be written. The issue is time.

Others are genuinely "not applicable in the same way": Windows Network QoS Policy is a NDIS concept. Linux has `tc` which overlaps somewhat, but the parameter surface is completely different. A stub that errors with `NotSupportedException` is more honest than a cmdlet that silently does something different.

The 24-stub situation is fine as a starting point. It would not be fine as a final answer.

## Subprocess audit — what happened after the initial push

After the initial Stage 5 push, I ran a subprocess audit across all three repos. The question: every call to `Process.Start` is a potential latency hit and a dependency on an external binary. Which ones can be eliminated?

The results were interesting.

**`ScheduledTasks.Linux.Native`** had one read-path subprocess hiding in the helpers: `Run("id", "-u")` to get the current user's UID, used to decide whether to write system-scope or user-scope unit files. `getuid()` is a single-syscall libc function:

```csharp
[LibraryImport("libc")]
private static partial uint getuid();
```

One subprocess gone. Everything else in ScheduledTasks stays as-is — `systemctl` is the correct interface for systemd, subprocess is fine there.

**`NetTCPIP.Linux.Native`** was the more substantial change. The original `IpHelpers.cs` called `ip -json addr show`, `ip -json route show`, and `ss -tnap` for all read operations — same tools as the Stage 1 PS wrapper, just from C#. That worked, but every `Get-NetIPAddress` call spawned a subprocess.

The BCL's `System.Net.NetworkInformation.NetworkInterface` already exposes everything `ip addr show` returns. `/proc/net/route` and `/proc/net/ipv6_route` contain the full routing table. `/proc/net/tcp` and `/proc/net/tcp6` have the TCP socket table. Cross-referencing `/proc/<pid>/fd/` for `socket:[inode]` symlinks gives you PID.

All four read paths got rewritten to use these sources directly. The hex formats in `/proc` are not obvious:

- `/proc/net/route`: 4-byte little-endian IPv4. `0101A8C0` is `192.168.1.1` (bytes reversed: `C0`, `A8`, `01`, `01`).
- `/proc/net/ipv6_route`: 32-char hex strings, big-endian, 16-byte IPv6. No reversal needed.
- `/proc/net/tcp`: state is a hex byte mapping to a TCP state name.
- PID lookup: scan `/proc/<pid>/fd/` for symlinks to `socket:[inode]`. O(processes × file descriptors), fast enough in practice.

One build error came up during this. `UnicastIPAddressInformation.AddressValidLifetime` and `AddressPreferredLifetime` are Windows-only BCL properties. The Roslyn CA1416 analyser flags them correctly — they cannot be called from a platform-agnostic binary. On Linux, the kernel exposes address lifetime via rtnetlink but the BCL does not surface it through `NetworkInterface`. The fix is to return `TimeSpan.MaxValue` (infinite) on non-Windows and guard the access:

```csharp
var validLifeRaw = OperatingSystem.IsWindows() ? uni.AddressValidLifetime : uint.MaxValue;
```

Pragmatic, correct, and the `#pragma warning disable CA1416` makes the intent explicit rather than hiding the suppression.

After the rewrite: 0 build warnings, 0 build errors. Zero subprocesses in `IpHelpers.cs` for read operations.

## Expanding the tests

With the subprocess audit done, the obvious next question was whether the tests were good enough to trust the matrix. The answer was: not quite.

The existing tests for all three modules were honest about what they covered — surface checks, factory cmdlets, WhatIf safety, basic integration. The kind of tests you write first to prove the module loads and does not immediately explode. What was missing was anything resembling how someone would actually use these modules in practice.

**ScheduledTasks** got weekly and AtStartup trigger tests, a pipeline bulk disable/enable test (because `Get-ScheduledTask -TaskName 'backup*' | Disable-ScheduledTask` is a real pattern that breaks silently if pipeline binding is wrong), and a conditional `Start-ScheduledTask` test that registers a task, runs it, and waits for a `/tmp/marker` file. That last one is gated on `$script:hasSystemd` — set in `BeforeDiscovery` by checking `/run/systemd/private` — so it skips cleanly on containers without an init system rather than failing with "Failed to connect to bus."

**NetTCPIP** got a loopback alias round-trip (`127.0.1.99/32` on `lo` — safe, no routing side effects), a route round-trip with an RFC 5737 documentation range (`192.0.2.0/24`), and a real TCP listener test. That last one opens a `TcpListener` in `BeforeAll` on port 19753, runs `Get-NetTCPConnection -State Listen`, and asserts the port appears. It runs as any user — no root needed for a userspace socket. The previous version relied on ambient LISTEN sockets in the container, which might not exist.

**LocalAccounts** already had ~140 tests from the previous session (service account provisioning, bulk operator group management, account expiry). Nothing new added there.

There was also a subtle Pester 5 scoping issue worth documenting. Skip conditions in `Describe -Skip:()` are evaluated at discovery time, before `BeforeAll` runs. So `$script:hasSystemd` had to be set in `BeforeDiscovery`, not `BeforeAll`. The same applies to `$script:isRoot`. Both are now set in `BeforeDiscovery`. This is the kind of thing that only seems obvious after you have had a test fail with "Cannot overwrite variable IsLinux because it is read-only" in a CI container and spent time staring at the wrong line.

## Numbers

| Module | Cmdlets | Tests | Head |
|---|---|---|---|
| `LocalAccounts.Linux.Native` | 15 full (P/Invoke reads) | ~147 | [`bc0d37b`](https://github.com/peppekerstens/LocalAccounts.Linux.Native/commit/bc0d37b) |
| `ScheduledTasks.Linux.Native` | 13 full + 2 stubs | ~100 | [`3f4648d`](https://github.com/peppekerstens/ScheduledTasks.Linux.Native/commit/3f4648d) |
| `NetTCPIP.Linux.Native` | 10 full + 24 stubs | ~65 | [`cd3767e`](https://github.com/peppekerstens/NetTCPIP.Linux.Native/commit/cd3767e) |

All three: 0 build warnings, 0 build errors, 5-distro GHA matrix.

## What still needs to happen

The GHA matrix runs are queued across all three repos. The most likely point of failure on the new tests: the route round-trip assumes `iproute2` is installed (it is — the testinfra Dockerfiles include it) and that `--privileged` is set (it is, in the `pester.yml` container options). The systemd-dependent test produces a skip count rather than a failure count on containers without an init system.

If the matrix comes back green — or green with expected skips — the next step is the RFC question. What it takes to upstream any of these three modules to PS7, and whether now is the right time to start that conversation.

That is a bigger question than a test expansion. We will get to it.






