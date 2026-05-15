---
date: 2026-05-08  -0000
title: Crescendo revisited - Linux Command Wrapping Part 12
toc: true
---

Part 11 ended on a note of productive discomfort: twelve modules, clean PSSA, 1513 tests passing, and an honest admission that "tests pass" is not the same as "actually works." The scaffold was up. The next question was what to do with it.

Before diving into Stage 3 - implementing the remaining stubs - I wanted to sit with something that had been bothering me since Part 4. Crescendo. I gave it a fair try at the beginning of this series, built a JSON config for `lsblk`, ran into some quirks, and ended up shipping a half-working wrapper that I then quietly ignored in favour of calling `lsblk` directly from each cmdlet. Twelve modules later, that decision had calcified into a pattern.

Was it the right pattern? I did not actually know. So Stage 2 was an audit.

## The question

Across all twelve modules, where is CLI output parsing duplicated, brittle, or inconsistent - and would a proper Crescendo-style wrapper improve things?

Worth saying what "Crescendo-style" means here, because after Part 4 I am not using `Export-CrescendoModule` to generate code anymore. That tool overwrote my existing `lsblk.psm1` with a 2-line stub the moment I pointed it at the wrong file. Once was enough. The `.crescendo.json` design files stay as documentation of intent. The actual wrappers are hand-written private helper modules that follow the same structure Crescendo would generate - just without the code generation step that keeps biting me.

## The audit

Eight modules use CLI tools in a way that could plausibly benefit from a shared wrapper. Here is how they each turned out:

| Module | Tool(s) | JSON output? | Decision |
|---|---|---|---|
| Storage.Linux | `lsblk` | Yes - `--json` | Fix the existing wrapper |
| NetTCPIP.Linux | `ip`, `ss` | `ip` yes / `ss` no | Migrate `ip` |
| NetAdapter.Linux | `ip` | Yes | Migrate `ip` |
| DnsClient.Linux | `dig`, `resolvectl` | Yes - `resolvectl --json=short` | ~~Keep custom parsing~~ Migrated (see addendum) |
| PowerShell.Management.Linux | `systemctl` | Yes - `--output=json` for list ops | ~~Keep custom parsing~~ Migrated (see addendum) |
| ScheduledTasks.Linux | `systemctl` | Yes - `--output=json` for list ops | ~~Keep custom parsing~~ Migrated (see addendum) |
| PowerShell.LocalAccounts.Linux | `getent` | No | Keep custom parsing |
| PrintManagement.Linux | `lpstat`, `lpadmin` | No | Keep custom parsing |

The pattern that jumps out: JSON-capable tools are candidates, text-only tools are not. Not a surprising conclusion, but useful to have it stated explicitly rather than assumed.

The other thing that jumps out: five of the eight are "keep" decisions. Crescendo - or rather, the structured-output wrapper approach it enables - is not universally applicable. Sometimes the tool is just text. That is the situation.

## Storage.Linux - the wrapper that was already broken

This one was embarrassing in a productive way.

Part 4 built a Crescendo wrapper for `lsblk`. It ran. In the sense that it called `lsblk --json` and piped through `ConvertFrom-Json`. What I did not notice at the time was that the parameter map was completely unwired:

```powershell
$__PARAMETERMAP = @{}
param()
```

Empty. No parameters. The `--bytes` flag - critical for getting sizes as integers rather than strings like `465.8G` - was in the JSON config file but never made it into the generated code. And `Get-Disk`, `Get-Partition`, and `Get-Volume` had all quietly gone around the wrapper entirely, calling `lsblk` inline. Three cmdlets, three independent invocations, three opportunities to get it wrong. `Get-Partition` had indeed gotten it wrong - no `--bytes`, so sizes came back as strings. Anything that compared or sorted by size was silently broken.

Once I actually looked at it, the fix was straightforward. `Functions/Private/Get-LsBlkData.ps1` with `--json`, `--bytes`, and a `--all` switch. `Functions/Private/Expand-LsBlkDevices.ps1` for the tree-flattening logic that had been buried inside `Get-Volume`'s function body, which is not where a reusable function belongs. Then update all three cmdlets to call `Get-LsBlkData` instead of `lsblk` directly.

The `.psm1` loads `Functions/Private/` before `Functions/` so the helpers are available when the cmdlet files load. Obvious when you think about it. Less obvious when you are adding a `Private/` folder for the first time and the helpers silently fail to load because they were dot-sourced in the wrong order.

## NetTCPIP.Linux - the N+1 problem

This one was more interesting.

`Get-NetRoute` was building its route table by calling `ip -json route show` twice (IPv4 and IPv6), then for each route entry, calling `ip -json link show <dev>` individually to look up the `ifindex`. On a system with twenty routes, that is twenty-two `ip` calls per `Get-NetRoute` invocation.

The fix was a private `Crescendo/ip.psm1` with three helpers:

```powershell
function Get-IpAddr    { ip -json addr show | ConvertFrom-Json }
function Get-IpRoute   { param([switch]$IPv6) ... }
function Get-IpLink    { param([switch]$Statistics) ... }
```

`Get-NetRoute` now calls `Get-IpLink` once, builds a hashtable from interface name to `ifindex`, and looks up each route from the map. One call instead of N+1:

```powershell
# before - per route:
$link = ip -json link show $r.dev | ConvertFrom-Json
$ifindex = $link[0].ifindex

# after - once:
$linkMap = @{}
Get-IpLink | ForEach-Object { $linkMap[$_.ifname] = $_.ifindex }
# ...then per route:
$ifindex = $linkMap[$r.dev]
```

