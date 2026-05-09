---
title: Real-world scenarios — Linux Command Wrapping Part 16
toc: true
---

Part 15 ended with "the GHA workflows have not yet produced a confirmed green matrix across all five distros in their final state." That was honest. The next logical step was to expand the test suites before declaring the matrix confirmed — because running tests you know are thin feels like cheating.

So that is what happened. Test expansion across all three Native modules, focused on scenarios that reflect actual use rather than just exercising the happy path.

## What was missing

The existing tests for all three modules were honest about what they covered: surface checks, factory cmdlets, WhatIf safety, basic integration (register a task, list it, remove it). The kind of tests you write first to prove the module loads and does not immediately explode.

What was missing was anything resembling how someone would actually use these modules in practice.

For `LocalAccounts.Linux.Native` those gaps were filled in a previous session — service account provisioning, bulk operator group management, account expiry — and that is documented in `tests/LocalAccounts.Linux.Native.Tests/`. About 140 tests now. Still nothing wrong with 63.

For `ScheduledTasks.Linux.Native` and `NetTCPIP.Linux.Native` the expansion happened now.

## ScheduledTasks: what was added

The existing tests registered a daily task, listed it, enabled and disabled it, and cleaned up. Fine. But a weekly trigger is not the same as a daily trigger in systemd terms, and the `OnCalendar=` expression format for weekly schedules is different enough that it is worth testing explicitly.

**Weekly trigger with specific days.** `New-ScheduledTaskTrigger -Weekly -At '02:30' -DaysOfWeek Monday,Wednesday,Friday` should produce a timer file containing `Mon`, `Wed`, and `Fri`. This is a real-world scheduling pattern — every working day, or a specific subset. The test registers the task and reads the timer file directly to assert the calendar expression.

**AtStartup trigger.** Already tested at the factory level (the OnCalendar property equals `boot`). Now tested end-to-end: register a task with `AtStartup`, confirm the unit file exists and contains `boot`. Small addition but completes the coverage.

**Pipeline bulk disable/enable.** The Windows `Disable-ScheduledTask` accepts pipeline input from `Get-ScheduledTask`. If that does not work, scripts that do `Get-ScheduledTask -TaskName 'backup*' | Disable-ScheduledTask` are silently broken. The test creates two tasks with a shared name prefix, then pipes them through disable and re-enable. If the pipeline binding is wired up wrong, it fails here.

**`Start-ScheduledTask` actually runs.** This is the test I was least sure about. The issue is that `Start-ScheduledTask` calls `systemctl start <name>.service` — and inside a Docker container with `--privileged`, systemd may or may not be PID 1. Most CI containers do not have a running systemd. Running unit files depends on systemd being active.

The approach: detect systemd availability in `BeforeDiscovery` by checking for `/run/systemd/private` (which only exists when systemd is actually running as the init). If that path is absent, the whole describe block is skipped. When systemd is present, the test registers a task that runs `/bin/touch /tmp/marker`, calls `Start-ScheduledTask`, and waits up to 5 seconds for the marker file to appear. Then it checks `Get-ScheduledTaskInfo` for `LastRunTime` within the last 2 minutes.

This is a conditional test. On a bare container with no init system it skips cleanly. On a system where systemd is actually running — a real Linux machine, or a container configured to boot with systemd — it validates the full execution path. Both outcomes are informative.

## NetTCPIP: what was added

**Loopback alias add/remove.** The documentation-range address `127.0.1.99/32` on `lo` is a safe test target — no routing side effects, cleaned up immediately after. The test adds it with `New-NetIPAddress`, confirms it appears in `Get-NetIPAddress` and in `Get-NetIPConfiguration -All`, then removes it and confirms it is gone. Four assertions, one round-trip, exercises both the write path and the read path together.

