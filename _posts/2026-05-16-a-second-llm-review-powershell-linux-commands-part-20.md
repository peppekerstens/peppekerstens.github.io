---
date: 2026-05-16 10:00:00 -0000
title: a second llm review — powershell linux commands part 20
toc: true
redirect_from:
  - /a-second-llm-review-linux-command-wrapping-part-20/
---

I thought the code review for the native modules was finished. Twenty-one issues had been identified, twenty were resolved, and the namespace style inconsistency was deferred as a minor cosmetic detail. The builds were green. The Pester matrix was green. It felt like the "done" definition had been met.

Then I ran a second LLM pass.

It is a strange feeling when you've spent weeks refining a build only for a fresh prompt to highlight a deadlock risk you completely overlooked. The second review didn't just find a few typos; it found seven new issues, some of them critical.

## The deadlock risk

The most alarming find was in `LocalAccounts.Linux.Native`. The way I was reading the stdout and stderr streams in `AccountHelpers.Run()` and `RunWithStdin()` was sequential. 

The problem is a classic .NET pitfall: if the subprocess fills its stderr buffer while the parent is still waiting to read stdout, the subprocess blocks. The parent, meanwhile, is still waiting for stdout to finish. Neither moves. The process deadlocks.

I had spent so much time on the P/Invoke layer and the D-Bus logic that I'd ignored the basic plumbing of process I/O. I had to refactor the reading logic to use concurrent asynchronous reads for both streams. This is now the standard across all four native repos.

## The "MUST" and "SHOULD" list

Beyond the deadlocks, the review flagged a few other gaps:

- **Copyright Headers**: None of the 43 files across the three native modules had copyright headers. A simple omission, but a "MUST" for any code intended for the Microsoft upstream tree.
- **Stderr Neglect**: In `NetTCPIP.Linux.Native`, the `RunProcess()` method was simply ignoring stderr. If a command failed with a descriptive error on stderr, my module would either throw a generic error or simply report failure without context.
- **Stub Safety**: A few stubs, like `SetScheduledTaskCommand`, were writing `ErrorRecord` instead of throwing a proper `NotImplementedException`. This might seem pedantic, but it changes how the calling script handles the failure.

## The cleanup session

I spent the next few hours across all four repos—LocalAccounts, ScheduledTasks, NetTCPIP, and Services—hunting down these issues.

The result was a series of focused commits:
- `a1c1ea4` and `e1b44eb` for the copyright headers and stub fixes.
- `e23258b` to resolve the deadlock and fix a typo (`UseraaddFailed` $\rightarrow$ `UserAddFailed`).
- `2e56574` to ensure stderr is actually read and reported.

## Where it stands now

The la lundry list is finally clean. Twenty-eight issues in total, twenty-seven resolved. The only survivor is the namespace style issue (#21), which remains deferred as it has zero functional impact on the binaries.

All eight GHA workflows (four builds and four pester matrices) are green. The native layer is, for the first time, actually "production ready" by the standards of the upstream project.

The focus now shifts entirely to the fork. The `feature/service-unix-systemctl` branch has the ported code and the tests. The next steps are the administrative hurdles: rebasing on the latest upstream master, signing the CLA, and filing the RFC.

The native modules are ready. Now it is just a matter of getting them into the tree.
