---
match: Gemfile*|Containerfile|*.gemfile|*.podman|*jekyll*|*bundle*
---

# MUST use podman for all Jekyll/Ruby/Bundler operations

All Ruby, Bundler, Jekyll, and Gemfile operations in this repo MUST run via **podman** containers.
Never install Ruby or gems directly on the host. Use one of the recipes below.

## Registry order (try in this order)

| Priority | Registry | Image | Notes |
|----------|----------|-------|-------|
| 1 | `ghcr.io` | `ghcr.io/ruby/ruby:3.2.1-jammy` | Fast with auth, smaller image |
| 2 | `docker.io` | `docker.io/library/ruby:3.4-slim` | May be unreachable (TLS timeout) |

## Prerequisites

- ghcr.io auth must exist at `~/.config/containers/auth.json`
- If missing, regenerate via browser:
  1. Go to https://github.com/settings/tokens
  2. Create PAT with `read:packages` scope
  3. Write token to auth file via Python tool

## Recipes

### Update Gemfile.lock (bundle lock)

```bash
podman run --rm --authfile ~/.config/containers/auth.json \
  -v "$PWD:/site:Z" -w /site \
  ghcr.io/ruby/ruby:3.2.1-jammy \
  bash -c "gem install bundler && bundle lock"
```

### Install gems (bundle install)

```bash
podman run --rm --authfile ~/.config/containers/auth.json \
  -v "$PWD:/site:Z" -w /site \
  ghcr.io/ruby/ruby:3.2.1-jammy \
  bash -c "gem install bundler && bundle install"
```

### Build Jekyll site

```bash
podman run --rm --authfile ~/.config/containers/auth.json \
  -v "$PWD:/site:Z" -w /site \
  ghcr.io/ruby/ruby:3.2.1-jammy \
  bash -c "gem install bundler && bundle install && bundle exec jekyll build"
```

### Docker Hub fallback (if ghcr.io fails)

```bash
podman run --rm \
  -v "$PWD:/site:Z" -w /site \
  docker.io/library/ruby:3.4-slim \
  bash -c "gem install bundler && bundle lock"
```

## Auth file format

The auth file at `~/.config/containers/auth.json` must contain:
```json
{
  "auths": {
    "ghcr.io": {
      "auth": "<base64(username:token)>"
    }
  }
}
```
