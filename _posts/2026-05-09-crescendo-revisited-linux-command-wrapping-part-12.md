---
title: Crescendo revisited — Linux Command Wrapping Part 12
toc: true
---

Part 11 ended on a note of productive discomfort: twelve modules, clean PSSA, 1513 tests passing, and an honest admission that "tests pass" is not the same as "actually works." The scaffold was up. The next question was what to do with it.

Before diving into Stage 3 — implementing the remaining stubs — I wanted to sit with something that had been bothering me since Part 4. Crescendo. I gave it a fair try at the beginning of this series, built a JSON config for `lsblk`, ran into some tooling quirks, and shipped a half-working wrapper that I then ignored in favour of calling `lsblk` directly from each cmdlet. Twelve modules later, that decision had calcified into a pattern: every module that needed a CLI tool just called it inline.

That is not necessarily wrong. But it is worth auditing.

## The question

The question for Stage 2 was: across all twelve modules, where is CLI output parsing duplicated, brittle, or inconsistent — and would a proper Crescendo-style wrapper (or a clean hand-written equivalent) improve things?

It is worth being precise about what "Crescendo-style" means here. After the adventures documented in Part 4, I am not using `Export-CrescendoModule` to generate code. That tool overwrote my existing `lsblk.psm1` with a 2-line stub the moment I pointed it at the wrong file. Lesson learned. The `.crescendo.json` design files stay as documentation of intent. The actual wrappers are hand-written private helper modules that follow the same structure Crescendo would generate — but without the code generation step that keeps burning me.

## The audit

Eight modules use CLI tools in a way that could plausibly benefit from a shared wrapper. Here is how they each turned out:

| Module | Tool(s) | JSON output? | Decision |
|---|---|---|---|
| Storage.Linux | `lsblk` | Yes — `--json` | **Fix the existing wrapper** |
| NetTCPIP.Linux | `ip`, `ss` | `ip` yes / `ss` no | **Migrate `ip`** |
| NetAdapter.Linux | `ip` | Yes | **Migrate `ip`** |
| DnsClient.Linux | `dig`, `resolvectl` | Yes — `resolvectl --json=short` | ~~Keep custom parsing~~ **Migrated** (see addendum) |
| PowerShell.Management.Linux | `systemctl` | Yes — `--output=json` for list ops | ~~Keep custom parsing~~ **Migrated** (see addendum) |
| ScheduledTasks.Linux | `systemctl` | Yes — `--output=json` for list ops | ~~Keep custom parsing~~ **Migrated** (see addendum) |
| PowerShell.LocalAccounts.Linux | `getent` | No | Keep custom parsing |
| PrintManagement.Linux | `lpstat`, `lpadmin` | No | Keep custom parsing |

The pattern that jumps out immediately: JSON-capable tools are candidates, text-only tools are not. That is not a surprising conclusion, but it is useful to have it stated clearly rather than implicit.

The other pattern: five of the eight are "keep custom parsing" decisions. Crescendo — or rather, the structured-output wrapper approach that Crescendo enables — is not universally applicable. `dig` has no JSON mode. `systemctl list-units` is text-only (the per-unit `systemctl show` does produce JSON-adjacent key=value output, but list operations do not). `getent` and `lpstat` are text tools, period. For those, the existing parsing is the right tool.

## Storage.Linux — fixing the wrapper that was already there

This one was embarrassing in a productive way.

Part 4 built a Crescendo wrapper for `lsblk`. It worked — in the sense that it called `lsblk --json` and piped the output through `ConvertFrom-Json`. What I did not notice at the time was that the parameter map was completely unwired:

```powershell
$__PARAMETERMAP = @{}
param()
```

Empty. No parameters. The `--bytes` flag — critical for getting sizes as integers rather than human-readable strings like `465.8G` — was documented in the JSON config file but never made it into the generated code. And `Get-Disk`, `Get-Partition`, and `Get-Volume` had all quietly gone around the wrapper entirely, calling `lsblk` inline. Three cmdlets, three independent invocations, three places to get the size handling wrong. `Get-Partition` had indeed gotten it wrong — no `--bytes`, so sizes came back as strings and anything that compared or sorted by size was silently broken.

The fix was straightforward once the problem was visible:

1. Added `Functions/Private/Get-LsBlkData.ps1` — a clean wrapper with `--json`, `--bytes`, and a `--all` switch, with proper structured `ErrorRecord` handling when `lsblk` is not installed or returns non-zero.
2. Added `Functions/Private/Expand-LsBlkDevices.ps1` — extracted from an inline helper function that was buried inside `Get-Volume`'s function body, which is not where a reusable tree-flattening function belongs.
3. Updated all three cmdlets to call `Get-LsBlkData` instead of `lsblk` directly.

