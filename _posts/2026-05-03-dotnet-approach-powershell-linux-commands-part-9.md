---
date: 2026-05-03
title: The distro problem, .NET to the rescue — PowerShell Linux Commands Part 9
toc: true
redirect_from:
  - /dotnet-approach-linux-command-wrapping-part-9/
---

PKI.Linux is done. Seven cmdlets, pure .NET, no openssl CLI, pushed to GitHub. Go look at it if you want: [peppekerstens/PKI.Linux](https://github.com/peppekerstens/PKI.Linux).

But writing that module surfaced something I have been quietly aware of for a while and have been deferring. So before we charge ahead to PrintManagement.Linux and the rest of the list, I want to sit with the uncomfortable part for a bit.

## The thing that keeps nagging at me

Every module in this series so far — except PKI.Linux — is built the same way: find the Linux CLI tool that does roughly the same thing, parse its output, wrap it in a PowerShell function that returns an object shaped like the Windows equivalent. `lsblk` for `Get-Disk`. `ss` for `Get-NetTCPConnection`. `systemctl` for `Get-Service`. `getent` for `Get-LocalUser`.

It works. The tests pass. On my WSL2 Ubuntu instance.

And that is exactly the problem.

Ubuntu is not Linux. Ubuntu is one Linux. The moment someone tries `Storage.Linux` on Alpine, or Arch, or a minimal Docker base image, or — let me tell you about a fun Friday afternoon — Amazon Linux 2023, things start falling apart in ways that are not obvious and are absolutely not caught by the module guard at the top of the psm1.

`lsblk` might not be installed. `ss` might not be installed (older distros still ship `netstat`). `systemctl` is not a thing if you are running inside a container without an init system. `getent` exists but the underlying NSS modules it queries vary. `apt` is Debian/Ubuntu — try running `Update.Linux` on a RHEL-family system and it will not even get to the command.

Every module I have written has a hidden dependency list that goes unstated: "this works on a reasonably modern Debian or Ubuntu with the standard package set and a functioning init system." That is a lot of asterisks.

## Why this is harder than it looks

The obvious answer is: detect the distro and branch. Which sounds reasonable until you try to write it.

```powershell
function Get-NetTCPConnection {
    if (Test-Path /usr/bin/ss) {
        # parse ss output
    } elseif (Test-Path /usr/bin/netstat) {
        # parse netstat output — different columns, different field ordering
    } elseif (Test-Path /usr/sbin/netstat) {
        # same but different path, Alpine does this
    } else {
        Write-Error "No suitable network tool found on this system."
    }
}
```

That is manageable for two tools. Now multiply by thirty cmdlets across eight modules, add the fact that the output format of `ss` changed between versions, and that `netstat` on BSD is different from `netstat` on Linux, and you start to see the shape of the maintenance problem you are signing yourself up for.

The thing about wrapping CLI tools is that the CLI tool is not a stable API. It never was. Output format is documentation, not contract. `lsblk --json` is fairly stable, but only from util-linux 2.27 onwards, and older systems exist. I know because I have worked on them.

And then there is the fun category of tools where not only the location varies but the package name does too. `ss` is in `iproute2` on Debian-family and `iproute` on RedHat-family and might not be present at all in a minimal image. You cannot even give reliable installation instructions.

## Pondering a different approach

What if the module did not call a CLI tool at all?

This is what PKI.Linux ended up being, almost by accident. When I went to research the implementation, the first question was "which OpenSSL CLI commands map to which Windows PKI cmdlets?" The answer was messy — the openssl CLI is not designed around the same concepts as the Windows PKI module, the flags are arcane, and there are at least two major openssl versions (1.x and 3.x) with different option names.

Then I remembered that .NET's `System.Security.Cryptography` namespace is fully cross-platform. `CertificateRequest.CreateSelfSigned()` was added in .NET Core 2.0. `X509Chain.Build()` runs on Linux. `X509Store` with the `CurrentUser` location works. The whole thing is there, under PowerShell's feet, without needing a single external command.

So: no CLI wrapping. No distro detection. No "is ss installed?" No version sniffing. Just .NET types that are present wherever PowerShell 7 runs. PKI.Linux ended up being simpler to write and more portable than any of the CLI-wrapping modules.

The question I have been sitting with since is: how many of the other Windows modules could be approached the same way?

## What .NET actually covers

More than you might expect. I went through the gap cmdlets from Evgenij's list with this question in mind.

**Networking** — `System.Net.NetworkInformation` has `NetworkInterface.GetAllNetworkInterfaces()`, `IPGlobalProperties.GetActiveTcpConnections()`, `GetIPv4GlobalStatistics()`. Not everything `Get-NetIPAddress` returns is there, but the core data — adapter names, addresses, connection state, TCP endpoints — is accessible without calling `ip` or `ss`. `System.Net.Dns` covers `Resolve-DnsName` for basic lookups.

**Process and service management** — `System.Diagnostics.Process` is already what `Get-Process` uses under the hood on Linux. Services via `System.ServiceProcess.ServiceController` — this one is more complicated; on Linux the class exists but is backed by systemd via D-Bus, and it only works if D-Bus is available. Probably not a clean win.

**Certificates** — already done. This is the PKI.Linux story.

**File system ACLs** — `System.Security.AccessControl` exists but its Linux support is limited. Posix ACLs are not in the .NET standard library. `PowerShell.Security.Linux` stays a CLI wrapper.

**Local users and groups** — `System.DirectoryServices.AccountManagement` has `PrincipalContext`, `UserPrincipal`, `GroupPrincipal`. The question is whether it works on Linux via LDAP. Short answer: in limited scenarios, yes. For local accounts against `/etc/passwd`, probably not without additional configuration. `PowerShell.LocalAccounts.Linux` is probably staying as a CLI module.

**Printing** — `System.Drawing.Printing` exists but is essentially Windows-only for the actual print subsystem interaction. CUPS has no .NET API surface. PrintManagement.Linux is a CLI module.

So the realistic picture is: networking and certificates are candidates for pure .NET implementations. Services are borderline. Everything else is CLI.

## Touching on class-based programming

There is another angle to this that I have not talked about yet in this series.

Right now every module is a collection of functions. Some of them have a lot of shared logic. `Get-NetIPAddress` and `Get-NetIPConfiguration` both need to enumerate network interfaces. If I switch from CLI parsing to .NET API calls, they would share `NetworkInterface.GetAllNetworkInterfaces()` as their starting point. In the CLI version I can just have both functions call the CLI and parse independently. In a .NET version, it would make sense to centralise the interface-enumeration logic.

In PowerShell that means either a helper function (what I have been doing) or a class.

PowerShell classes have been around since v5. They are not used much in the community — most people are used to the function-based model and classes feel like they add ceremony. But for wrapping .NET types that have inherent object structure, a class can make the relationship explicit.

Something like:

```powershell
class LinuxNetworkInterface {
    [string] $Name
    [string] $Description
    [System.Net.NetworkInformation.NetworkInterfaceType] $InterfaceType
    [System.Net.NetworkInformation.OperationalStatus] $Status
    [System.Net.NetworkInformation.UnicastIPAddressInformationCollection] $UnicastAddresses

    LinuxNetworkInterface([System.Net.NetworkInformation.NetworkInterface] $iface) {
        $this.Name            = $iface.Name
        $this.Description     = $iface.Description
        $this.InterfaceType   = $iface.NetworkInterfaceType
        $this.Status          = $iface.OperationalStatus
        $this.UnicastAddresses = $iface.GetIPProperties().UnicastAddresses
    }
}
```

Then `Get-NetIPAddress` and `Get-NetIPConfiguration` both instantiate `LinuxNetworkInterface` objects and select the properties they need. One place for the interface-to-object mapping. One place to fix if something changes.

This is not a radical idea. It is just applying basic OOP principles to a domain where they fit. The resistance is partly cultural — PowerShell has always been function-first — and partly practical: debugging class-based code in PowerShell is slightly more awkward, and the class syntax in PowerShell has some rough edges (no interface enforcement, limited inheritance, no generics).

I am not committing to rewriting everything with classes. But for a hypothetical `NetTCPIP.Linux` v2 built on .NET APIs rather than CLI parsing, a class layer would be the right structure.

## PKI.Linux as the proof of concept

PKI.Linux is the first module in the set built entirely without CLI dependencies. It works on any distro where PowerShell 7 runs. There is no `if (Test-Path /usr/bin/openssl)`. There is no output parsing. There is no version sniffing.

It is also simpler. The functions are shorter. The logic is closer to what `New-SelfSignedCertificate` actually does rather than being a translation layer between a PowerShell concept and an openssl flag. `CertificateRequest.CreateSelfSigned()` does what the name says.

The limitations are real — `LocalMachine\My` throws on Linux because the .NET runtime defers to a system certificate store that does not work the same way, and enrollment-server cmdlets are stubs because there is simply no Linux equivalent. But these are honest limitations rather than hidden ones. The module does not pretend to support things it cannot support.

Whether the same approach is worth applying to networking is a question of trade-offs. The .NET networking APIs are lower-level than I would like — you have to do more assembly work to reconstruct what `Get-NetIPAddress` returns. But the output is distro-independent, and that feels increasingly valuable the more I think about the audience for these modules.

## Where this leaves things

PKI.Linux is a side step and a proof of concept, not a pivot.

The CLI-wrapping approach is not going away. For printing, package management, most of the management modules — there is no .NET API equivalent. CLI wrapping is the right tool for those.

But for the next iteration of the networking modules, I want to at least investigate how far `System.Net.NetworkInformation` can carry us before falling back to `ip` and `ss`. If it can cover the common cases, the resulting module would work on Arch, on Alpine, on Amazon Linux, on a Docker scratch container with PowerShell somehow wedged in — anywhere .NET runs.

That investigation is what comes next, alongside PrintManagement.Linux which is firmly in the CLI-wrapping camp and does not raise these questions at all.

There is something slightly satisfying about a module series that ends up questioning one of its own founding assumptions halfway through. It means something was learned along the way.