**Route round-trip.** Same pattern with `192.0.2.0/24` — RFC 5737 documentation range, guaranteed to not collide with anything real. Add the route, confirm `Get-NetRoute` returns it, remove it, confirm it is gone. The test discovers the interface name dynamically (first non-loopback IPv4 interface) rather than hardcoding `eth0` — because container interface names vary.

**Real TCP listener.** The existing `Get-NetTCPConnection` tests checked that LISTEN sockets have `RemotePort 0` and that `State` values are valid strings. But they relied on whatever sockets happened to be open in the container. That is fragile — a minimal container might have nothing listening, making the LISTEN test vacuous.

The fix: open a `System.Net.Sockets.TcpListener` in `BeforeAll` on a specific port (19753, high enough to not conflict with anything real), run the assertions against that listener, and stop it in `AfterAll`. Now the test controls its own condition rather than relying on ambient state. `Get-NetTCPConnection -State Listen` should find port 19753 with `LocalAddress 127.0.0.1` and `RemotePort 0`. This test runs as any user — opening a TCP port in userspace does not require root.

## The `$script:hasSystemd` guard

Worth a short digression. Pester 5 has a somewhat subtle scoping rule: skip conditions in `Describe -Skip:()` are evaluated at discovery time, before `BeforeAll` runs. So any variable you reference in `-Skip:()` must be set in `BeforeDiscovery`.

`$script:isRoot` was already set there. I added `$script:hasSystemd`:

```powershell
BeforeDiscovery {
    $script:isRoot     = $IsLinux -and ((& id -u) -eq '0')
    $script:isLinux    = $IsLinux
    $script:prefix     = 'stn_test'
    $script:taskName   = "$($script:prefix)_daily"
    $script:hasSystemd = $IsLinux -and (Test-Path '/run/systemd/private')
}
```

`/run/systemd/private` is the canonical indicator that systemd is running as the init system. It is a directory that systemd creates at startup and removes at shutdown — it will not be there if systemd is not PID 1. Checking this at discovery time means the `Start-ScheduledTask runs the service` block skips immediately if systemd is absent, rather than registering the task, calling `systemctl start`, getting an error, and then failing with a confusing message.

This is the kind of thing that only seems obvious after you have had a test fail with "Failed to connect to bus: No such file or directory" in a CI container that had no init system. The skip condition makes the intent clear: this test requires a running systemd, not just root access.

## Numbers after expansion

| Module | Tests before | Tests after | New scenarios |
|---|---|---|---|
| `LocalAccounts.Linux.Native` | 116 | ~140 | Service account, bulk ops, expiry |
| `ScheduledTasks.Linux.Native` | 63 | ~100 | Weekly, AtStartup, pipeline disable, Start run |
| `NetTCPIP.Linux.Native` | ~40 | ~65 | Loopback alias, route round-trip, real listener |

The counts are approximate — some tests are `It` blocks inside `-ForEach` loops which expand at runtime. The point is that each module has meaningful new coverage beyond what was there before.

## READMEs updated

All three Native repos have updated READMEs with a test scenario table showing what each describe block covers and what scope it runs at (everywhere / Linux any user / Linux + root). The version history got a `0.2.0` entry. Consistent with what I said in Part 9 about documentation being part of the work, not something you do after the work.

## What still needs to happen

The GHA matrix runs are queued — pushed to all three repos as part of this session. The question is whether any of the new tests expose regressions or environmental assumptions that do not hold on all five distros.

The most likely point of failure: the route round-trip test assumes `iproute2` is installed and the container interface is not called something unexpected. The testinfra images were built to include `iproute2`, so that should be fine. The loopback alias test depends on `ip addr add` succeeding on the `lo` interface — `--privileged` makes that available, and the workflow already runs `--privileged`.

The systemd-dependent test skips on containers without systemd. That should produce a skip count rather than a failure count across all five distros.

If the matrix comes back green (or green + expected skips), the next step is the RFC question — what it takes to upstream these to PS7, and whether now is the right time to start that conversation.

That is a bigger question than a test expansion. We will get to it.
