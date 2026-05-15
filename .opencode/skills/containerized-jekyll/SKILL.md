---
name: containerized-jekyll
description: Use ONLY when performing Jekyll operations (build, serve, bundle) on this repo. Prefers podman with ghcr.io fallback over docker.io.
---

# Containerized Jekyll Workflow

This repository prefers **podman** for all Jekyll operations. Never install Ruby/gems directly on the host.

The authoritative copy-paste recipes live in `.opencode/rules/containerized-tooling.md` (auto-loaded by opencode when working with Gemfile/Bundler/Jekyll files).

## Quick reference

| Task | Image | Command |
|------|-------|---------|
| `bundle lock` | `ghcr.io/ruby/ruby:3.2.1-jammy` | `podman run --rm --authfile ~/.config/containers/auth.json -v "$PWD:/site:Z" -w /site ghcr.io/ruby/ruby:3.2.1-jammy bash -c "gem install bundler && bundle lock"` |
| `bundle install` | same | same but `bundle install` |
| `jekyll build` | same | same but `bundle install && bundle exec jekyll build` |

## Registry order

1. **ghcr.io** (`ghcr.io/ruby/ruby:3.2.1-jammy`) — requires auth file at `~/.config/containers/auth.json`
2. **docker.io** (`docker.io/library/ruby:3.4-slim`) — fallback, may have TLS issues

## Auth setup

```bash
# Check if auth exists:
ls ~/.config/containers/auth.json

# ~/.config/containers/auth.json format:
# {"auths":{"ghcr.io":{"auth":"<base64(username:token)>"}}}
```

If missing, generate a GitHub PAT with `read:packages` scope at https://github.com/settings/tokens and write it to the auth file.

## Registry Mirrors

If the default registry is slow, configure a mirror in `/etc/containers/registries.conf.d/mirror.conf`:

```
[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "ghcr.io/mirror"
```
