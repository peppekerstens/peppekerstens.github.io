---
title: Five distros, one test run - Linux Command Wrapping Part 14
toc: true
---

Part 13 ended with a known gap. Fourteen modules, 0 PSSA issues, 0 test failures - all on a single Ubuntu WSL2 instance. That is fine as a development baseline but it leaves an obvious question unanswered: does any of this actually work on Fedora? On Arch? On openSUSE?

Stage 4 was about closing that gap. Pre-built container images, GitHub Actions workflows, Docker Compose files, and a local test runner. The goal: every module, every push, tested on five Linux distributions.

Here is what happened.

## The plan

The original Stage 4 design called for:

1. A `testinfra` repository under `peppekerstens` with one `Dockerfile.*` per distro - each image has PowerShell 7, Pester 5, and PSScriptAnalyzer pre-installed, plus the Linux tool set the module tests actually exercise.
2. A GitHub Actions workflow (`build-images.yml`) that builds and pushes all five images to GHCR on Dockerfile changes.
3. A `.github/workflows/pester.yml` in each of the 14 module repos, running the full Pester suite against a 5-distro matrix.
4. A `docker-compose.test.yml` in each module repo for local runs.
5. A workspace-level `run-tests-docker.ps1` that drives all 14 modules in sequence.

On paper it is a straightforward infrastructure job. In practice it involved a sequence of bugs that only showed up when you actually ran the containers.

## Why not a single shared base image

The first design question was whether to have one image per distro or a single shared base. The shared base idea is attractive - install PowerShell and Pester once, layer on top.

The problem is the tool set. Each module test suite calls into Linux CLI tools: `ip`, `ss`, `ping`, `nc`, `sysctl`, `parted`, `fdisk`, `lpoptions`, `smbstatus`, `nfsstat`. The packages that provide those tools are named differently across distros. `netcat` is `netcat-openbsd` on Ubuntu and Debian, `nmap-ncat` on Fedora, `openbsd-netcat` on Arch. `ps` and `kill` come from `procps` on Ubuntu, `procps-ng` on Fedora and Arch. `dig` is in `dnsutils` on Debian-family, `bind-utils` on RHEL-family and openSUSE, `bind` on Arch.

A shared base would hide all of that behind an abstraction layer with nothing to abstract. The actual complexity is in the per-distro package names - that is exactly what needs to be visible and explicit. Five separate Dockerfiles with the per-distro names spelled out is more honest than one Dockerfile that somehow resolves package names at build time.

## PowerShell install - three different methods

Ubuntu and Debian are the easy case. Microsoft publishes a `.deb` package through their APT repository, so it is just `apt-get install powershell` after adding the repo.

Fedora, openSUSE, and Arch are different. The original Dockerfiles used the Microsoft RHEL9 RPM repository for Fedora and openSUSE. This seemed reasonable - Fedora is the upstream of RHEL, so RHEL9 packages should be compatible. They are not. The RPM installs, but the runtime crashes on incompatible system libraries. The fix is the upstream tarball from GitHub releases:

```dockerfile
RUN curl -sSL https://github.com/PowerShell/PowerShell/releases/download/v7.6.1/powershell-7.6.1-linux-x64.tar.gz \
        -o /tmp/pwsh.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && rm /tmp/pwsh.tar.gz \
    && ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
```

That tarball works on any distro with a current enough glibc. Fedora 40, openSUSE Tumbleweed, and Arch all use it.

Arch uses the tarball for the same reason - AUR is not available in rootless containers. AUR requires `makepkg`, which requires a non-root user with sudo, which is a lot of Dockerfile plumbing for something that the tarball replaces in three lines.

## The openSUSE problem

The original openSUSE Dockerfile used `opensuse/leap:15.6`. Reasonable choice - Leap is the stable release.

It does not work. Leap 15.6 ships glibc 2.31. The PowerShell 7.6.1 tarball requires a newer glibc and segfaults silently at startup - no error, no output, exit code 139. This took a while to diagnose because the container itself starts fine; it is only when `pwsh` runs that it crashes. `podman run` finishes instantly with a non-zero exit code and no useful message.

