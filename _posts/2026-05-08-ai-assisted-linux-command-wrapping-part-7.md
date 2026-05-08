---
title: Letting AI do the heavy lifting - Linux Command Wrapping Part 7
toc: true
---

So. It has been a while.

Part 6 ended with a somewhat functional Show-Command pseudo-interface and a promise that a proper TUI replacement would likely become a multi-article series. That was July 2025. It is now May 2026. You do the math.

## What happened

Nothing dramatic. Life happened. Work happened. The usual suspects.

I did tinker a bit here and there. Opened some files, read some code, closed them again. Stared at the list of remaining modules. Felt slightly overwhelmed. Closed the laptop.

The thing about side projects is that when they are going well, they are great. When they stall, even a small bump feels like a wall. The list of remaining modules is not small:

- `NetTCPIP.Linux` — `Get-NetIPAddress`, `Get-NetRoute`, all the networking stuff
- `PowerShell.Management.Linux` — service management, computer info
- `PowerShell.Security.Linux` — `Get-Acl`, `Set-Acl`
- `PowerShell.LocalAccounts.Linux` — user and group management
- `Update.Linux` — wrapping `apt` as a PSWindowsUpdate peer
- and more...

Each of those is weeks of work if done properly. Research, implementation, Pester tests, examples, documentation, blog post. It adds up fast.

And I still believe in the goal. The cmdlet gap between Windows PowerShell and Linux is still very much there. Nobody else seems to be sprinting to close it either. Evgenij Smirnov's call to action from the 2025 Summit still rings true.

## Enter AI

I have been experimenting with AI tooling at work for a while now. Mostly code review, explaining unfamiliar codebases, that sort of thing. Nothing groundbreaking.

At some point it occurred to me that the bottleneck on this project is not insight or direction — I know exactly what needs to be built and roughly how. The bottleneck is time and the sheer amount of repetitive scaffolding involved: stub generation, manifest files, Pester test files, README sections, example scripts. Boring but necessary work that does not require creativity but does require hours.

So I decided to try using [OpenCode](https://opencode.ai) with Claude as an accelerator. Not to replace my thinking, but to do the legwork.

## Being honest about this

I want to be upfront about what this means for the rest of the series.

Posts 1 through 6 were written entirely by me, sitting at my keyboard, working things out as I went, typos and all. The code in those posts reflects my actual exploration: hitting dead ends with proxy functions, discovering that `-Filter` combined with `-Exclude` silently breaks on Windows, that sort of thing.

From part 8 onwards, the implementation work has been significantly accelerated by AI. I describe what I want, we iterate, it writes code, I review it, we test it — on Windows and via WSL2. The decisions are still mine. The direction is still mine. But I am not pretending I typed every line of every function and test file myself.

Whether that matters to you probably depends on why you are reading this. If you are here for the concepts and patterns — how to wrap Linux CLI tools as PowerShell cmdlets, how to structure cross-platform modules, how to handle Pester across different versions — those are still valid and documented in the posts that follow. If you wanted a pure solo craftsman effort, well, that would have taken another year and there would be fewer posts.

Personally I think this is just a sensible way to work in 2026. The code gets reviewed, the tests get run, the bugs get found and fixed. The result is the result. OpenCode and Claude are my development tools now, alongside VS Code and PowerShell ISE and all the others I have accumulated over the years.

## What AI is actually good at here

Keeping things consistent across modules. Once the first module was done properly, every subsequent module needed the same structure: Linux-only guard in `.psm1`, `BeforeDiscovery` in test files, `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }`, `param()` before anything else in example scripts, `Where-Object` instead of `-Filter -Exclude` in `.psm1`, and so on. Remembering all of that across sessions without forgetting one item is exactly the kind of thing AI handles well and humans handle poorly at 10pm.

Generating stubs. The `Storage` module has 161 cmdlets. Writing 157 nearly-identical stub functions by hand is not a good use of anyone's time.

Finding bugs I would have found eventually anyway. The PSPath provider prefix problem with pipeline input — passing `Get-ChildItem` output to a custom function, only to discover that `FileInfo.PSPath` looks like `Microsoft.PowerShell.Core\FileSystem::/etc/hosts` and `stat` cannot deal with that. That is the kind of thing you discover by running the tests, and AI is helpful at suggesting the fix once you have identified the problem.

## What AI is not good at here

Knowing whether the approach is right. That is still mine to decide. When I said the functions should use Linux-native names (`Get-LinuxAcl`) and export the Windows names as aliases (`Get-Acl`), that was a deliberate choice based on readability and intent. AI would have just implemented whichever I asked for first.

Knowing the constraints of the environment. Things like "this WSL2 instance does not have `getfacl` installed" or "Pester 5.3.3 on Windows has that specific `$PSScriptRoot` quirk at discovery time" — those required actually running things and observing results. The tools are there to help once you know what the problem is.

Writing in my voice. That is presumably obvious from reading this post versus the ones that follow it.

## What is next

Parts 8 onwards cover the actual module implementations. The writing style in those posts is different from the earlier ones — more structured, more technical, less rambling. That is partly because the AI helped write them and partly because at that point I was already deep enough into the project that the exploratory phase was over.

Starting with `Storage.Linux` in part 8, which turned out to be more interesting than expected. 161 cmdlets, 4 implemented, 157 stubs, and one very annoying bug involving `lsblk` and human-readable size strings.