The `.psm1` loads `Functions/Private/` before `Functions/` so the helpers are available when the cmdlet files dot-source in. Obvious once you think about it. Less obvious when you are adding a `Private/` folder for the first time and the helpers silently fail to load because they were dot-sourced after the files that needed them.

## NetTCPIP.Linux — the N+1 problem

This one was more interesting.

`Get-NetRoute` was building its route table by calling `ip -json route show` (twice — IPv4 and IPv6), then for each route entry, calling `ip -json link show <dev>` individually to look up the `ifindex` of the interface. On a system with twenty routes, that is twenty-two `ip` calls per `Get-NetRoute` invocation. On a busy system or in a pipeline loop, this adds up.

The fix was to create a private `Crescendo/ip.psm1` with three helpers:

```powershell
function Get-IpAddr    { ip -json addr show | ConvertFrom-Json }
function Get-IpRoute   { param([switch]$IPv6) ... }
function Get-IpLink    { param([switch]$Statistics) ... }
```

`Get-NetRoute` now calls `Get-IpLink` once, builds a hashtable mapping interface names to `ifindex` values, and looks up each route's index from the map. One call instead of N+1. The route data is the same. The interface is cleaner. The performance is better.

The same `ip.psm1` gives `Get-NetIPAddress` and `Get-NetIPConfiguration` a shared `Get-IpAddr`, so they are both calling the same wrapper rather than duplicating the invocation independently.

```powershell
# before — Get-NetRoute, per route:
$link = ip -json link show $r.dev | ConvertFrom-Json
$ifindex = $link[0].ifindex

# after — Get-NetRoute, once:
$linkMap = @{}
Get-IpLink | ForEach-Object { $linkMap[$_.ifname] = $_.ifindex }
# ...then per route:
$ifindex = $linkMap[$r.dev]
```

Not complicated. Worth doing.

`ss` — which backs `Get-NetTCPConnection` — has no JSON mode. The text parsing stays.

## NetAdapter.Linux — the same pattern, simpler case

`Get-NetAdapter` and `Get-NetAdapterStatistics` were both calling `ip -json link show` independently, with `Get-NetAdapterStatistics` adding the `-s` flag for statistics data. Two functions, one tool, zero sharing.

A separate `Crescendo/ip.psm1` for NetAdapter.Linux (not the same file as NetTCPIP.Linux — each module is self-contained):

```powershell
function Get-IpLink { param([switch]$Statistics) ... }
```

`Get-NetAdapter` calls `Get-IpLink`. `Get-NetAdapterStatistics` calls `Get-IpLink -Statistics`. Both load the same private module. Neither duplicates the invocation.

## What Crescendo cannot fix

Five of the eight modules stayed as custom parsing, and that is the right call. But it is worth naming why.

`dig` is the uncomfortable one. `dig` output is structured — it has well-defined sections (`QUESTION`, `ANSWER`, `AUTHORITY`, `ADDITIONAL`), each with typed records. But the output is designed for humans, not machines. There is no `--json` flag. The `+format=json` experiment that appeared briefly in some dig versions was not standardised. So `Resolve-DnsName` remains a text parser, and it will continue to be one unless `dig` changes or an alternative tool takes its place.

`systemctl list-units` and `systemctl list-timers` are in the same category. The `--output=json` flag exists for `systemctl show <unit>` but not for list operations. The list commands produce aligned text columns — parseable, but fragile if the column widths change between systemd versions.

`getent passwd` is colon-delimited text. Seven fields, colon-separated. Not going to change. The parsing is four lines. It does not need a wrapper.

`lpstat` is perhaps the worst: different flags return different text formats, and joining them into one object per printer requires three separate calls with three different parsers. There is no JSON version. CUPS has a REST API, but it requires authentication and local access to the CUPS socket. The `lpstat` wrapper stays.

## What the audit actually produced

Three modules changed. Three commits pushed. Numbers:

- `Storage.Linux`: commit `47c3325`
- `NetTCPIP.Linux`: commit `d4eb81c`
- `NetAdapter.Linux`: commit `510519c`

PSScriptAnalyzer on all three: 0 errors, 0 warnings. Pester on Windows: 804 tests, 0 failures (804 skipped — Linux-only modules, correct). Pester in WSL2: 533+167+171 = 871 tests, 0 failures, 1 expected skip (no partitioned disks in WSL2 — the partition test guards for that).

The remaining nine modules — the five kept-as-is plus the four that were not candidates — were documented with a short "Implementation Approach" note in each README explaining the audit decision. If someone picks up one of these modules and wonders why there is no Crescendo wrapper, the explanation is there.

## The lesson I keep re-learning

