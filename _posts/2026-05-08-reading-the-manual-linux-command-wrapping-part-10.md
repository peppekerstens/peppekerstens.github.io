---
date: 2026-05-08  -0000
title: Reading the manual, properly — Linux Command Wrapping Part 10
toc: true
---

PKI.Linux v0.1.0 worked. The tests passed. The examples ran. I shipped it.

Then I did something I probably should have done before shipping: I read the manual. Not the API docs for the specific .NET types I was using — I had read those. I mean the PowerShell SDK development guidelines, the .NET dispose pattern docs, the community style guide. The things that tell you not just *how* the APIs work but *how you are supposed to use them*.

What came back was twelve findings, two of them serious enough that I am calling them critical. This post is about what those were, where I went to find them, why each source matters, and what changed in v0.2.0.

## Why do this at all

The module worked. It passed its tests. So why spend time on a code review?

A few reasons. PKI operations touch private key material. If something is leaking memory or leaving key handles open, that matters more here than it would in, say, a module that parses `lsblk` output. Also, one of the things I have been thinking about since Part 9 — the distro portability problem — is that the .NET approach is supposed to be cleaner and more principled than CLI wrapping. If the implementation is sloppy under the hood, that story falls apart.

And honestly: I was curious. I had written seven modules before this one all using the CLI-wrapping pattern. PKI.Linux was the first to use .NET types directly in any serious way. I wanted to know whether I had gotten the patterns right.

The answer was: some of them, yes. Some of them, no.

## What I reviewed and why each source matters

Before getting to the findings, a word on the sources. I looked at four bodies of reference material and they each contributed something different.

### PowerShell SDK Required Development Guidelines

**URL:** https://learn.microsoft.com/powershell/scripting/developer/cmdlet/required-development-guidelines

These are the guidelines Microsoft considers non-negotiable for production cmdlets — the things that go under "Required" rather than "Advisory." Two of them hit PKI.Linux directly.

**RC04 — Declare OutputType.** Every cmdlet must declare what type it outputs. This is not just documentation — it feeds pipeline type inference and IDE tab completion. All seven functions in PKI.Linux already had `[OutputType(...)]` declared, which was good. What the guideline made me check was accuracy: does `Get-PfxData` really return `[PSCustomObject]`? (Yes, and that is acceptable — the Windows version returns a specialised type that does not exist cross-platform.) Does `Test-Certificate` return `[bool]`? (Yes, and the guideline AD05 specifically confirms that Test-verb cmdlets should return Boolean.) So RC04 was a confirmation rather than a finding.

**RC06 — Use ErrorRecord for all errors.** This was the biggest finding in the entire review, and the most pervasive. The guideline says terminating errors must use `$PSCmdlet.ThrowTerminatingError(ErrorRecord)` and non-terminating errors must use `$PSCmdlet.WriteError(ErrorRecord)`. It is very specific about what an `ErrorRecord` requires: a typed exception object, a string error ID, an `ErrorCategory` enum value, and a target object. Without all four of these, the error is not inspectable. Callers using `-ErrorVariable`, `try/catch` with specific types, or `$Error[0].FullyQualifiedErrorId` get nothing useful back.

Every single error path in PKI.Linux v0.1.0 used `Write-Error "some string"`. All of them. Eight error sites, all producing `ErrorId = ""`, `Category = NotSpecified`, `Exception = WriteErrorException`. The module looked fine interactively — the messages were readable — but was completely opaque to any caller trying to handle errors programmatically.

### PowerShell SDK Advisory Development Guidelines

**URL:** https://learn.microsoft.com/powershell/scripting/developer/cmdlet/advisory-development-guidelines

The "should follow" tier. Two advisory items were relevant.

**AC06 — Support Credential Parameters.** This validated a decision I had already made. PKI.Linux uses `[System.Security.SecureString]` for the `-Password` parameter on `Export-PfxCertificate`, `Get-PfxData`, and `Import-PfxCertificate`. The .NET team has separately said SecureString is not recommended for new cross-platform development. These two positions seem to conflict. The advisory guideline resolves it: use `SecureString` for password parameters that mirror Windows cmdlet signatures, because script portability depends on matching the parameter type. The decision to keep `SecureString` was correct — but the guideline also prompted me to document *why*, which I had not done.

