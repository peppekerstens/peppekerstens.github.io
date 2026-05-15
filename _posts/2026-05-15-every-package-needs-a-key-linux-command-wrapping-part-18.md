---
date: 2026-05-15  -0000
title: Every Package Needs a Key — Linux Command Wrapping Part 18
toc: true
---

Stage 7 shipped. Eighteen modules are now published as NuGet packages to
GitHub Packages. The CI flow — tag, push, GHA packs and pushes — works
without friction. `GITHUB_TOKEN` has `packages:write`, the job runs,
the `.nupkg` lands in the registry.

Then I tried to install one.

`Find-PSResource -Name Storage.Linux -Repository peppekerstens`

403 Forbidden.

This is the story of why that 403 exists and what it took to fix it
properly.

## The distribution problem

For the first six stages, "distributing a module" meant cloning the
repo. Import the module from the local clone, run the tests, iterate.
The consumer was always the developer.

Stage 7 changed that. The consumer is now a package manager pipeline:

```
.nuspec / .csproj  ->  nuget pack / dotnet pack  ->  .nupkg
                                                      -> GitHub Packages
                                                      -> PSResourceGet
```

A consumer should be able to run this in a clean WSL prompt:

```powershell
Install-PSResource -Name Storage.Linux -Repository peppekerstens
Import-Module Storage.Linux
Get-Command -Module Storage.Linux
```

Not clone a repo. Not set up a build environment. Just install and go.

This meant the NuGet feed had to be reachable from a developer machine,
not just from a GHA runner. And that is where the auth boundary appeared.

## GitHub Packages requires auth for everything

GitHub Packages is designed for private packages. The public-package
support exists, but the NuGet protocol endpoint — the V3 service index
at `nuget.pkg.github.com/<owner>/index.json` — requires HTTP basic
authentication for every request, even when the package is public.

This is a design choice, not a bug. It means every tool in the NuGet
ecosystem that touches the feed needs credentials. The dotnet CLI.
NuGet.exe. PSResourceGet. Each has its own auth mechanism, and none of
them share a config file.

The existing authentication pattern was simple:

```powershell
$env:GH_TOKEN = (
    "protocol=https`nhost=github.com`n" |
    & git credential fill
) -split "`n" | Select-String "password=" |
  ForEach-Object { $_ -replace "password=", "" }
```

This extracts the PAT that `git-credential-manager` stores for
`github.com`. It works for `gh`, for `git`, for any tool that
reads `GH_TOKEN`. It gives us a PAT with `repo`, `workflow`, and
`gist` scopes.

It does not give us `read:packages` or `write:packages`. And when
you hit the NuGet feed with a PAT missing those scopes, GitHub
returns 403.

## The scope gap

The PAT from `git credential fill` is created during `gh auth login`
with the defaults: `repo`, `workflow`, `gist`. These cover git
operations and workflow management. They do not cover NuGet.

Adding the missing scopes is one command:

```powershell
gh auth refresh -h github.com -s read:packages,write:packages
```

But a refresh is interactive — it opens a browser. And on WSL
(Linux), the `gh` CLI has its own credential store, separate from
the Windows Credential Manager. You have to refresh twice if you
develop on both Windows and WSL.

Worse, the NuGet ecosystem does not read `GH_TOKEN` automatically.
The dotnet CLI does not pick it up. NuGet.exe does not pick it up.
PSResourceGet needs a `PSCredential` object. Every tool requires
you to explicitly hand it the token.

So the real question became: how do you store the PAT once, and
retrieve it in the right format for each tool?

## What we tried

**Register-PSResourceRepository with -Credential.** The cmdlet
accepts `PSCredentialInfo`, not `PSCredential` — a PSResourceGet-
specific wrapper type. Creating a `PSCredentialInfo` from a
`PSCredential` is possible but fragile. The constructor signature
varies by PSResourceGet version. No clear documentation. Abandoned.

**NuGet.config with plaintext password.** `dotnet nuget add source`
can embed the PAT in `NuGet.config` with `--store-password-in-clear-text`.
On Windows the credential is DPAPI-encrypted. On Linux it is literally
base64. Storing a PAT that grants access to 18 repos in a config file
that might be committed is not acceptable.

**Temp files.** Write the PAT to `/tmp/gh_pat.txt`, read it back.
Works, but a temp file is one shell history leak away from exposed.
And it does not survive a reboot.

**Windows Credential Manager only.** Works on Windows. Does not exist
on Linux. Half a solution.

None of these were cross-platform, secure, and automation-friendly at
the same time.

## The choice: SecretManagement + SecretStore

`Microsoft.PowerShell.SecretManagement` is Microsoft's abstraction
layer for credential storage. It sits above vault backends:
Windows Credential Manager on Windows, the `SecretStore` module
(file-based, AES-256-CBC encrypted) on Linux. The API is the same
on both platforms.

The `SecretStore` vault can be configured with `-Authentication None`,
meaning it does not prompt for a master password. The encryption key
is derived from the machine's local storage — DPAPI on Windows, a
generated key file on Linux. This trades some security (no master
password) for unattended automation (scripts can retrieve secrets
without prompts). For a development-machine PAT with limited NuGet
scope, the tradeoff is acceptable.

The result is three files in the coordination repo:

**setup-auth.ps1** — one-time interactive setup. Installs
SecretManagement + SecretStore if missing. Detects missing
`read:packages` / `write:packages` scopes on the current PAT and
offers to refresh them. Prompts for the PAT and stores it in the
vault as the secret `GitHubNuGetToken`. Run once per machine.

**Get-GitHubNuGetCredential.ps1** — per-session retrieval. Returns
a `PSCredential` for PSResourceGet operations. With `-AsEnvVar`,
sets `$env:GH_TOKEN` for dotnet CLI operations.

**authentication.md** — documentation covering setup, usage,
troubleshooting, and cross-platform edge cases.

Usage looks like this:

```powershell
# One-time:
.\setup-auth.ps1

