---
name: writing-style
description: Personal writing conventions for peppekerstens — load when producing commit messages, PR descriptions, help text, or blog content
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: writing
---

## When to use me

Load this skill before writing any of the following:

- Git commit messages
- PR titles and descriptions
- PowerShell help text (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`)
- C# XML doc comments (`///`)
- README sections
- Blog posts for `peppekerstens.github.io`

---

## Voice

Direct and technical. No filler.

Never write:
- "certainly!", "great question", "I hope this helps", "I'm happy to"
- "this PR introduces exciting new..."
- "In this post I will explain how to..."

Always write:
- One idea per sentence. If a sentence needs a semicolon to hold two ideas, split it.
- Active voice: "Returns the user object" — not "The user object is returned".
- No em-dashes as a stylistic device. Use a plain hyphen or split the sentence.

---

## Commit messages

Format: Conventional Commits, lowercase type.

```
fix: convert to file-scoped namespaces (review #21)
feat: add Get-NetNeighbor using ip neigh
chore: pin SMA to 7.4.6 across all four repos
docs: add 5-distro CI badge to README
test: add WhatIf safety tests for Set-LocalUser
refactor: extract RunIpVoid helper to remove duplication
```

Rules:
- Subject line: imperative mood, ≤72 characters, no trailing period.
- Body: explain *why*, not what. The diff shows what.
- Reference issue or review item when relevant: `(review #21)`, `(closes #14)`.

---

## PowerShell help text

`.SYNOPSIS` — one sentence, imperative mood, no trailing period:
```
Gets the IP address configuration for one or more network interfaces
```

`.DESCRIPTION` — two to four sentences. What it does, then any non-obvious behaviour:
```
Retrieves IPv4 and IPv6 address information from the ip command output.
On Windows, delegates to the built-in Get-NetIPAddress cmdlet.
Accepts pipeline input from Get-NetAdapter.
```

`.PARAMETER` — one sentence. Mention default only if surprising:
```
The name of the network interface. Wildcards are supported.
```

`.EXAMPLE` — realistic invocation first, then a one-line comment:
```powershell
Get-NetIPAddress -InterfaceAlias eth0
# Returns all IP addresses assigned to eth0
```

No "This example shows how to..." preamble. Mirror the density of `Get-Help Get-Item`.

---

## C# XML doc comments

`<summary>` on public API only. One sentence:
```csharp
/// <summary>Gets all local user accounts from the passwd database.</summary>
```

Add `<param>` and `<returns>` only when the name alone is not self-explanatory.
No `<remarks>` blocks for things obvious from the code.

---

## PR descriptions

Structure every PR description in this order — no deviations:

```
## Context
<one paragraph: what problem does this solve or what stage does it advance>

## Changes
- <one line per change>
- <one line per change>

## Testing
<what was run: GHA matrix result, local Pester run, distro list>
```

---

## README updates

- Lead with what the module does, not what it is.
- Cmdlet table: mark stub vs implemented accurately — it matters to users.
- CI badge immediately after the title.
- Usage examples use realistic values from the actual project.

---

## Blog posts (`peppekerstens.github.io`)

- First person. Present tense for discoveries, past tense for completed work.
- Start with the problem or question — not "In this post I will...".
- Code blocks use real project examples, not toy snippets.
- End with what was learned or what comes next — not a summary of what was just written.
- Titles: lowercase except proper nouns and acronyms.
  Good: "Five distros, one test run"
  Bad: "How I Tested Across Five Linux Distributions"
- **Dates**: Always use ISO 8601 timestamps in the front matter (`YYYY-MM-DD HH:MM:SS -0000`) to ensure correct chronological display. If multiple posts are published as part of a logical series (e.g., "Part X"), synthesize unique dates or times (e.g., different days) to guarantee the desired display order.