**AD05 — Boolean return from Test cmdlets.** `Test-Certificate` already returned `[bool]` and already had `[OutputType([bool])]`. The guideline confirmed both were right, and clarified one more thing: Test cmdlets should not write to the success output stream when the result is false. They should return `$false`, not write an error object. `Test-Certificate` was already doing this correctly with `Write-Verbose` for failure details. Confirmed.

### .NET IDisposable / Dispose Pattern documentation

**URL:** https://learn.microsoft.com/dotnet/standard/garbage-collection/implementing-dispose

This is where the critical findings lived.

The core principle: objects that hold unmanaged resources must implement `IDisposable` and must be disposed explicitly. The GC finalizer will eventually clean them up but the timing is non-deterministic. In a short-lived script that creates one certificate and exits, this is irrelevant. In a long-running PowerShell session — or a function called in a pipeline loop over many objects — leaked handles accumulate.

Three .NET types used heavily in PKI.Linux implement `IDisposable` and hold unmanaged handles on Linux:

**RSA and ECDsa** hold OpenSSL key handles. `New-SelfSignedCertificate` created the key at line 78-103 of the v0.1.0 code — before the `ShouldProcess` check at line 131. This meant that on `-WhatIf`, the key was generated and allocated but `CreateSelfSigned` was never called, so the key handle was never incorporated into a certificate object and the handle was simply abandoned. On a normal run, the key was created, used, and then also abandoned — it was not disposed after use. The fix required understanding one non-obvious fact from the `CertificateRequest` API docs: `CreateSelfSigned()` *copies* the key into the resulting `X509Certificate2`. After that call returns, the original key object can be safely disposed. Without that confirmation, disposing the key after creating the cert would seem dangerous.

**X509Store** holds a certificate store handle. The v0.1.0 pattern was `$store.Open(...)`, `$store.Add($cert)`, `$store.Close()`. This appeared in three functions: `New-SelfSignedCertificate`, `Import-Certificate`, and `Import-PfxCertificate`. The problem: if `$store.Add()` throws — which it can, for example if the cert is already present — `$store.Close()` is never reached. The store handle leaks. The fix is `try { $store.Add($cert) } finally { $store.Dispose() }`. `Dispose()` calls `Close()` internally on .NET Core, so you do not need both.

**X509Chain** holds an OpenSSL verification context. This was the worst finding. `Test-Certificate` creates a new `X509Chain` inside its `process {}` block — one per pipeline input certificate — and never disposes any of them. In a pipeline like `Get-ChildItem Cert:\CurrentUser\My | Test-Certificate`, every certificate in the store gets its own `X509Chain` object, all accumulating in memory. The fix is a `try/finally { $chain.Dispose() }` wrapping the chain's lifetime.

### .NET SecureString documentation

**URL:** https://learn.microsoft.com/dotnet/api/system.security.securestring

This page has a prominent note that was added with .NET 5:

> *"We don't recommend using SecureString for new development. The contents of the array are unencrypted on non-Windows platforms."*

This is important context for a Linux-only module. `SecureString` on Linux is not encrypted. The memory protection that the name implies only exists on Windows. Practically, what PKI.Linux gets from using it is: API parity with the Windows module, and minimisation of the time window during which the plaintext password exists in managed memory (via the BSTR interop pattern).

The BSTR interop pattern — `SecureStringToBSTR` → `PtrToStringBSTR` → use → `ZeroFreeBSTR` in `finally` — was already correct in v0.1.0. What the docs prompted was adding comments explaining *why* the pattern is what it is, and adding a clear note in the Implementation Notes section of the README that the OS-level protection does not apply on Linux.

The same page also pointed at `X509CertificateLoader` (introduced in .NET 9) as the modern replacement for the `X509Certificate2` file-loading constructors, which are marked obsolete in .NET 9. That is a forward-compatibility note for a future v0.3.0.

### PowerShell Practice and Style Guide

**URL:** https://poshcode.gitbook.io/powershell-practice-and-style/

The community style guide, not from Microsoft but widely adopted. This is where the `process {}` bug surfaced.

The guide documents something that is easy to miss if you have not run into it: `[Parameter(ValueFromPipeline)]` only works correctly when the function body is inside a `process {}` block. Without one, the body executes in the implicit `end {}` block — which runs once, after all pipeline input has been collected, using only the last value bound from the pipeline. There is no error, no warning. The first three certs pipe through and are silently discarded. Only the fourth is processed.