# Each session — PSResourceGet:
$cred = .\Get-GitHubNuGetCredential.ps1
Register-PSResourceRepository -Name peppekerstens `
    -Uri https://nuget.pkg.github.com/peppekerstens/index.json -Trusted
Find-PSResource -Repository peppekerstens -Credential $cred
Install-PSResource -Name Storage.Linux -Credential $cred

# Each session — dotnet CLI:
. .\Get-GitHubNuGetCredential.ps1 -AsEnvVar
dotnet nuget push out/*.nupkg --api-key $env:GH_TOKEN --skip-duplicate
```

## The pros

**Cross-platform.** The same `setup-auth.ps1` runs in Windows pwsh
and WSL pwsh. The `SecretStore` vault format is the same. The
`Get-GitHubNuGetCredential.ps1` output is the same.

**No plaintext PATs in files.** The token lives in the vault,
encrypted at rest. The only time it exists in process memory is
during the few seconds of a `Find-PSResource` call.

**PowerShell-native.** No third-party credential providers. No
config file changes. Just two scripts and the modules already in
the PSGallery.

**Scope guard.** The setup script checks the current PAT scopes
against what NuGet needs. If `read:packages` or `write:packages`
is missing, it prompts the user to run `gh auth refresh`. The user
does not have to remember which scopes are needed.

**Documented.** The reasoning, the failure modes, the workarounds
for `Register-PSResourceRepository` — all in `authentication.md`.
A human can understand the setup without reading the scripts.

## The cons

**Two vaults, not one.** Windows and WSL have separate credential
stores. Running `setup-auth.ps1` in WSL does not pick up the PAT
you stored on Windows. You have to run it twice. There is no
cross-platform secret sharing without a network vault solution.

**No master password reduces security.** `-Authentication None`
means any process running as the same user can retrieve the
secret. The vault file on Linux is AES-256 encrypted, but the
key file is in `~/.password-store/` — readable by the same user.
This is acceptable for a development machine with a scoped PAT.
It would not be acceptable for production or shared machines.

**One-time setup per machine.** You cannot clone the repo and
immediately run `Find-PSResource`. You have to run
`setup-auth.ps1` first. This is friction for new contributors.

**Register-PSResourceRepository still needs PSCredentialInfo.**
The `-Credential` parameter on `Register-PSResourceRepository`
accepts `PSCredentialInfo`, not `PSCredential`. The workaround
is to register the repo without a credential and pass
`-Credential` (which does accept `PSCredential`) on every
`Find-PSResource` / `Install-PSResource` call. This works but
is not obvious from the cmdlet help.

**gh auth refresh is still interactive.** Adding `read:packages`
scopes to the PAT requires a browser redirect. You cannot script
it. The setup script detects the gap and tells you, but it cannot
close it.

## The tradeoff in context

The NuGet packaging stage is the first time in this project where
an external system (GitHub Packages) enforces authentication on the
consumer side. For six stages, authentication was a developer concern
— `git push`, `gh pr create`, triggering workflows. Now it is a
distribution concern.

The SecretManagement approach is not the simplest possible solution.
The simplest solution is `dotnet nuget add source` with an embedded
token in a local config file. But that fails the security gate.
The simplest secure solution is the Windows Credential Manager,
but that fails the cross-platform gate. The simplest secure
cross-platform solution is what we built.

It has rough edges. Two vaults instead of one. A per-machine setup
step. A cmdlet that does not accept the credential type you already
have. But it works on Windows and Linux, it keeps the PAT encrypted,
and the three files in the repo document every decision.

## What is next

Commit and push. Tag all 18 repos. Wait for 18 GHA runs to turn
green. Then the distribution pipeline is complete — from tag to
`Install-PSResource` in under five minutes, on any machine that
has a vault and a key.




