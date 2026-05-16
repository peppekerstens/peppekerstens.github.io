# Plan

Stabilize this Jekyll blog (Minimal Mistakes theme, GitHub Pages), fix build failures, and lock in reproducible setup.

## Progress

### Phase 1 — Fix build failures

GitHub Actions build was failing. Root cause: a post was re-dated, breaking `{% post_url %}` cross-references in later posts that referenced the old date.

**Done:**
- [x] Fix stale `post_url` refs in `2026-05-02-building-the-modules-powershell-linux-commands-part-8.md` (Part 7: `2026-05-08`→`2026-05-01`, Part 10: `2026-05-08`→`2026-05-04`)
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

**Approach preference:** containerized (podman). Docker Hub may have TLS issues; `ghcr.io` works with auth.

**Done:**
- [x] Generate `Gemfile.lock` using brew-installed Ruby as a one-time bootstrap (pragmatic workaround)
- [x] Remove `Gemfile.lock` from `.gitignore` so it is tracked
- [x] Write `Containerfile` — portable Docker/podman build definition
- [x] Write `.opencode/rules/containerized-tooling.md` — **auto-loaded opencode rule** with exact tested podman recipes (primary: `ghcr.io/ruby/ruby:3.2.1-jammy`, fallback: `docker.io/library/ruby:3.4-slim`)
- [x] Write `.opencode/skills/containerized-jekyll/SKILL.md` — higher-level skill documentation referencing the rule for authoritative commands
- [x] Identify available ghcr.io Ruby images (`ghcr.io/ruby/ruby:3.2.1-jammy` confirmed available via API)
- [x] Confirm ghcr.io auth works (curl returns 200 with auth token)
- [x] Confirm Docker Hub reachable (returns 401 — no TLS timeout on retry; earlier failure was transient)

### Phase 6 — Enforce blog creation rules

Two hard requirements for all blog posts. Non-negotiable.

**Done:**
- [x] Write `.opencode/rules/blog-creation.md` — **auto-loaded rule** for `_posts/*` files
- [x] Rule 1: Date synthesis — every post MUST have a unique date; same-day posts get synthesized dates
- [x] Rule 2: Tone calibration — part-1 through part-12 in `_posts/` MUST be read before drafting any new post
- [x] Update `.opencode/commands/blog.md` to reference the hard requirements rule
- [x] Copy `.opencode/skills/writing-style/SKILL.md` from opencode repo

### Phase 7 — Rename blog series to reflect project evolution

The series was uniformly titled "Linux Command Wrapping" across all 20 parts, but the project shifted from CLI wrapping (Parts 1–6) to module engineering (Parts 7–13) to native C# and upstream contribution (Parts 14–20). The old name no longer describes what the posts are about.

**Done:**
- [x] Rename all 20 filenames: `linux-command-wrapping` → `powershell-linux-commands`
- [x] Update all 20 frontmatter titles
- [x] Update internal `{% post_url %}` cross-references (3 in Part 8)
- [x] Update markdown link in Part 5 (absolute URL to Part 3)
- [x] Add `redirect_from` frontmatter to all 20 posts for old URL preservation
- [x] Update `.opencode/commands/blog.md` — series name, filename pattern, frontmatter template
- [x] Remove stale `_drafts/linux command/` directory (3 superseded drafts)
- [x] Update `plan.md` references to renamed filenames

## Constraints

| Constraint | Detail |
|------------|--------|
| No Ruby/Bundler permanently installed natively | One-time brew bootstrap works; don't rely on it |
| Docker Hub | Reachable (returns 401 on retry); earlier TLS timeout was transient |
| ghcr.io | Works with auth file at `~/.config/containers/auth.json`; `podman login` fails (no tty) |
| `GITHUB_TOKEN` available | ghp token in `~/.bashrc`; works for API and git push |
| podman version | 5.7.0 |
| Blog date uniqueness | Every post MUST have a unique date — enforced by `.opencode/rules/blog-creation.md` |
| Blog tone calibration | Part-1 through part-12 MUST be read before drafting — enforced by `.opencode/rules/blog-creation.md` |

## Key Decisions

- `Gemfile.lock` is committed (not gitignored). Without it, GitHub Actions rebuilds from scratch each time with potentially different dependency resolutions.
- Remote theme is preferred over local overrides. Keeps the repo small and automatically gets theme fixes.
- Containerized workflow is mandatory — enforced by `.opencode/rules/containerized-tooling.md` (auto-loaded by opencode whenever Gemfile/Bundler/Jekyll files are involved).
- The **rule file** (not the skill) is the authoritative source for copy-paste podman commands. The skill is the higher-level overview.
- Blog creation rules are hard requirements — enforced by `.opencode/rules/blog-creation.md` (auto-loaded for all `_posts/*` files).

## Relevant Files

| File | Purpose |
|------|---------|
| `_config.yml` | Remote theme pinned, exclude list cleaned |
| `Gemfile` | Dependencies: `github-pages` + `jekyll-include-cache` |
| `Gemfile.lock` | Locked dependency tree for reproducible builds |
| `Containerfile` | Docker/podman build definition |
| `.opencode/opencode.json` | GitHub MCP server config |
| `.opencode/rules/containerized-tooling.md` | **Auto-loaded rule** — enforces podman-first workflow with tested recipes |
| `.opencode/rules/blog-creation.md` | **Auto-loaded rule** — enforces date synthesis and tone calibration for blog posts |
| `.opencode/commands/blog.md` | `/blog` command — references blog creation rule and writing-style skill |
| `.opencode/skills/containerized-jekyll/SKILL.md` | Containerized workflow overview — references rule for recipes |
| `.opencode/skills/writing-style/SKILL.md` | Personal writing conventions — copied from opencode repo |
| `.opencode/TOOLS.md` | Comprehensive reference of all available tools and capabilities |
| `.opencode/rules/working-principles.md` | **Auto-loaded rule** — work via opencode, defer to subtasks to overcome looping |
| `.gitignore` | Minimal Jekyll-focused ignore rules |
| `plan.md` | This file — development plan and progress |