The fix is `opensuse/tumbleweed`. Tumbleweed is the rolling release - current glibc, current packages. That introduces a different concern (rolling release means the image content changes over time without a version bump) but it is the only option that works. Pinning to a Leap release with a current glibc would require Leap 16, which was not available at the time.

openSUSE also needed two extra packages that the others pulled in transitively: `gzip` (the base image does not include it, so `tar -xzf` fails silently) and `libicu` (required by the .NET globalization stack; absent from the base image and not a transitive dependency of anything else we install). Both are easy to add once you know they are missing. The symptom of a missing `libicu` is PowerShell starting and immediately printing a globalization error, which at least is diagnosable.

## `ping` and the capability problem

After fixing the PS install, the next failure was `ping`.

`Test-NetConnection` calls `ping -c 1 -W 2 <host>`. In the container, `ping` is installed and executable. The command returns exit code 1 and the message "Operation not permitted."

The issue is `CAP_NET_RAW`. ICMP raw sockets require this Linux capability. In a rootless container - which is what Podman uses by default, and what GitHub Actions uses for container jobs - the capability is dropped. The binary is there, the network is there, but the kernel refuses the socket creation.

The fix is `--cap-add=NET_RAW` on `docker run` or `cap_add: [NET_RAW]` in compose:

```yaml
services:
  ubuntu-24.04:
    image: ghcr.io/peppekerstens/pwsh-pester-ubuntu:24.04
    cap_add:
      - NET_RAW
    volumes:
      - ".:/module"
```

And in the GitHub Actions workflow:

```yaml
container:
  image: ${{ matrix.distro.image }}
  options: --cap-add=NET_RAW
```

This is a real capability with real security implications. Adding it to a CI container is reasonable - you are running tests in an isolated job, and the alternative is having `Test-NetConnection` skipped on every distro. But it is worth knowing you are doing it deliberately rather than by accident.

## Podman in WSL2

Podman was not installed on this machine. The obvious approach - `podman machine init` on Windows - downloads a VM image from `quay.io`. On this machine, the TLS connection times out before the download completes.

The alternative: install Podman directly inside WSL2.

```bash
sudo apt-get install podman
```

That gives you Podman 5.7.0 inside the WSL2 Ubuntu instance. From there, `wsl -u root podman build` and `wsl -u root podman run` work correctly. No VM, no `quay.io` download, no TLS timeout.

One additional requirement: `nftables`. Podman's `netavark` network backend calls `nft` at container startup to configure network rules. If `nftables` is absent from the WSL2 environment, every `podman run` fails with:

```
netavark: nftables error: unable to execute "nft": No such file or directory
```

```bash
sudo apt-get install nftables
```

That is all it takes. After that, containers start and networks work.

## GitHub Actions artifacts and the colon problem

The `.github/workflows/pester.yml` template in each module repo uses a matrix strategy. The first version of that matrix used image tags directly as distro identifiers:

```yaml
matrix:
  distro: [ubuntu:24.04, debian:12, fedora:40, opensuse/tumbleweed, arch-latest]
```

The artifact upload step used `matrix.distro` as the artifact name:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: pester-${{ matrix.distro }}
```

GitHub Actions artifact names cannot contain `:` or `/`. `pester-ubuntu:24.04` and `pester-opensuse/tumbleweed` both fail at upload time with a validation error.

The fix is a separate `slug` field in the matrix:

```yaml
matrix:
  distro:
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-ubuntu:24.04',        slug: ubuntu-24.04 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-debian:12',           slug: debian-12 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-fedora:40',           slug: fedora-40 }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-opensuse:tumbleweed', slug: opensuse-tumbleweed }
    - { image: 'ghcr.io/peppekerstens/pwsh-pester-arch:latest',         slug: arch-latest }
