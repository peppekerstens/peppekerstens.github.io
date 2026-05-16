---
date: 2026-05-05
title: The scaffold — PowerShell Linux Commands Part 11
toc: true
redirect_from:
  - /the-scaffold-linux-command-wrapping-part-11/
---

Today was productive by almost any measure you care to apply. Twelve modules. Hundreds of cmdlets. A full PSScriptAnalyzer pass. Zero test failures across 1513 tests. Clean repos, pushed, documented.

It also feels, sitting here at the end of it, a little hollow.

Let me try to explain that.

---

## The good: we covered a lot of ground

In a single day — with AI doing the heavy lifting — we went from a backlog of quality concerns to a codebase that is, by the numbers, in good shape:

- 12 modules covering 118 cmdlets from Evgenij's list (53% implemented, 43% stubbed)
- PSScriptAnalyzer: 6 errors and 399 warnings reduced to zero
- Real code bugs fixed: automatic variable collisions (`$home`, `$args`), empty catch blocks, pipeline functions missing `process {}` blocks, unused variables, a credential parameter typed as `[object]`
- Intentional patterns properly suppressed via `PSScriptAnalyzerSettings.psd1` at each repo root rather than sprinkled `[SuppressMessageAttribute]` noise
- A meaningful discovery about PowerShell parsing: if any code appears before `process {}` in a function body, PowerShell interprets `process` as the `Get-Process` alias. The named block must come first.

That last one is the kind of thing you only find by actually running the tools. So the tooling loop is working.

The coverage is real. The structure is sound. The patterns are documented. If someone were to pick up these modules cold, they would find consistent layout, consistent conventions, and a test suite to tell them if they broke something.

That is worth something.

---

## The bad: what do the tests actually test?

Here is where it gets uncomfortable.

1513 tests pass. That is a good number. But if you look at what the majority of those tests are actually asserting, the picture gets murkier.

A large fraction of the test suite — particularly on Windows, where 1309 of 1513 tests are skipped — is testing things like:

- Does the module load without errors?
- Does the function exist in the module's exported surface?
- Does calling the stub emit a warning?
- Does the example script exist as a file?

These are useful as regression guards. They are not useful for telling you whether the cmdlet works.

The Linux tests (run in WSL2) go further. `Get-Disk` actually calls `lsblk`. `Get-NetIPAddress` actually calls `ip addr`. `Get-LocalUser` actually parses `getent passwd`. Those tests return real data and assert real properties.

But they assert things like: "the result is not null", "the Name property is not empty", "the result has more than zero entries". They do not assert: "given this specific system state, the output is exactly this". They cannot, because the system state varies.

The practical effect is that the tests can tell you when the code is completely broken. They cannot tell you when the code is subtly wrong — returns the wrong field, maps the wrong unit, misparses an edge case in `chage -l` output, or silently drops entries for users with unusual GECOS fields.

That is a gap.

---

## The ugly: this is a curated, theoretical world

Here is the harder admission.

The entire development loop today was: AI writes code, AI writes tests, AI runs tests, tests pass, AI documents results, repeat. I directed the process — chose what to build, reviewed the logic, caught a few things — but I was not running these cmdlets against real workloads. I was not plugging them into scripts I actually use. I was not running them in a production-adjacent environment where the inputs are messy and the edge cases are real.

`Get-ScheduledTaskInfo` reads from `systemctl show *.timer`. What happens on a system where some timers have been manually masked? What happens when `LastTriggerUSec` is present but the system clock was reset? What happens on a container that has no systemd at all? The code handles the obvious cases. Whether it handles the real ones — I do not know.

`Get-LocalUser` parses `getent passwd`. What happens when the system uses LDAP or AD-joined accounts? What about users with colons in their GECOS field? What about systems where `chage` requires root and the caller does not have it? The empty catch blocks we replaced with `Write-Debug` are a hint: there were silent failure modes that nobody had tested.

`Resolve-DnsName` calls `dig`. One of the bugs fixed today was that the function was calling `dig` twice — once to a variable that was immediately overwritten. That means every call was twice as slow as it needed to be, and nobody noticed because the tests only checked that the output was not null.

The test suite is a scaffold. It proves the structure is there. It does not prove the building stands up.

This is not a criticism of AI-assisted development specifically. The same problem exists when a human writes a module in isolation, writes their own tests, and ships without external validation. The difference is that with AI the iteration speed is so high that you can build a lot of scaffold very quickly — which feels like progress, and mostly is, but also means the gap between "tests pass" and "actually works" can grow faster than it would if you were building more slowly.

---

## What this means for next steps

The modules exist. The structure is correct. The conventions are documented. PSScriptAnalyzer is clean.

What they are not is production-validated. To get there, someone needs to:

1. **Actually use the cmdlets.** Not in a test. In a script that does a real thing. `Get-Disk | Where-Object MediaType -eq 'SSD' | Select-Object FriendlyName, Size` on a real machine with real disks. `Get-LocalUser | Where-Object Enabled | Format-Table` on a real server. See what comes out. See what is wrong.

2. **Test on diverse systems.** Ubuntu 24.04 in WSL2 is not Ubuntu 20.04 on a VM, which is not Alpine in a container, which is not RHEL 9 on a cloud instance. The `lsblk` JSON format differs by version. `systemctl` behaves differently without systemd. `ip addr` output changes between iproute2 versions.

3. **Push on the edge cases.** What happens when `dig` is not installed and the error is not caught? What happens when `getent passwd` returns a line with fewer than 7 fields? What happens when a timer unit exists in the user scope but `id -u` says the caller is root?

4. **Write tests that would actually catch regressions.** Tests that mock `lsblk` output with known tricky inputs and assert specific parsed field values. Tests that exercise the filter logic with exact inputs. Tests that verify the `process {}` pipeline actually processes multiple piped values, not just one.

None of this requires throwing away what was built today. The scaffold is a good place to start from. It would be a poor place to stop.

---

## An honest summary

The good: in one day, with AI assistance, we covered more structural ground than I would have covered in weeks working alone. The pattern library, the conventions, the PSSA integration, the test runner infrastructure — that is genuinely useful.

The bad: the tests are thin. They confirm presence, not correctness. The real validation work has not been done.

The ugly: I am the only human in this loop. The AI builds what I ask it to build, tests what it thinks should be tested, and reports success when the tests it wrote pass the code it wrote. That is a closed system. It is productive in the early stages. It is dangerous if you mistake it for quality assurance.

What comes next is the part that cannot be automated: real usage, real environments, real failure modes, real users. The scaffold is up. Now someone has to move in.

---

All twelve module repositories are at [github.com/peppekerstens](https://github.com/peppekerstens). Pull requests, bug reports, and reports of edge cases that break things are more welcome than stars.