Not complicated. Worth doing.

`ss` - which backs `Get-NetTCPConnection` - has no JSON mode. The text parsing stays.

## NetAdapter.Linux - same pattern, simpler

`Get-NetAdapter` and `Get-NetAdapterStatistics` were both calling `ip -json link show` independently. Same tool, zero sharing.

A private `Crescendo/ip.psm1` for NetAdapter.Linux (its own file - each module is self-contained, not pulling in another module's helpers):

```powershell
function Get-IpLink { param([switch]$Statistics) ... }
```

`Get-NetAdapter` calls `Get-IpLink`. `Get-NetAdapterStatistics` calls `Get-IpLink -Statistics`. Done.

## What Crescendo cannot fix

Five of the eight modules stayed as custom parsing, and that is the right call. But it is worth naming why.

`dig` is the uncomfortable one. `dig` output has structure - well-defined sections, typed records. But it is designed for humans. No `--json` flag. The `+format=json` experiment that appeared briefly in some versions was not standardised. So `Resolve-DnsName` stays a text parser.

`systemctl list-units` is in the same category. Or so I thought at the time - see addendum.

`getent passwd` is seven colon-separated fields. Not going to change. The parsing is four lines. It does not need a wrapper.

`lpstat` is perhaps the worst: different flags return different text formats, and joining them into one object per printer requires three separate calls with three different parsers. There is no JSON mode. CUPS has a REST API, but it needs authentication and local socket access. The `lpstat` wrapper stays.

## Numbers

Three modules changed:

- `Storage.Linux`: commit `47c3325`
- `NetTCPIP.Linux`: commit `d4eb81c`
- `NetAdapter.Linux`: commit `510519c`

PSScriptAnalyzer on all three: 0 errors, 0 warnings. Pester on Windows: 804 tests, 0 failures (Linux-only modules, all correctly skipped). Pester in WSL2: 533+167+171 = 871 tests, 0 failures, 1 expected skip.

## The lesson I keep re-learning

Crescendo is a tool for one specific problem: wrapping a CLI tool that produces structured output and making it look like a proper PowerShell cmdlet. When the tool supports that, it is the right abstraction. When it does not, no amount of configuration will make it fit.

The harder lesson: the first implementation is rarely the right one. The Crescendo wrapper from Part 4 worked in the sense that it ran without throwing. It did not work in the sense that every cmdlet that depended on it had quietly gone around it, because it was not properly wired up. That is a comfortable kind of broken - nothing fails loudly, so nothing gets fixed. Going back through twelve modules looking for that kind of quiet brokenness does not feel exciting. It does not produce new cmdlets or new features. It produces code that works more correctly in cases the tests did not catch. That is worth doing too.

## Addendum - three more migrations, and what I got wrong

The audit above was wrong about three modules. I published it, then immediately discovered the errors when I actually ran the commands against WSL2. Here are the corrections, embarrassing details included.

**`systemctl list-units` and `systemctl list-timers` do support `--output=json`.**

The post said they did not. That sentence was wrong. I had based it on memory and a quick scan of the flags - not on actually running the commands. Running them produced:

```json
[
  {"unit":"apparmor.service","load":"loaded","active":"inactive","sub":"dead","description":"Load AppArmor profiles"},
  ...
]
```

Clean JSON array. `Get-Service` and `Get-ScheduledTask` have now been rewritten to use it.

`Get-ScheduledTask` also had an N+1 problem I had not noticed: it called `systemctl show <unit>` once per timer to get `ActiveState`, `Description`, and `FragmentPath`. Bulk `systemctl show unit1 unit2 unit3 ...` works - units separated by blank lines - so the rewrite makes one bulk call instead of N per-timer calls.

**`dig` is not installed in WSL2. `resolvectl` is.**

The post said `dig` is the right tool for `Resolve-DnsName`. The actual situation: `dig` requires installing `dnsutils`, which is not in the base Ubuntu WSL2 image. `resolvectl` ships with systemd-resolved and is always present on modern distros.

More importantly: `resolvectl query --json=short --type=<TYPE>` works for A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, and TXT records:

```json
{"key":{"class":1,"type":1,"name":"dns.google"},"address":[8,8,8,8]}
{"key":{"class":1,"type":1,"name":"dns.google"},"address":[8,8,4,4]}
```

That is cleaner than parsing `dig` section headers. The `Resolve-DnsName` implementation has been rewritten to use `resolvectl`. The `dig`-based text parser is gone. PTR arpa conversion is now automatic - pass the plain IP, get the right answer.

Three more commits:

- `DnsClient.Linux`: commit `4f8ac6e`
- `ScheduledTasks.Linux`: commit `45191b0`
- `PowerShell.Management.Linux`: commit `a755f09`

176 additional tests passing in WSL2. 0 failures.

The lesson from the first session applies to the addendum too. The conclusions about `systemctl` and `dig` were wrong for exactly the same reason as the broken `lsblk` wrapper: I did not run the commands in the environment they were meant to run in. Running it would have told me immediately.

## Next

Stage 3. The stubs that currently just emit `Write-Warning "not yet implemented"` - several of them are genuinely implementable. `Find-NetRoute` via `ip route get`. `Get-PrintConfiguration` via `lpoptions`. `Set-TimeZone` via `timedatectl`. `New-Service` via unit file creation and `systemctl`.

None of those are radical departures from what has been built already. They are just more of the same work, applied to the next batch of cmdlets on the list.

There are also two new modules on the list: `SmbShare.Linux` and `PackageManagement.Linux`. Both need new repos, new scaffolding, new decisions about what is in scope.

Onwards.



