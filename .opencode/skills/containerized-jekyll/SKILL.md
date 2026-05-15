---
name: containerized-jekyll
description: Use ONLY when performing Jekyll operations (build, serve, bundle) on this repo. Prefers podman with ghcr.io fallback over docker.io.
---

# Containerized Jekyll Workflow

This repository prefers **podman** for all Jekyll operations. Docker Hub (`docker.io`) is often unreachable from this build environment — always use `ghcr.io` as fallback.

## Generating / Updating Gemfile.lock

```bash
podman run --rm -v "$PWD:/site:Z" -w /site \
  docker.io/library/ruby:3.4-slim \
  bash -c "bundle lock && bundle install"
```

If Docker Hub is unreachable, use `ghcr.io/catthehacker/ubuntu:act-latest` and install Ruby manually:

```bash
podman run --rm -v "$PWD:/site:Z" -w /site \
  ghcr.io/catthehacker/ubuntu:act-latest \
  bash -c "apt-get update -qq && apt-get install -y -qq ruby bundler && bundle lock"
```

## Building the site

```bash
podman run --rm -v "$PWD:/site:Z" -w /site \
  docker.io/library/ruby:3.4-slim \
  bash -c "bundle install && bundle exec jekyll build"
```

## Local dev server

```bash
podman run --rm -v "$PWD:/site:Z" -w /site -p 4000:4000 \
  docker.io/library/ruby:3.4-slim \
  bash -c "bundle install && bundle exec jekyll serve --host 0.0.0.0"
```

## Registry Mirrors

If the default registry is slow, configure a mirror in `/etc/containers/registries.conf.d/mirror.conf`:

```
[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "ghcr.io/mirror"
```
