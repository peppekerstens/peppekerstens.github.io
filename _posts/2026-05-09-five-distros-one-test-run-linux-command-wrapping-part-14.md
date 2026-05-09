---
title: Five distros, one test run - Linux Command Wrapping Part 14
toc: true
---

Part 13 ended with a known gap. Fourteen modules, 0 PSSA issues, 0 test failures - all on a single Ubuntu WSL2 instance. That is fine as a development baseline but it leaves an obvious question unanswered: does any of this actually work on Fedora? On Arch? On openSUSE?

Stage 4 was about closing that gap. Pre-built container images, GitHub Actions workflows, Docker Compose for local runs, and a workspace-level script to drive all fourteen modules at once. The goal was simple to state: every module, every push, tested on five Linux distributions.

Getting there was not simple.

## Why five separate images and not one shared base

The first design question was whether to have one image per distro or a single shared base with layers on top. The shared base idea is attractive. Install PowerShell and Pester once, layer the rest.

The problem is the tool set. Each module's tests call into Linux CLI tools: `ip`, `ss`, `ping`, `nc`, `sysctl`, `parted`, `fdisk`, `lpoptions`, `smbstatus`, `nfsstat`. The packages that provide those tools are named differently across distros. `netcat` is `netcat-openbsd` on Ubuntu and Debian, `nmap-ncat` on Fedora, `openbsd-netcat` on Arch. `dig` is in `dnsutils` on Debian-family, `bind-utils` on RHEL-family and openSUSE, `bind` on Arch.

A shared base would hide all of that behind an abstraction with nothing to abstract. The actual complexity is in the per-distro package names - that is exactly what needs to be visible. Five separate Dockerfiles with the names spelled out is more honest than one Dockerfile that somehow resolves them at build time.

## Installing PowerShell - three different methods

Ubuntu and Debian are the easy case. Microsoft publishes a `.deb` package through their APT repository, so it is `apt-get install powershell` after adding the repo.

Fedora, openSUSE, and Arch are different. The original Dockerfiles used the Microsoft RHEL9 RPM repository for Fedora and openSUSE. That seemed reasonable - Fedora is the upstream of RHEL, so RHEL9 packages should be compatible. They are not. The RPM installs, but the runtime crashes on incompatible system libraries. The error is not obvious - it just exits silently with a non-zero code.

The fix was to use the upstream tarball from GitHub releases directly:

```dockerfile
RUN curl -sSL https://github.com/PowerShell/PowerShell/releases/download/v7.6.1/powershell-7.6.1-linux-x64.tar.gz \
        -o /tmp/pwsh.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && rm /tmp/pwsh.tar.gz \
    && ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
```

That tarball works on any distro with a current enough glibc. Fedora 40, openSUSE Tumbleweed, and Arch all use it. Arch uses it for the same reason - AUR requires `makepkg`, which requires a non-root user with sudo, which is a lot of Dockerfile plumbing for something the tarball replaces in three lines.

## The openSUSE problem

The original openSUSE Dockerfile used `opensuse/leap:15.6`. Reasonable choice - Leap is the stable release. It does not work.

Leap 15.6 ships glibc 2.31. PowerShell 7.6.1 requires a newer glibc and segfaults silently at startup. No error, no output, exit code 139. This took a while to diagnose because the container itself starts fine. It is only when `pwsh` runs that it crashes. Spotted it by running `pwsh --version` inside the container manually and watching it produce nothing.

The fix is `opensuse/tumbleweed`. Tumbleweed is the rolling release - current glibc, current packages. That introduces the usual rolling-release concern (the image content changes without a version bump) but it is the only option that works with PS 7.6.1.

openSUSE also needed two extra packages that the other images pull in transitively: `gzip` (the base image does not include it, so `tar -xzf` fails silently - a particularly confusing failure mode) and `libicu` (required by the .NET globalization stack; absent from the base and not a transitive dependency of anything else installed). The symptom of missing `libicu` is PowerShell starting and immediately printing a globalization error, which at least tells you what is wrong.

## `ping` and capabilities

After fixing the PS install, the next failure was `ping`.

`Test-NetConnection` calls `ping -c 1 -W 2 <host>`. In the container, `ping` is installed. The command returns exit code 1 and "Operation not permitted."

The issue is `CAP_NET_RAW`. ICMP raw sockets require this Linux capability. In a rootless container - which is what GitHub Actions uses for container jobs - the capability is dropped. The binary is there, the network is there, but the kernel refuses the socket creation.

The fix is `--cap-add=NET_RAW`:

```yaml
# docker-compose.test.yml
services:
  ubuntu-24.04:
    image: ghcr.io/peppekerstens/pwsh-pester-ubuntu:24.04
    cap_add:
      - NET_RAW
```

And in the GitHub Actions workflow:

```yaml
container:
  image: ${{ matrix.distro.image }}
  options: --cap-add=NET_RAW
```

This is a real capability with real security implications. Adding it to a CI container is reasonable - isolated job, torn down immediately after. But it is worth knowing you are doing it deliberately rather than by accident.

