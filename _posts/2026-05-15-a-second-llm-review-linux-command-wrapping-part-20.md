---
date: 2026-05-15
title: A Second LLM Review — Linux Command Wrapping Part 20
toc: true
---

Part 17 ended with the AI review experiment. One LLM reviewed the code it helped write. Twenty-one issues found, twenty real, one false positive. All twenty fixed. The code compiled clean. Tests passed. GHA green.

That should have been the end of the review cycle.

Instead I brought in a second LLM. Gave it a specific role: be a code reviewer. Read all four repos. Find everything wrong. No code generation. No feature work. Just review.

It came back with seven more issues.

Then I asked it to fix them. It did. Four commits across four repos. All pushed. All building.

Now I need to verify that the fixes actually work. That is the next session: manual testing in a real Linux environment.

## The second review

The first review was the AI reviewing its own output. This time I used a different model with a different prompt. The instructions were explicit:

> You are a code reviewer. Read every `.cs` file across these four repos. Find issues. Do not write code. Do not suggest features. Only flag problems.

The scope was the same: all 62 `.cs` files across LocalAccounts, ScheduledTasks, NetTCPIP, and Services. No tests. No CI configs. Just the source.

It found seven issues. Three MUST-fix. Two SHOULD. Two MINOR.

## The three that mattered

**Issue 22: Missing copyright headers.** Forty-one files across three repos had no `// Copyright (c) Microsoft Corporation.` header. One repo had them. Three did not. The first review actually flagged this as a false positive — it claimed the files had headers when they did not. The second reviewer got it right.

This is a MUST fix not because of legal risk — these are MIT-licensed open source modules. It is a MUST fix because consistency matters. If one repo has the header and three do not, the pattern is broken. And broken patterns are where other bugs hide.

**Issue 23: Pipe deadlock in LocalAccounts.** The `AccountHelpers.Run()` method read stdout and stderr sequentially:

```csharp
string stdout = proc.StandardOutput.ReadToEnd();
string stderr = proc.StandardError.ReadToEnd();
proc.WaitForExit();
```

This is the same pattern the first review caught in Part 17. But the first review missed that the *other* helper method — `RunWithStdin()` — had the same bug. The first reviewer found one instance. The second reviewer found both.

The fix is the same: concurrent reads.

```csharp
var stdoutTask = proc.StandardOutput.ReadToEndAsync();
var stderrTask = proc.StandardError.ReadToEndAsync();
System.Threading.Tasks.Task.WaitAll(stdoutTask, stderrTask);
proc.WaitForExit();
```

**Issue 24: Pipe deadlock in NetTCPIP.** The `RunProcess()` helper in `IpHelpers.cs` redirected stderr but never read it:

```csharp
var stdout = proc.StandardOutput.ReadToEnd();
proc.WaitForExit();
```

This is worse than sequential reads. This is a guaranteed deadlock if the child process writes more than ~64KB to stderr. The `ip` command can produce verbose error output. Under the right conditions — invalid arguments, permission denied, missing capabilities — this would hang forever.

The fix required changing the return type to include stderr, then reading both streams concurrently.

## The four that should not have slipped through

The remaining four were SHOULD and MINOR. Not dangerous. Just wrong.

**Issue 25:** `SetScheduledTaskCommand` stub declared `SupportsShouldProcess = true`. Stubs do not perform state-changing operations. They should not declare ShouldProcess. This was a convention drift — the stub was written before the convention was established, and nobody caught it.

**Issue 26:** Same issue in Services. `SuspendServiceCommand` and `ResumeServiceCommand` stubs both declared `SupportsShouldProcess`. Same fix: remove the attribute.

**Issue 27:** A typo. `"UseraaddFailed"` instead of `"UserAddFailed"` in the error ID for `NewLocalUserCommand`. Harmless — the string is only used for error categorization, not for logic. But it looks unprofessional.

**Issue 28:** `SetScheduledTaskCommand` stub wrote an `ErrorRecord` instead of throwing `NotImplementedException`. The convention for stubs is `throw new NotImplementedException("Cmdlet-Name is not supported on Linux.")`. This stub was an outlier — it used `WriteError` with a `NotSupportedException`. Functionally equivalent. Conventionally wrong.

## The fix session

I asked the second LLM to fix all seven issues. It produced the patches. I reviewed them, committed, and pushed.

The commits:

| Repo | Commit | Fixes |
|---|---|---|
| LocalAccounts.Linux.Native | `e23258b` | #23 (deadlock), #27 (typo) |
| NetTCPIP.Linux.Native | `2e56574` | #22 (headers), #24 (deadlock) |
| ScheduledTasks.Linux.Native | `a1c1ea4` | #22 (headers), #25 (stub), #28 (stub) |
| Services.Linux.Native | `e1b44eb` | #22 (headers), #26 (stubs) |

Total: 41 files touched across 4 repos. All pushed. All building.

## Two reviewers, different results

The first LLM found 20 real issues. The second found 7 more. That is a 26% increase — not trivial.

But the interesting thing is not the count. It is the *type* of issues each one found:

| First LLM found | Second LLM found |
|---|---|
| Missing error handling | Missing copyright headers (consistency) |
| Wrong API usage | Second instance of a known pattern (exhaustiveness) |
| Resource leaks | Convention drift across repos (cross-cutting) |
| Type mismatches | Typos in error IDs (attention to detail) |

The first LLM was better at finding *new* patterns of bugs. The second was better at finding *all* instances of a known pattern. The first caught the sequential pipe read in one file. The second caught the same pattern in another file in the same repo.

This is not about which model is better. It is about different models having different blind spots. The first review missed exhaustiveness. The second review missed the first review's false positive on headers. Neither is perfect. Together they are better.

## The final tally

Twenty-eight issues total. Twenty-seven resolved. One deferred.

The deferred one is #21 — namespace style. LocalAccounts and Services use block-scoped `namespace Foo { }`. ScheduledTasks and NetTCPIP use file-scoped `namespace Foo;` (C# 10+). Thirty-three files would need to change. Zero functional impact. Cosmetic. Deferred.

## What is next

The code review cycle is done. Two LLMs. Twenty-eight issues. Twenty-seven fixed. One deferred.

But the fixes have not been tested in a real Linux environment. The GHA matrix runs in containers, and the builds pass. But I want to verify that the deadlock fixes actually work under load, that the stubs behave correctly, and that the copyright headers are in place.

The next session: manual testing in a Linux environment. Docker compose across the 5-distro matrix. Real `useradd`, real `ip`, real `systemctl`. Verify that the code does what it is supposed to do.

After that, the upstream PR path is clear:

1. Rebase the fork branch on latest upstream PowerShell master
2. Sign the Microsoft CLA
3. File an RFC at `PowerShell/PowerShell-RFC`
4. Submit the upstream PR

The code is ready. The review is done. Now I need to make sure it works.
