---
date: 2026-05-18 18:00:00 -0000
title: ready for contributors — powershell linux commands part 23
toc: true
---

Four repos. All eight CI workflows green. Twenty-two rules audited and enforced. Yet someone cloning `ScheduledTasks.Linux.Native` or `NetTCPIP.Linux.Native` would find no `AGENTS.md`, no contribution guide, no issue templates, and no CODEOWNERS file. The project could build and pass tests on five distros, but it had no on-ramp for an outside contributor.

That is the gap this post closes.

## Filling the documentation gaps

LocalAccounts.Linux.Native and Services.Linux.Native had the full set of contributor-facing files from earlier work. ScheduledTasks and NetTCPIP did not. I copied the entire set across:

- `AGENTS.md` — project context, C# conventions, test infrastructure, GitHub auth patterns
- `CONTRIBUTING.md` — how to clone, build, run tests, and submit a PR
- `CODE_OF_CONDUCT.md` — standard Contributor Covenant
- `SECURITY.md` — vulnerability reporting path
- `.github/ISSUE_TEMPLATE/` — bug report and feature request templates
- `PULL_REQUEST_TEMPLATE.md` — context, changes, testing structure
- `CODEOWNERS` — ensures I review every PR
- `.github/workflows/pr-validation.yml` — runs `dotnet build` and Pester on every pull request

The copy was not mechanical. Each `AGENTS.md` needed its module-specific details: cmdlet count, stub count, D-Bus usage notes, and the correct repo URL. The PR template references the correct distro matrix for each repo. CODEOWNERS points to the right paths.

After this change, every repo has the same baseline. Clone any of the four, read `AGENTS.md`, and you know how to build, test, and contribute.

## NuGet packaging for all 18 modules

Packaging was the last distribution gap. The 14 PowerShell modules from Stages 1-3 and the 4 C# binary modules from Stage 6 all needed a consistent publish path.

PowerShell modules use `.nuspec` files. The version tracks the `.psd1` manifest. The package includes the module directory subtree and `PSScriptAnalyzerSettings.psd1`. Example for Storage.Linux:

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>Storage.Linux</id>
    <version>0.6.0</version>
    <authors>peppekerstens</authors>
    <description>Linux Storage module providing Windows-compatible disk, partition, and volume cmdlets.</description>
    <tags>PowerShell Linux pwsh Module Storage</tags>
    <projectUrl>https://github.com/peppekerstens/Storage.Linux</projectUrl>
    <license type="expression">GPL-3.0-only</license>
  </metadata>
  <files>
    <file src="Storage.Linux\**\*" target="Storage.Linux" />
    <file src="PSScriptAnalyzerSettings.psd1" target="Storage.Linux" />
  </files>
</package>
```

C# modules add NuGet properties directly to the `.csproj`. `dotnet pack` produces the `.nupkg`. No separate `.nuspec` needed.

Authentication uses `Microsoft.PowerShell.SecretManagement` and `SecretStore` for cross-platform PAT storage. Two scripts handle the workflow:

- `setup-auth.ps1` — detects missing NuGet scopes on the stored PAT, offers to refresh via `gh auth refresh`
- `Get-GitHubNuGetCredential.ps1` — retrieves the PAT from the vault as a `PSCredential`

Consumer setup is two steps. Register the repository once without credentials. Pass `-Credential` on each `Find-PSResource` or `Install-PSResource` call:

```powershell
Register-PSResourceRepository -Name peppekerstens `
  -Uri https://nuget.pkg.github.com/peppekerstens/index.json -Trusted

$cred = & ./opencode/Get-GitHubNuGetCredential.ps1
Install-PSResource -Name LocalAccounts.Linux.Native -Repository peppekerstens `
  -Credential $cred -Reinstall -AcceptLicense
```

A `publish.yml` workflow runs on tag push. It packs and pushes to GitHub Packages with `--skip-duplicate` for idempotency. All 18 repos have this workflow. All 18 packages are published and installable.

## Decentralizing documentation

The coordination repo (`opencode`) was carrying too much documentation. `status.md` was a multi-page table. `stage6/review.md` duplicated review findings that also lived in each repo's `docs/REVIEW.md`. If you wanted to know the status of NetTCPIP.Linux.Native, you had to open the coordination repo, find the right row, then follow a link anyway.

I rewrote both files as thin indexes. `status.md` now contains a module table with links to each repo's `docs/STATUS.md`, `docs/REVIEW.md`, and `docs/CHANGELOG.md`. `stage6/review.md` links to the same per-repo review files.

Each repo now owns its documentation. Clone it, read `docs/`, and you have the full picture: current status, code review findings, and change history. The coordination repo tells you where to look.

## Closing the last code issues

Two remaining review items got fixed in this batch.

Issue #21 was the namespace style inconsistency. LocalAccounts and Services used block-scoped `namespace Foo { }`. ScheduledTasks and NetTCPIP used file-scoped `namespace Foo;`. I converted LocalAccounts and Services — 33 files total. All four repos now use file-scoped namespaces.

Issue #41 was a `ShouldProcess` display formatting regression. The goal was to show `"sshd (OpenSSH Daemon)"` instead of raw unit names. The initial implementation looked up display names before `ShouldProcess` ran, which triggered a D-Bus call on every invocation even when the user declined. I deferred the lookup until after `ShouldProcess` passes. The D-Bus call only happens when the user confirms.

## What is left

The project is contributor-ready. The remaining work is upstream submission:

1. Replace `LinuxServiceInfo` with `LinuxServiceController` in the PowerShell fork's `ServiceUnix.cs`. The standalone repo already has the new type. The fork needs the matching update.
2. Update fork tests for the new type name and properties.
3. Sign the Microsoft CLA at https://cla.opensource.microsoft.com/.
4. File an RFC at `PowerShell/PowerShell-RFC`.
5. Submit the upstream PR to `PowerShell/PowerShell`.

The fork branch (`feature/service-unix-systemctl`) is rebased on upstream master (`1919ba8`) with six commits on top. All nine service cmdlets are ported. WhatIf safety tests pass. Integration tests cover New/Remove-Service.

## What I learned

Documentation is not a separate concern from code. A repo with green CI but no `AGENTS.md` is not ready for contributors. The same applies to inconsistent namespace style — it is a small thing, but it signals whether the project cares about its own conventions.

NuGet packaging turned out to be simpler than expected once the authentication path was clear. GitHub Packages requires auth for reads, which complicates the consumer experience. The `SecretStore` approach handles it, but it adds a setup step that does not exist for the PowerShell Gallery. That trade-off is acceptable for a project this size.

Decentralizing documentation reduced the coordination repo to what it should be: a plan, a status index, and shared skills. Each module repo stands on its own. That is how it should have been from the start.

The next post covers the upstream PR submission.
