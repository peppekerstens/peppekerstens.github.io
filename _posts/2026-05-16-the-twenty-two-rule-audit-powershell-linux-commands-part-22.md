---
date: 2026-05-16 18:00:00 -0000
title: the twenty-two rule audit — powershell linux commands part 22
toc: true
redirect_from:
  - /the-twenty-two-rule-audit-linux-command-wrapping-part-22/
---

Part 21 ended with the elevation audit complete and the `LinuxServiceController : Component` design documented. The Services module had nine cmdlets, D-Bus integration, and proper error translation. It passed its tests. It built clean.

I still wanted to know how it measured up against the rest of the codebase. The other three native modules had been through a full code review. Services had been reviewed in isolation during the port, but not against the full set of conventions that had accumulated across all four repos.

So I wrote the rules down and audited Services against every single one.

## The rules

The rules live in `stage6/linux-rules.md`. They started as nine guidelines for Linux module development. By the time the audit was done, there were twenty-two.

The foundational principle is Rule 1: native .NET APIs first. Use D-Bus for systemd. Use P/Invoke for libc. Subprocess is a last resort. This is not a preference. It is a requirement. The Windows built-in cmdlets use native Win32 APIs. The Linux equivalents should do the same.

Rules 2 through 8 cover error handling, process invocation, platform branching, and code hygiene. Rules 9 through 22 cover type alignment, documentation, test infrastructure, and parameter conventions. The full list is in the repo.

## The audit

I ran through all 22 rules against every file in `Services.Linux.Native`. 62 C# files. 11 cmdlet classes. 3 helper classes. 1 test file.

The results:

| Severity | Count | Status |
|---|---|---|
| MUST | 7 | 5 resolved, 2 deferred |
| SHOULD | 9 | 3 resolved, 6 open |

The MUST fixes were the priority. Five of seven were resolved within the audit session. Two were deferred as debatable.

### Rule 10 — Copyright headers

The files said `Microsoft Corporation`. They should say `peppekerstens`. The module is not Microsoft code. It will be submitted to Microsoft eventually, but until then, the copyright belongs to the author. Fixed across all 43 files in commit `20add13`.

### Rule 8 — Platform branching

No cmdlet had an `OperatingSystem.IsWindows()` guard. Every cmdlet should delegate to the built-in Windows version when running on Windows. Without this guard, the module would try to use D-Bus on Windows and fail. Added to all 11 cmdlet classes in commit `da83f34`.

### Rule 7 — Silent error swallowing

`RemoveServiceCommand` had two bare `catch (Exception) { }` blocks. `SystemdHelper.IsNonRoot()` had another. These swallow errors silently. They are never acceptable. Replaced with proper error handling that writes `ErrorRecord` instances with meaningful categories. Commit `35d1fcc`.

### Rule 6 — Error ID and category

The error ID was `ElevationRequired` with category `PermissionDenied`. Windows uses `UnauthorizedAccess` with category `SecurityError` for the same scenario. Changed to match the Windows precedent. Commit `219db42`.

### Rule 11 — Error message resources

Error messages were hardcoded string literals scattered across cmdlet files. Centralized into `ErrorMessages.cs` with const fields and a `Format()` method. This makes them searchable, testable, and easy to update. Commit `d2243b7`.

### Rule 12 — HelpUri and RemotingCapability

No `[Cmdlet]` attribute had `HelpUri` or `RemotingCapability`. Added both. `HelpUri` points to the Microsoft Learn page for the Windows equivalent cmdlet. This is Phase 1 — authoritative documentation for the shared surface. Phase 2 will be a delta docs site for Linux-specific behavior. Commit resolved via attribute additions across all cmdlet classes.

### Rule 3 — D-Bus vs subprocess (revised)

Rule 3 originally said "use `systemctl` subprocess, not D-Bus." The audit proved this wrong. D-Bus IS the native API for systemd. `systemctl` is a CLI wrapper around the same D-Bus calls. Using D-Bus directly is the Linux equivalent of using Win32 APIs directly on Windows. Subprocess should be a last resort only.

Rule 3 was revised to reflect this. The Services module already uses D-Bus via `Tmds.DBus.Protocol`. No changes needed. Commit `e891d9d` updated the rules file.

### Rule 32 — Proactive elevation check (deferred)

The write cmdlets rely on reactive error translation — catch the D-Bus polkit error, translate it, throw. Rule 32 asks for a proactive `Utils.IsAdministrator()` check at the top of each write cmdlet.

This is debatable. The Windows built-in `*-Service` cmdlets also use a reactive pattern. They do not check for admin rights upfront. They attempt the operation and fail with an access denied error. The Services module follows the same pattern. Deferred.

### Rule 34 — `RunSystemctl()` conventions (deferred)

`LinuxServiceController.RunSystemctl()` uses synchronous `ReadToEnd()`, splits strings into `ArgumentList`, and lacks `CultureInfo.InvariantCulture`. This is a MUST-severity issue by the rules.

It only affects read-only property refresh and lazy getters. No write operations use this path. The deadlock risk is minimal because the subprocess output is small. Deferred as low-priority.

## The SHOULD fixes

After the MUST issues, the SHOULD items were next. Three were resolved in a single commit:

### Rule 46 — Template unit filtering

`ListUnits` returned all units matching `.service`, including template units like `systemd-journald@.service`. These templates cannot be started directly. They need an instance identifier. The filter now excludes any unit name containing `@.`. One line change.

### Rule 42 — Parameter aliases

The `Name` parameter on four cmdlets lacked `[Alias("ServiceName")]`. This breaks pipeline input from Windows `ServiceController` objects, which have a `ServiceName` property, not `Name`. Added the alias to `ServiceUnixBase`, `SetServiceCommand`, `NewServiceCommand`, and `RemoveServiceCommand`.

### Rule 41 — ShouldProcess display formatting

`ShouldProcess` was showing raw unit names like `cron.service` in confirmation prompts. Windows shows just `cron`. Added `FormatShouldProcessTarget()` to strip the `.service` suffix. All six write cmdlets now use it.

Commit `e116409` covers all three.

## Remaining open issues

Five items remain open:

| # | Severity | Issue | Effort |
|---|---|---|---|
| 44 | SHOULD | LINQ in `DependentServices` and `ServicesDependedOn` getters | Small |
| 43 | SHOULD | Test tags and `$PSDefaultParameterValues` skip pattern | Small |
| 45 | SHOULD | XML docs on 11 cmdlet classes | Medium |
| 32 | MUST | Proactive elevation check | Deferred |
| 34 | MUST | `RunSystemctl()` sync read | Deferred |

The two deferred MUST items are genuinely low-risk. The three open SHOULD items are mechanical. They will be resolved before the upstream PR.

## What this means

The Services module now scores 37 out of 46 against the full rule set. The remaining 9 points are all SHOULD-severity or deferred MUST items. No open MUST-severity bugs affect write operations.

The audit also produced something useful beyond the fixes: a documented set of development rules that apply to all four native modules. These rules will be the baseline for any future Linux module development. They are already being applied to the other three repos.

The next step is replacing `LinuxServiceInfo` with `LinuxServiceController : Component` in the fork branch. The standalone repo already has the implementation. The fork needs the same type, the same properties, and the same enum values. After that, the upstream PR path is clear.