## Getting Podman running in WSL2

Podman was not installed on this machine. The obvious approach - `podman machine init` on Windows - downloads a VM image from `quay.io`. On this machine, the TLS connection times out before the download completes. I sat through two timeout failures before trying something else.

The alternative: install Podman directly inside WSL2.

```bash
sudo apt-get install podman
```

Podman 5.7.0, inside the WSL2 Ubuntu instance, no VM required. `wsl -u root podman build` and `wsl -u root podman run` both work correctly after one more dependency:

```bash
sudo apt-get install nftables
```

Podman's `netavark` network backend calls `nft` at container startup to configure network rules. Without it:

```
netavark: nftables error: unable to execute "nft": No such file or directory
```

Not an obvious error when you do not already know what `netavark` is. Once I had both installed, containers started and networks worked.

## The GitHub Actions artifact name bug

The first version of the GHA workflow matrix used image tags as distro identifiers:

```yaml
matrix:
  distro: [ubuntu:24.04, debian:12, fedora:40, opensuse/tumbleweed, arch-latest]
```

The artifact upload step used `matrix.distro` as the artifact name. GitHub Actions artifact names cannot contain `:` or `/`. `pester-ubuntu:24.04` and `pester-opensuse/tumbleweed` both fail at upload time with a validation error. I only found this out when the first workflow run finished.

The fix is a separate slug field in the matrix:

```yaml
matrix:
  distro:
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-ubuntu:24.04',        slug: ubuntu-24.04 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-debian:12',           slug: debian-12 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-fedora:40',           slug: fedora-40 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-opensuse:tumbleweed', slug: opensuse-tumbleweed }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-arch:latest',         slug: arch-latest }
```

The container uses `matrix.distro.image`. The artifact name uses `matrix.distro.slug`. One is a valid Docker image reference, the other is a valid artifact name, they do not need to be the same string.

## Pester discovery without a path

The first version of the GHA workflow ran:

```yaml
- run: pwsh -NoProfile -Command "Invoke-Pester -Output Detailed"
```

No `-Path`. Pester without a path discovers tests by walking the current directory recursively. The current directory in a GHA container job is the repo root. It finds the test file in `<ModuleName>/<ModuleName>.Tests.ps1` - and also finds `Examples/Examples.Tests.ps1`, which tries to import the module, which is not installed system-wide, which throws a discovery error before any tests run. Not a hard failure, but confusing output in the artifact.

The fix is explicit:

```yaml
- run: pwsh -NoProfile -Command "Invoke-Pester -Path './<ModuleName>' -Output Detailed"
```

Obvious in retrospect. The template now needs to be customised per module rather than copy-pasted. Not ideal, but correct.

## Results

After all the fixes, NetTCPIP.Linux was the validation module - 141 tests, including `Test-NetConnection` which exercises `ping` and the `CAP_NET_RAW` path:

| Distro | Pass | Fail | Skip |
|---|---|---|---|
| Ubuntu 24.04 | 141 | 0 | 0 |
| Debian 12 | 141 | 0 | 0 |
| Fedora 40 | 141 | 0 | 0 |
| openSUSE Tumbleweed | 141 | 0 | 0 |
| Arch Linux | 141 | 0 | 0 |

141/141 across all five distros. No skips. The tools that were previously absent from WSL2 are installed in every image. The platform differences in package names are handled in the Dockerfiles.

That is the difference between "tests pass on my machine" and "tests pass."

## The gap between writing and running

Session 1 wrote all the Dockerfiles and workflows. Session 2 found the artifact name bug and the missing `-Path`. Session 3 actually built the images and ran the containers.

There was a meaningful gap between sessions 1 and 2. The Dockerfiles were authored carefully but never run. The only check was reading them over and comparing against documentation. That is not enough. You find the RHEL9 RPM compatibility issue by running `podman build` and watching it fail. You find the missing `libicu` by running `pwsh` inside the container and reading the error. You find the `CAP_NET_RAW` problem by running the tests and seeing "Operation not permitted."

This is not a novel insight. Infrastructure code is not different from any other code: you have to run it.

The reason there was a session gap before running is that Podman was not installed. The time spent sorting that out - TLS timeouts, WSL2 install path, `nftables` dependency - is time that could have been avoided if the test environment had been set up before the Dockerfiles were written. Or at minimum, before they were committed.

Noted for Stage 5.

## Next

Stage 5 is a different kind of work. The question is whether to port selected cmdlets to C# for potential upstream contribution to the PowerShell project itself, or build external binary modules as an intermediate step. The Stage 1 PowerShell implementations are the functional spec. The Stage 4 matrix is the test harness. The question is whether the implementations are good enough to serve as a blueprint for C# translations.

That is a longer conversation. It involves RFCs, CLAs, and code review by the PowerShell team. It also involves admitting that "looks correct in PowerShell" is not the same as "correct enough for a production OS-level cmdlet." Stage 5 is going to be more deliberate than the previous stages.

But that is for the next post.
