# Plan

Stabilize this Jekyll blog (Minimal Mistakes theme, GitHub Pages), fix build failures, and lock in reproducible setup.

## Progress

### Phase 1 — Fix build failures

GitHub Actions build was failing. Root cause: a post was re-dated, breaking `{% post_url %}` cross-references in later posts that referenced the old date.

**Done:**
- [x] Fix stale `post_url` refs in `2026-05-02-building-the-modules-linux-command-wrapping-part-8.md` (Part 7: `2026-05-08`→`2026-05-01`, Part 10: `2026-05-08`→`2026-05-04`)
- [x] Synthesize unique dates for all posts (May 1–12) so GitHb Pages sorts them correctly
- [x] Verify site builds cleanly with `bundle exec jekyll build`

### Phase 2 — Strip stale theme overrides

The repo had ~11,800 lines of local copies of Minimal Mistakes layouts, includes, and Sass — likely from an earlier `jekyll new` or theme extraction. These override the remote theme and rot over time.

**Done:**
- [x] Remove `_layouts/`, `_includes/`, `_sass/minimal-mistakes/` directories
- [x] Pin remote theme to `mmistakes/minimal-mistakes@4.28.0` in `_config.yml`
- [x] Keep only custom overrides that actually differ from theme (none needed currently)
- [x] Remove `jekyll-include-cache` gem dependency (bundled with theme)

### Phase 3 — Clean up dead config and artifacts

**Done:**
- [x] Remove `staticman.yml` (dead config for a comments system not in use)
- [x] Remove root `package.json` / `package-lock.json` (VS Code / theme artifacts)
- [x] Replace 400-line VS Code `.gitignore` with minimal Jekyll-focused one
- [x] Clean up `_config.yml` — prune commented-out `jekyll-paginate-v2` config, tighten `exclude` list

### Phase 4 — Set up opencode with GitHub MCP

**Done:**
- [x] Add `.opencode/opencode.json` with `@modelcontextprotocol/server-github` MCP server
- [x] Configure `GITHUB_TOKEN` env var for the MCP server
- [x] Add `export GITHUB_TOKEN` to `~/.bashrc`
- [x] Write `.opencode/.gitignore`

### Phase 5 — Lock in reproducible builds

Builds need `Gemfile.lock` committed. Generating it requires Ruby + Bundler.

**Approach preference:** containerized (podman). Docker Hub is unreachable from this machine (TLS timeout); `ghcr.io` works with auth but Ruby/Jekyll images aren't readily available there.

**Done:**
- [x] Generate `Gemfile.lock` using brew-installed Ruby as a one-time bootstrap (pragmatic workaround)
- [x] Remove `Gemfile.lock` from `.gitignore` so it is tracked
- [x] Write `Containerfile` — portable Docker/podman build for future use
- [x] Write `.opencode/skills/containerized-jekyll/SKILL.md` — documents containerized workflow with podman, registry fallbacks, and mirror config

## Constraints

| Constraint | Detail |
|------------|--------|
| No Ruby/Bundler installed natively | Only available via brew one-time; don't rely on it |
| Docker Hub unreachable | TLS handshake timeout — use ghcr.io or mirrors |
| ghcr.io auth required | Auth file at `~/.config/containers/auth.json`; `podman login` fails (no tty) |
| Browser can reach registries | Firefox on same machine can pull images — but not helpful for CLI |
| GITHUB_TOKEN available | ghp token set in ~/.bashrc; works for API and git push |
| podman version | 5.7.0 |

## Key Decisions

- `Gemfile.lock` is committed (not gitignored). Without it, GitHub Actions rebuilds from scratch each time with potentially different dependency resolutions.
- Remote theme is preferred over local overrides. Keeps the repo small and automatically gets theme fixes.
- Containerized workflow is the documented standard (skill file). If a registry is available, use `podman run`; if not, brew is the escape hatch.

## Relevant Files

| File | Purpose |
|------|---------|
| `_config.yml` | Remote theme pinned, exclude list cleaned |
| `Gemfile` | Dependencies: `github-pages` + `jekyll-include-cache` |
| `Gemfile.lock` | Locked dependency tree for reproducible builds |
| `Containerfile` | Docker/podman build definition |
| `.opencode/opencode.json` | GitHub MCP server config |
| `.opencode/skills/containerized-jekyll/SKILL.md` | Containerized workflow documentation |
| `.gitignore` | Minimal Jekyll-focused ignore rules |
| `plan.md` | This file — development plan and progress |
