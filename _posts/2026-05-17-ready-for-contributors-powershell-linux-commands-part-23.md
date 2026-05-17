---
date: 2026-05-17 12:00:00 -0000
title: ready for contributors — powershell linux commands part 23
toc: true
redirect_from:
  - /ready-for-contributors-linux-command-wrapping-part-23/
---

Part 22 ended with the 22-rule audit complete across all four native modules. The code was clean. The builds were green. The issues were tracked. But the repos still looked like personal projects — no contribution guides, no code of conduct, no branch protection, no labels, no issues anyone could find and pick up.

If this was going to be ported into PowerShell itself, it needed to look like it belonged there.

## What a contributor sees

Before this pass, a visitor to any of the four repos would find source code, tests, a README, and nothing else. No `CONTRIBUTING.md`. No issue templates. No code of conduct. No way to know how to submit a change or what conventions to follow.

That changes now. Every repo has the same set of files:

| File | Purpose |
|---|---|
| `CONTRIBUTING.md` | "Your First Contribution" guide, commit conventions, branch naming |
| `CODE_OF_CONDUCT.md` | Contributor Covenant v2.1 |
| `SECURITY.md` | Private vulnerability reporting via GitHub Security Advisories |
| `CHANGELOG.md` | Version history in Keep a Changelog format |
| `.github/ISSUE_TEMPLATE/` | Bug report, feature request, code review templates |
| `.github/PULL_REQUEST_TEMPLATE.md` | Build and test checklist for every PR |
| `.github/CODEOWNERS` | Auto-assign reviewers on every PR |
| `.github/workflows/pr-validation.yml` | Build + Pester tests on every PR |
| `docs/linux-rules.md` | 22 development rules, authoritative reference |
| `.opencode/` | Standalone dev config with build, review, and status commands |
| `STATUS.md` | Current state, open issues, next steps |
| `AGENTS.md` | Architecture, conventions, boundary rules for AI-assisted development |

The `CONTRIBUTING.md` is deliberately short. It does not ask contributors to read a 20-page guide. It tells them: fork, branch off `master`, run the build, run the tests, open a PR. The commit convention is Conventional Commits — `fix:`, `feat:`, `docs:`, `test:`, `refactor:`, `chore:`. The branch naming is free-form — no enforced prefix.

The `pr-validation.yml` workflow runs `dotnet build` and the Pester test suite on every pull request. It does not wait for a maintainer to kick it off. It runs automatically.

## Branch protection

The repos allow direct pushes to `master` by default. That is fine for a solo project. It is not fine for something that will eventually live in the PowerShell organization.

The protection rules applied to all four repos:

- Require pull request before merging
- Require one approving review
- Require status checks to pass (`Build` and `Pester Tests`)
- Dismiss stale approvals when new commits are pushed
- Require linear history (squash merge only)
- Block force pushes
- Block deletions

The squash-only rule matters. Each PR becomes one clean commit in `master`. The upstream port will have a clean linear history, not a graph of merge commits from a personal workflow.

## Labels

GitHub ships with nine default labels. They are not enough for a project that tracks code review findings by severity.

The label set applied to all four repos:

| Label | Color | Purpose |
|---|---|---|
| `bug` | `#d73a4a` | Something isn't working |
| `documentation` | `#0075ca` | Improvements or additions to documentation |
| `duplicate` | `#cfd3d7` | This issue or pull request already exists |
| `enhancement` | `#a2eeef` | New feature or request |
| `good first issue` | `#7057ff` | Good for newcomers |
| `help wanted` | `#008672` | Extra attention is needed |
| `invalid` | `#e4e669` | This doesn't seem right |
| `question` | `#d876e3` | Further information is needed |
| `wontfix` | `#ffffff` | This will not be worked on |
| `MUST` | `#FF0000` | Must fix before merge |
| `SHOULD` | `#FFA500` | Should fix, but can defer |

The `MUST` and `SHOULD` labels come from the code review process. Every finding in the audit was tagged with one of these. They survive the transition from audit spreadsheet to GitHub issue.

## The issues

The code review produced 33 new findings across the four repos. Each one is now a GitHub issue with a body, labels, and a link back to the review.

| Repo | MUST | SHOULD | Total |
|---|---|---|---|
| LocalAccounts.Linux.Native | 3 | 4 | 7 |
| ScheduledTasks.Linux.Native | 3 | 6 | 9 |
| NetTCPIP.Linux.Native | 3 | 6 | 9 |
| Services.Linux.Native | 2 | 6 | 8 |

The `MUST` items are things like missing elevation checks, bare `catch (Exception)` blocks, and platform branching without `OperatingSystem.IsWindows()` guards. The `SHOULD` items are missing XML docs, LINQ in hot paths, missing parameter aliases, and test infrastructure gaps.

None of these are blockers. The code works. The tests pass. But they are gaps between what the modules do today and what they would need to do to be accepted into PowerShell itself.

## Discussions

The Discussions tab was enabled on all four repos. It is not a substitute for issues. It is a place for questions, proposals, and conversations that do not fit the issue template. The `CODE_OF_CONDUCT.md` applies there too.

## What changed

The code did not change. The structure did.

Before this pass, the repos were personal projects with good code and no process. After this pass, they are projects that look like they could accept contributions from strangers. The branch protection prevents accidental damage. The issue templates tell people how to report problems. The contribution guide tells them how to submit fixes. The CI workflow validates every PR before a human looks at it.

This is the minimum viable surface for an open source project. It is not everything PowerShell requires. But it is enough to start.

## What comes next

The issues are open. The next step is to fix them. The `MUST` items first, then the `SHOULD` items. After that, the fork branch needs updating to match the standalone repos, the Microsoft CLA needs signing, and the upstream PR needs filing.

The repos are ready for contributors. Now they need to be ready for Microsoft.
