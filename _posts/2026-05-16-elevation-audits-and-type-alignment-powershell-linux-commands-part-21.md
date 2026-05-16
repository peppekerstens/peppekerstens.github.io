---
date: 2026-05-16 14:00:00 -0000
title: elevation audits and type alignment — powershell linux commands part 21
toc: true
redirect_from:
  - /elevation-audits-and-type-alignment-linux-command-wrapping-part-21/
---

Part 20 ended with the second LLM code review finding seven new issues across the four native modules. All seven were fixed. The builds were green. The Pester matrix was green. Twenty-eight issues total, twenty-seven resolved, one deferred.

I declared the code review phase done. Then I did something the LLM could not do: I ran the write cmdlets as a non-root user and watched what happened.

The results were not what I expected.

## The elevation audit

The theory was simple. Every state-changing cmdlet that requires root should fail with a clear message. Not a stack trace. Not a raw subprocess error. Something a human can act on.

The pattern established across the modules was: catch the failure, translate it, and throw an `ErrorRecord` with error ID `ElevationRequired` and category `PermissionDenied`. `LocalAccounts.Linux.Native` and `NetTCPIP.Linux.Native` followed this cleanly. Their subprocess-based write cmdlets catch non-zero exit codes and produce `"CmdletName requires root privileges. Use 'sudo pwsh'."`

`ScheduledTasks.Linux.Native` does something different by design. It checks `IsSystemContext()` — which returns false for non-root — and falls back to user-scope timers under `~/.config/systemd/user/`. No elevation error needed. The cmdlet works, just in a different scope.

`Services.Linux.Native` was the problem.

## The D-Bus leak

`Start-Service`, `Stop-Service`, and `Restart-Service` already handled this correctly. Their `UnitActionAsync` method catches `Tmds.DBus.Protocol.DBusException` with the error name `InteractiveAuthorizationRequired` and translates it to the standard elevation message.

`Set-Service`, `New-Service`, and `Remove-Service` did not.

`Set-Service` calls `EnableUnits` and `DisableUnits` to change the startup type. `New-Service` and `Remove-Service` call `DaemonReload` after writing or removing unit files. These three D-Bus operations threw raw polkit errors straight through to the caller. The user sees a `DBusException` with an internal error name, not a message that tells them what to do.

This is issue #29. It was a MUST-severity bug because it only manifests on non-root systems, which is where most users will encounter the cmdlets for the first time.

The fix was straightforward. Wrap `EnableUnits`, `DisableUnits`, and `DaemonReload` in try-catch blocks that catch `DBusExceptionBase` and check for `InteractiveAuthorizationRequired` in the message. Translate to the standard elevation message. Throw.

```csharp
catch (DBusExceptionBase ex) when (ex.Message.Contains("InteractiveAuthorizationRequired"))
{
    throw new InvalidOperationException(
        "EnableUnitFiles failed: root privileges are required. Use 'sudo pwsh'.", ex);
}
```

The cmdlets then catch this `InvalidOperationException` and emit an `ErrorRecord` with error ID `ElevationRequired` and category `PermissionDenied`. The same pattern now appears in `SystemdHelper.cs` for the standalone module and in `ServiceUnix.cs` for the fork. Commit `1ba16a8` in the standalone repo, matching commit `139776a` in the fork.

The elevation audit table after the fix:

| Module | Write cmdlets | Non-root behavior |
|---|---|---|
| Services.Linux.Native | Start/Stop/Restart/Set/New/Remove-Service | `"root privileges are required. Use 'sudo pwsh'."` |
| LocalAccounts.Linux.Native | All 11 write cmdlets | `"CmdletName requires root privileges."` |
| ScheduledTasks.Linux.Native | All 6 write cmdlets | Falls back to user-scope timers |
| NetTCPIP.Linux.Native | All 6 write cmdlets | `"CmdletName requires root privileges."` |

All four modules now have tests that verify the elevation message, error ID, and error category on non-root Linux. The tests run as part of the standard Pester matrix.

## The type alignment question

With the elevation audit complete, I turned to a question that had been nagging since the Services module was first written: what does `Get-Service` return on Linux?

On Windows, `Get-Service` returns `System.ServiceProcess.ServiceController`. This type extends `System.ComponentModel.Component`, implements `IDisposable`, and exposes 25+ members including `Start()`, `Stop()`, `WaitForStatus()`, and properties like `Status`, `StartType`, and `MachineName`.

On Linux, `Services.Linux.Native` returns `LinuxServiceInfo`. This type extends `object`. It has `Name`, `DisplayName`, `Status`, `StartupType`, and a few others. It does not extend `Component`. It does not implement `IDisposable`. It does not match the Windows type hierarchy at all.

The incompatibilities fall into three buckets:

**Breaking** — code that works on Windows will fail on Linux. `LinuxServiceInfo` cannot be cast to `Component`. `Dispose()` does not exist. `WaitForStatus()` does not exist.

**Degrading** — code that works but loses information. Property type mismatches. `StartupType` is a custom enum on Linux versus `ServiceStartMode` on Windows.

**Cosmetic** — `Get-Member` shows a different type name. Scripts that check `$_.GetType().Name` break.

This is not acceptable for an upstream contribution. The whole point of porting these cmdlets is that they behave the same way on both platforms.

## The research

`System.ServiceProcess.ServiceController` itself cannot be subclassed on Linux. It is a Windows-only stub on `net8.0` — the assembly exists but the implementation throws `PlatformNotSupportedException` for every method.

`System.ComponentModel.Component`, however, is cross-platform. It is not sealed. It has no Windows-specific APIs. It is the base class that `ServiceController` extends on Windows.

The design proposal is simple: `LinuxServiceController : Component`.

This type would:
- Inherit from `Component` (shared across platforms)
- Implement the 25 `ServiceController` members that the Windows version exposes
- Use D-Bus for the 8 members that need live system interaction (`Start()`, `Stop()`, `Refresh()`, `WaitForStatus()`, etc.)
- Throw `PlatformNotSupportedException` for the 5 members that are genuinely Windows-only (like `GetServices()` with machine name)
- Add Linux-specific extensions as separate methods, not as overrides

The full analysis lives in `Services.Linux.Native/docs/linuxserviceinfo-vs-servicecontroller-20260516.md`. It maps every `ServiceController` member to its Linux equivalent, identifies the D-Bus calls required, and estimates ~570 lines of C# for the full implementation.

This is now Rule 9: cross-platform type alignment is mandatory. The priority order is: inherit from common base class, match property names and types, match methods, add Linux-specific extensions, split class tree only as a last resort.

## What this means for the fork

The fork branch `feature/service-unix-systemctl` currently uses `LinuxServiceInfo`. Replacing it with `LinuxServiceController : Component` is a prerequisite for the upstream PR. The work breaks down into three steps:

1. Build `LinuxServiceController` in the standalone `Services.Linux.Native` repo
2. Replace `LinuxServiceInfo` with `LinuxServiceController` in the fork's `ServiceUnix.cs`
3. Update the fork tests for the new type name and property set

The type alignment work is the last substantive engineering task before the upstream submission. After that, the remaining steps are administrative: sign the Microsoft CLA, file the RFC at `PowerShell/PowerShell-RFC`, and submit the PR.

The elevation audit found one bug that needed fixing. The type alignment research identified a design task that needs doing. Both are now tracked in status.md with clear acceptance criteria.

The native modules are functionally complete. The remaining work is about making them look and behave like they belong in the PowerShell source tree.
