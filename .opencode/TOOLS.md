# Tool & Capability Reference

Quick-reference for all tools and capabilities available in this opencode session. Saves discovery time on new sessions.

---

## Built-in Tools

| Tool | Purpose |
|------|---------|
| `read` | Read file contents or list directories. Supports offset/limit for large files. |
| `glob` | Fast file pattern matching (e.g., `**/*.md`). Returns paths sorted by modification time. |
| `grep` | Regex content search. Supports `include` patterns. Returns file paths and line numbers. |
| `bash` | Execute PowerShell 7+ commands. `git *` is auto-allowed; all other commands require user approval. |
| `webfetch` | Fetch URL content, convert to markdown/text/HTML. |
| `task` | Launch subagents for complex/multi-step work. Use `explore` for codebase search, `general` for research tasks. |
| `todowrite` | Track task progress. Use for complex multi-step work. |
| `edit` / `write` | Modify or create files. |
| `question` | Ask the user for input/decisions. |

## MCP Servers

| Server | Config | Status |
|--------|--------|--------|
| **GitHub** | `.opencode/opencode.json` → `@modelcontextprotocol/server-github` | Read ops work. Write ops fail (needs PAT with `repo` scope). |

**Available GitHub MCP operations:**
- **Read**: `github_list_commits`, `github_list_issues`, `github_list_pull_requests`, `github_get_file_contents`, `github_get_issue`, `github_get_pull_request`, `github_get_pull_request_files`, `github_get_pull_request_status`, `github_get_pull_request_comments`, `github_get_pull_request_reviews`, `github_search_*` (repos/code/issues/users)
- **Write** (auth required): `github_create_or_update_file`, `github_push_files`, `github_create_branch`, `github_create_issue`, `github_update_issue`, `github_add_issue_comment`, `github_create_pull_request`, `github_merge_pull_request`, `github_create_pull_request_review`, `github_create_repository`, `github_fork_repository`

## Browser DevTools

| Browser | Status | Key Capabilities |
|---------|--------|------------------|
| **Firefox** | Available (`firefox-devtools_*`) | Pages, console, network, screenshots, DOM snapshots, clicks, forms, file uploads, navigation, viewport, extensions |
| **Edge** | Available (`edge-devtools_*`) | Pages, console, network, screenshots, JS evaluation, clicks, typing |
| **Chrome** | Available (`chrome-devtools_*`) | Pages, console, network, screenshots, JS evaluation, clicks, forms, file uploads, performance traces, Lighthouse audits, memory snapshots, emulation |

## External CLI Tools

| Tool | Path | Notes |
|------|------|-------|
| `podman` | `C:\Program Files\RedHat\Podman\podman.exe` | **v5.7.0**. Required for ALL Jekyll/Ruby/Bundler ops. No host Ruby installed. |
| `gh` | `C:\Program Files\GitHub CLI\gh.exe` | v2.92.0. GitHub CLI for repo operations. |
| `git` | `C:\Program Files\Git\cmd\git.exe` | Auto-allowed in permission policy. |
| `node`/`npm`/`npx` | `C:\Program Files\nodejs\` | Node.js runtime. npx used by GitHub MCP server. |
| `curl` | `C:\WINDOWS\system32\curl.exe` | HTTP client. |
| `ssh` | `C:\WINDOWS\System32\OpenSSH\ssh.exe` | SSH client. |
| `code` | VS Code CLI | Open files/editor. |

## OPNsense MCP Tools

Full suite of OPNsense firewall management tools available:
- **DNS**: `opnsense_dns_*` — list/add/delete overrides, forwards, blocklists, cache management, diagnostics
- **Firewall**: `opnsense_fw_*` — list/add/update/delete/toggle rules, aliases, apply changes
- **Diagnostics**: `opnsense_diag_*` — ARP, routes, ping, traceroute, DNS lookup, firewall states/logs, system info
- **Interfaces**: `opnsense_if_*` — list, get config, stats, assign, configure
- **DHCP**: `opnsense_dhcp_*` — leases, static mappings, Kea subnets (list/create/update/delete/apply)
- **Services**: `opnsense_svc_*` — list, start/stop/restart
- **ACME**: `opnsense_acme_*` — accounts, challenges, certificates, settings, renewal
- **Firmware**: `opnsense_firmware_*` — info, status, plugins, install/remove
- **Routes**: `opnsense_route_*` — list/add/update/delete/apply, gateway list
- **VLANs**: `opnsense_vlan_*` — list/create/update/delete
- **Tailscale**: `opnsense_tailscale_*` — settings, service control/status
- **System**: `opnsense_sys_*` — info, backups (list/download/revert), certificates

## Mermaid

| Tool | Purpose |
|------|---------|
| `mermaid_generate` | Generate PNG/SVG diagrams from mermaid markdown |

## Opencode Configuration

### Auto-Loaded Rules

| Rule | Match | Purpose |
|------|-------|---------|
| `working-principles.md` | `*` (all files) | Work via opencode; defer to subtasks to overcome looping |
| `blog-creation.md` | `_posts/*` | Unique dates for same-day posts; tone calibration from parts 1-12 |
| `containerized-tooling.md` | `Gemfile*\|Containerfile\|*jekyll*\|*bundle*` | Podman-only for all Ruby/Bundler/Jekyll ops |

### Skills

| Skill | File | When to Load |
|-------|------|--------------|
| `containerized-jekyll` | `.opencode/skills/containerized-jekyll/SKILL.md` | Jekyll build/serve/bundle operations |
| `writing-style` | `.opencode/skills/writing-style/SKILL.md` | Writing commits, PRs, help text, blog content |

### Custom Commands

| Command | File | Usage |
|---------|------|-------|
| `/blog` | `.opencode/commands/blog.md` | `/blog <brief description>` — drafts a new blog post |

### Permission Policy

From `.opencode/opencode.json`:
- `git *` → **allow** (auto-approved)
- `*` → **ask** (requires user approval)

---

## Repo State (as of 2026-05-16)

- **21 posts**: 1 standalone (Windows Sandbox) + 20-part PowerShell Linux Commands series
- **Latest**: Part 20 — "A Second LLM Review" (2026-05-16)
- **Next series part**: Part 21
- **Branch**: `main` (default)
- **Open issues**: 0
- **Open PRs**: 0
- **All plan phases**: Complete (Phase 1-6)

## Containerized Jekyll — Quick Commands

Primary registry: `ghcr.io/ruby/ruby:3.2.1-jammy` (auth at `~/.config/containers/auth.json`)

```bash
# Update Gemfile.lock
podman run --rm --authfile ~/.config/containers/auth.json -v "$PWD:/site:Z" -w /site ghcr.io/ruby/ruby:3.2.1-jammy bash -c "gem install bundler && bundle lock"

# Build site
podman run --rm --authfile ~/.config/containers/auth.json -v "$PWD:/site:Z" -w /site ghcr.io/ruby/ruby:3.2.1-jammy bash -c "gem install bundler && bundle install && bundle exec jekyll build"
```

## Key Constraints

- No Ruby/Bundler installed natively — use podman only
- GitHub MCP write ops need PAT with `repo` scope (currently read-only)
- Every blog post MUST have a unique date
- Read parts 1-12 before drafting new posts (tone calibration)
