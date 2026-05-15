---
date: 2026-05-14  -0000
title: AI Reviewed Its Own Code — Linux Command Wrapping Part 17
toc: true
---

Part 16 ended with a conclusion. Stage 5 done (the list is still accurate, go figure), back to Stage 6. The C# binary modules are built, the GHA matrix is green, the code review is mostly resolved. Time to wrap up and talk about upstream PRs and RFCs.

But then something happened that is worth its own post.

I asked the AI that helped write the code to review its own output. All four C# modules at once. And it came back with 20 genuine bugs in code that compiled clean, passed its tests, and had already been through one human review pass.

This is the story of those bugs, what they say about AI-written code, and what they say about AI-as-reviewer.

## The experiment

There are four binary modules now. `LocalAccounts.Linux.Native` (P/Invoke into libc, user management). `ScheduledTasks.Linux.Native` (systemd timers, JSON). `NetTCPIP.Linux.Native` (BCL `NetworkInterface` plus `ip`). `Services.Linux.Native` (D-Bus `*-Service` cmdlets via `Tmds.DBus.Protocol`).

All four were written in AI-assisted sessions. The workflow was simple: describe what I need, the AI generates the code, I build and test, we go back and forth until it passes. The AI handled the boilerplate — the P/Invoke signatures, the D-Bus message construction, the JSON parsing. I handled the architecture decisions, the edge cases, the parts that need actual understanding of how systemd or `iproute2` work.

The code compiled at 0 warnings. Tests passed. GHA green. I was fairly satisfied.

Then I asked the AI: read all four repos and review them. Find everything wrong.

It found 21 issues. Twenty were real. One was a false positive.

## The deadlock that wasn't a deadlock (yet)

`LocalAccounts.Linux.Native` runs subprocesses for write operations — `useradd`, `groupmod`, that family. The read path uses P/Invoke, but writes still go through `Process.Start`. The review spotted this in a helper:

```csharp
string stdout = proc.StandardOutput.ReadToEnd();
string stderr = proc.StandardError.ReadToEnd();
proc.WaitForExit();
```

This is a classic pipe deadlock. If the child process writes enough stderr to fill the pipe buffer before stdout is drained, the child blocks on stderr while the parent blocks on stdout. Everyone waits forever.

This particular code works because `useradd` does not produce enough stderr to trigger it. It works by luck, not by design.

The fix is concurrent reads:

```csharp
var stdoutTask = proc.StandardOutput.ReadToEndAsync();
var stderrTask = proc.StandardError.ReadToEndAsync();
proc.WaitForExit();
```

What made this interesting: the same AI that wrote the buggy code in this file had already written the correct pattern in another file. Another helper used the async-read version from the start. The AI-as-writer did not propagate the pattern. The AI-as-reviewer, reading everything at once, flagged the inconsistency immediately.

That is the strongest argument for AI code review I have seen. The writer works file-by-file. The reviewer sees the whole picture.

## The command that succeeds while failing

`NetTCPIP.Linux.Native` has a helper for running `ip` commands:

```csharp
private static string RunProcess(string exe, string arguments)
{
    try { ... return stdout; }
    catch { return string.Empty; }
}
```

No exit code check. If `ip addr add` fails — address already exists, prefix invalid, not root — the error is swallowed. The cmdlet returns a clean empty string. The user sees success. Nothing happened.

The review called this a MUST fix. Obvious once you think about it. Easy to miss when you are focused on the happy path.

## The unit file injection that nobody tried

`ScheduledTasks.Linux.Native` writes systemd unit files via string interpolation:

```csharp
$"Description={description}\n" +
$"ExecStart={execStart}\n"
```

If the user provides a description with a newline in it — which `New-ScheduledTask` accepts — the generated unit file breaks. An attacker can inject arbitrary systemd directives.

The fix is simple:

```csharp
static string Sanitize(string s) => s.Replace('\n', ' ').Replace('\r', ' ');
```

Five lines. Prevents a class of bug that would be extremely hard to diagnose in production because the unit file looks fine when you open it in a text editor.

## Six D-Bus connections when you need one

`Services.Linux.Native` talks to systemd over D-Bus. Every public method opened its own connection:

```csharp
internal static void StartUnit(string unitName) { /* opens connection */ }
internal static void StopUnit(string unitName) { /* opens connection */ }
// ... six methods, six connections
```

Compound cmdlets like `Remove-Service` do stop + disable + daemon-reload. That is three connections for one command.

The fix: add overloads that accept an existing connection. The compound cmdlets open one and pass it around.

## The one false positive

Issue 2: "Services repo missing copyright headers." The review claimed every `.cs` file lacked `// Copyright (c) Microsoft Corporation.` 

It was wrong. Every file already had it. The reviewer somehow missed them. One false positive out of 21.

## What this means

Twenty-one issues. Twenty real. One false positive. None were syntax errors — the build catches those. None were wrong-output bugs — the tests catch those. Every single one was a pattern-level issue: inconsistent conventions, missing error handling, unnecessary resource churn.

That is exactly the gap the review was designed to fill. AI-as-writer is good at translating requirements into working code. It is bad at cross-cutting consistency — making sure the same pattern is used in two files in different directories. AI-as-reviewer reads everything at once and spots the mismatch immediately.

The code review experiment was supposed to be a quick detour before wrapping up Stage 6. Instead it became the most productive hour of the week. Twenty bugs I did not know I had, fixed in one session, validated by a first-pass GHA build that turned green in 30 seconds.

---

**Some side notes from that session, worth remembering:**

- **AI sessions now follow a fixed pipeline.** Read AGENTS.md for conventions. Write code. Review it. Fix what the review found. Build at 0W/0E. Commit. Push. GHA. The review step caught all 20 issues before they ever reached CI. That first-pass GHA green on Services.Linux.Native — a module with 2 git commits that had never seen a runner — was not luck. It was the gate doing its job.

- **AGENTS.md is accumulating project memory.** Conventions from earlier sessions (`ConfigureAwait(false)`, `ArgumentList`, `Sanitize()`, the async-read pattern) live in AGENTS.md. Every session re-reads it. The AI does not have to re-learn. And the review step enforces that the conventions were actually followed.

- **GitHub auth trick.** `gh auth login` needs `read:org` scope. The PAT in the Windows Credential Manager does not have it. One-liner workaround: `git credential fill` extracts the PAT, set `$env:GH_TOKEN`, and `gh` works. No interactive login. Saved in AGENTS.md so every future session just works.

- **Code review as CI pre-filter.** Not a replacement for build or tests. Build catches syntax. Tests catch output. Code review catches the structural issues between them. That is the right niche.



