# peppekerstens.github.io

Personal blog at [peppekerstens.github.io](https://peppekerstens.github.io) — Jekyll site using the Minimal Mistakes theme, hosted on GitHub Pages.

## Improvements

| Date | Change |
|------|--------|
| 2026-05-15 | Fix stale `post_url` references in Part 8 after post re-dating (Part 7: `2026-05-08`→`2026-05-01`, Part 10: `2026-05-08`→`2026-05-04`) |
| 2026-05-15 | Remove 11,800+ lines of stale local theme overrides (`_layouts/`, `_includes/`, `_sass/minimal-mistakes/`) — theme now provides these fresh |
| 2026-05-15 | Add opencode config with GitHub MCP server for API access |
| 2026-05-15 | Clean up commented-out `jekyll-paginate-v2` config |
| 2026-05-15 | Pin remote theme to `mmistakes/minimal-mistakes@4.28.0` |
| 2026-05-15 | Remove `staticman.yml`, root `package.json`/`package-lock.json` (dead config / theme artifacts) |
| 2026-05-15 | Replace 400-line VS Code `.gitignore` with Jekyll-focused one |
| 2026-05-15 | Clean up `_config.yml` exclude list |
| 2026-05-15 | Generate `Gemfile.lock` for reproducible builds; add `Containerfile` and containerized workflow skill |
| 2026-05-15 | Add `plan.md` with full development plan and progress tracking |
| 2026-05-15 | Add `.opencode/rules/containerized-tooling.md` auto-loaded rule enforcing podman workflow |
| 2026-05-15 | Sanitize `_config.yml` — remove dead boilerplate, empty fields, `.svn` from keep_files |
| 2026-05-15 | Synthesize unique post dates (May 1–12) for correct blog series ordering |