```

Then the container uses `matrix.distro.image` and the artifact name uses `matrix.distro.slug`. One is a valid Docker image reference; the other is a valid artifact name. They do not need to be the same string.

## Pester path in GHA

The first version of the GHA workflow ran:

```yaml
- run: pwsh -NoProfile -Command "Invoke-Pester -Output Detailed"
```

No `-Path`. When Pester runs without a path, it discovers tests by walking the current directory recursively. The current directory in a GHA container job is the repo root. The test file is in `<ModuleName>/<ModuleName>.Tests.ps1`. Pester finds it - usually. But it also finds any stray `.Tests.ps1` files elsewhere in the repo (the `Examples/Examples.Tests.ps1` files, for instance), runs them, and the results are mixed together in the artifact.

More importantly, when there is an `Examples.Tests.ps1` that imports the module, and the module is not installed system-wide, Pester's discovery phase throws an error before any tests run. That error does not cause the job to fail (discovery errors are warnings in Pester 5), but it is confusing noise.

The fix is explicit:

```yaml
- run: pwsh -NoProfile -Command "Invoke-Pester -Path './<ModuleName>' -Output Detailed -PassThru | Export-Clixml results.xml"
```

Straightforward, but it means the workflow template has to be customised per module rather than being a shared copy-paste. Not ideal, but correct.

## Validation results

After all the fixes, NetTCPIP.Linux was used as the validation module - it has the most interesting test coverage (141 tests, including `Test-NetConnection` which exercises `ping` and the `CAP_NET_RAW` requirement):

| Distro | Pass | Fail | Skip |
|---|---|---|---|
| Ubuntu 24.04 | 141 | 0 | 0 |
| Debian 12 | 141 | 0 | 0 |
| Fedora 40 | 141 | 0 | 0 |
| openSUSE Tumbleweed | 141 | 0 | 0 |
| Arch Linux | 141 | 0 | 0 |

141/141 across all five distros. No skips - the tools that were previously absent from WSL2 (`ping`, `nc`, `sysctl`) are installed in every image. No failures - the platform differences in package names and install methods are handled in the Dockerfiles.

That is the difference between "tests pass on my machine" and "tests pass."

## What the infrastructure looks like now

Each module repo has:

- `.github/workflows/pester.yml` — 5-distro Linux matrix + Windows bare runner; runs on every push
- `docker-compose.test.yml` — one service per distro, `cap_add: [NET_RAW]`; for local runs

The `testinfra` repo has:

- `Dockerfile.ubuntu`, `Dockerfile.debian`, `Dockerfile.fedora`, `Dockerfile.opensuse`, `Dockerfile.arch`
- `.github/workflows/build-images.yml` — builds and pushes all images to GHCR on Dockerfile changes

Run locally:

```powershell
# From any module repo root
docker compose -f docker-compose.test.yml up --abort-on-container-exit

# From the workspace root, all 14 modules
.\run-tests-docker.ps1

# Single module
.\run-tests-docker.ps1 -Module NetTCPIP.Linux
```

## The gap between sessions 1 and 3

Session 1 wrote all the Dockerfiles and workflows. Session 2 found the artifact name bug and the missing `-Path`. Session 3 actually built the images and ran the containers.

There was a meaningful gap between sessions 1 and 2. The Dockerfiles were authored carefully but never run. The only check was reading them over and comparing against documentation. That is not enough. You find the RHEL9 RPM compatibility problem by running `podman build` and watching it fail. You find the `libicu` problem by running `pwsh` inside the container and reading the error. You find the `CAP_NET_RAW` problem by running the tests and seeing "Operation not permitted."

This is obvious in retrospect. Infrastructure code is not different from any other code in this respect: you have to run it.

The reason there was a session gap before running is that Podman was not installed. The time spent fixing that - dealing with the `quay.io` timeout, finding the WSL2 install path, sorting out the `nftables` dependency - is time that could have been avoided if the test environment had been set up before the Dockerfiles were written. Or at minimum, before they were committed and pushed.

Noted for Stage 5.

## Next

Stage 5 is a different kind of work. The question is whether to port selected cmdlets to C# for potential upstream contribution to the PowerShell project itself - or to build external binary modules as an intermediate step. The Stage 1 PowerShell implementations are the functional spec. The Stage 4 matrix is the test harness. The question is whether the implementations are good enough to serve as a blueprint for C# translations, and whether the upstream contribution process is worth pursuing.

That is a longer conversation. It involves RFCs, CLAs, and code review by the PowerShell team. It also involves admitting that "looks correct in PowerShell" is not the same as "correct enough for a production OS-level cmdlet." Stage 5 is going to be more deliberate and more uncomfortable than the previous stages.

But that is for the next post.