`Export-Certificate`, `Export-PfxCertificate`, and `Import-PfxCertificate` all had `[Parameter(Mandatory, ValueFromPipeline)]` declared on `$Cert` but no `process {}` block. `Test-Certificate` was the only function that had it right. All three missing cases were fixed in v0.2.0.

### PowerShell source code — C# cmdlet implementations

**URL:** https://github.com/PowerShell/PowerShell/tree/master/src/Microsoft.PowerShell.Commands.Management

Reading actual C# cmdlet implementations from the PowerShell team confirmed the error handling model. In compiled cmdlets, the pattern is:

```csharp
// Non-terminating — pipeline continues for the next record
WriteError(new ErrorRecord(
    new IOException("File already exists"),
    "FileAlreadyExists",
    ErrorCategory.ResourceExists,
    filePath));

// Terminating — cmdlet stops here
ThrowTerminatingError(new ErrorRecord(
    new InvalidOperationException("Certificate has no private key"),
    "CertificateHasNoPrivateKey",
    ErrorCategory.InvalidArgument,
    cert));
```

PowerShell advanced functions expose the same API via `$PSCmdlet.WriteError(...)` and `$PSCmdlet.ThrowTerminatingError(...)`. The error ID string — `"FileAlreadyExists"`, `"CertificateHasNoPrivateKey"` — is what appears in `$Error[0].FullyQualifiedErrorId` (prefixed with the cmdlet name) and what callers use to catch specific conditions. Without it, you have a module that produces errors but cannot be reliably scripted against.

The source reading also confirmed the terminating vs non-terminating distinction: file-already-exists is non-terminating (the next cert in a pipeline should still be processed); no-private-key is terminating (the current operation fundamentally cannot proceed).

## What changed in v0.2.0

Twelve issues, all addressed:

| Issue | Severity | Fix |
|---|---|---|
| `X509Chain` not disposed per pipeline record in `Test-Certificate` | Critical | `try/finally { $chain.Dispose() }` |
| RSA/ECDsa key created before `ShouldProcess`, never disposed | Critical | Moved inside `ShouldProcess`; `try/finally { $key.Dispose() }` |
| No `process {}` block on three pipeline-accepting functions | High | Added `process {}` to `Export-Certificate`, `Export-PfxCertificate`, `Import-PfxCertificate` |
| `X509Store` not in `try/finally` in three functions | High | `try/finally { $store.Dispose() }` in all three |
| Bare `Write-Error "string"` at every error site | High | Structured `ErrorRecord` with typed exception, error ID, `ErrorCategory`, and target object |
| `$cert` created before `ShouldProcess` in `Import-PfxCertificate` | High | Now disposed in the else branch when `ShouldProcess` returns false |
| `-TextExtension` silently ignored | Medium | `Write-Warning` emitted when used |
| `-KeyLength` with `-KeyAlgorithm ECDSA` silently ignored | Medium | `Write-Warning` emitted when used |
| `$KeyLength` accepts insecure values | Medium | `[ValidateRange(2048, 8192)]` |
| No exception wrapping around crypto operations | Medium | `CryptographicException` caught and re-thrown as structured `ErrorRecord` with user-facing context |
| Manual `Test-Path` checks for input files | Low | `[ValidateScript({ Test-Path $_ -PathType Leaf })]` on `$FilePath` parameters |
| `$CertStoreLocation` unvalidated string | Low | `[ValidateSet('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')]` |

## What this says about the broader project

The CLI-wrapping modules — all seven before PKI.Linux — have some of the same issues. The `process {}` block problem almost certainly exists in some of them. The bare `Write-Error` pattern is definitely in all of them. The IDisposable problem is less relevant there because the CLI tools leave no .NET objects to dispose.

I am not going back to fix all of them now. But this review has produced a cleaner template for how PKI.Linux v0.2.0 handles errors and resource lifetimes, and that template will carry forward into the next module.

The other thing it produced is a clearer sense of which references to consult and what each one is for. The required guidelines tell you what the contract is. The advisory guidelines tell you the preferred way to meet it. The .NET dispose docs tell you which types are dangerous to leave undisposed. The style guide catches the footguns that do not show up in formal specs. The source code confirms what the docs describe actually looks like in practice.

Reading all of them takes a few hours. Not reading them apparently takes a bit longer — distributed across every script that calls your module and hits an error it cannot parse.