Crescendo is a tool for one specific problem: wrapping a CLI tool that produces structured (ideally JSON) output and making it look like a proper PowerShell cmdlet. When the CLI tool supports that, it is the right abstraction. When it does not, Crescendo is the wrong tool and no amount of configuration will make it fit.

The harder lesson is adjacent to that: the first implementation is rarely the right one. The Crescendo wrapper from Part 4 worked in the sense that it ran without throwing. It did not work in the sense that it was quietly bypassed by every cmdlet that depended on it, because it was not wired up properly. That is a comfortable kind of broken — nothing fails loudly, so nothing gets fixed.

Going back through twelve modules looking for exactly that kind of quiet brokenness is the kind of work that does not feel exciting. It does not produce new cmdlets or new features. It produces code that works more correctly in cases that the tests did not catch.

That, too, is worth doing.

## Addendum — three more migrations (what I got wrong)

The audit above was wrong about three modules. I published it, then immediately discovered the errors when I actually ran the commands against WSL2. So: corrections, with the embarrassing details included.

**`systemctl list-units` and `systemctl list-timers` do support `--output=json`.**

The post says they do not. "The `--output=json` flag exists for `systemctl show <unit>` but not for list operations." That sentence is wrong. `systemctl list-units --output=json` produces a JSON array. `systemctl list-timers --output=json` produces a JSON array. `systemctl list-unit-files --output=json` produces a JSON array. I had based that conclusion on memory and a quick scan of the flags — not on actually running the commands. Running them produced:

```json
[
  {"unit":"apparmor.service","load":"loaded","active":"inactive","sub":"dead","description":"Load AppArmor profiles"},
  ...
]
```

That is exactly what you want. Clean, typed, no column-width fragility. `Get-Service` and `Get-ScheduledTask` have now been rewritten to use JSON.

`Get-ScheduledTask` also had an N+1 problem I had not noticed: it called `systemctl show <unit>` once per timer to get `ActiveState`, `Description`, and `FragmentPath`. Bulk `systemctl show unit1 unit2 unit3 ...` works — units are separated by blank lines in the output — so the rewrite makes one bulk call for all timers instead of N per-timer calls.

**`dig` is not installed in WSL2. `resolvectl` is.**

The post says `dig` is the right tool for `Resolve-DnsName` and that `resolvectl` only handles cache flushing and per-interface queries. The actual situation: `dig` requires installing `dnsutils` or `bind9-dnsutils`, which is not in the base Ubuntu WSL2 image. `resolvectl` ships with systemd-resolved and is always present on modern distros.

More importantly: `resolvectl query --json=short --type=<TYPE>` works for A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, and TXT records. Each result comes back as a separate JSON line:

```json
{"key":{"class":1,"type":1,"name":"dns.google"},"address":[8,8,8,8]}
{"key":{"class":1,"type":1,"name":"dns.google"},"address":[8,8,4,4]}
```

That is cleaner than parsing `dig` section headers. The `Resolve-DnsName` implementation has been rewritten to use `resolvectl`. The `dig`-based text parser is gone. PTR arpa conversion (reversing the IP to `.in-addr.arpa`) is now handled automatically — pass the plain IP, get the right answer.

**What the corrected audit actually produced:**

Six modules changed. Three commits pushed in session 1, three more in session 2:

- `DnsClient.Linux`: commit `4f8ac6e`
- `ScheduledTasks.Linux`: commit `45191b0`
- `PowerShell.Management.Linux`: commit `a755f09`

WSL2 Pester: 86+30+60 = 176 additional tests passing, 0 failures.

The lesson from the first session — the Crescendo wrapper from Part 4 was quietly broken because nobody tested it in the environment it was meant to run in — applies here too. The audit conclusions about `systemctl` and `dig` were wrong for exactly the same reason: I did not run the commands.

## Next

Stage 3. The remaining stubs — the 51 cmdlets that currently just emit `Write-Warning "not yet implemented"` — several of them are genuinely implementable. `Find-NetRoute` via `ip route get`. `Get-NetNeighbor` via `ip neigh`. `Get-PrintConfiguration` via `lpoptions`. `Set-TimeZone` via `timedatectl`. `New-Service` via unit file creation and `systemctl`.

None of those are radical departures from what has been built already. They are just more of the same work, applied to the next batch of cmdlets on the list. Which is fine. That is what the project is.

There are also two new modules on the list: `SmbShare.Linux` (SMB/NFS client cmdlets, the four remaining ❌ from Evgenij's gap analysis) and `PackageManagement.Linux` (wrapping `apt`/`dpkg` as a `PSWindowsUpdate` peer). Both of those will need new repos, new scaffolding, new decisions about what is in scope.

Onwards.
