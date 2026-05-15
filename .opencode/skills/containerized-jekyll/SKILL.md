---
name: containerized-jekyll
description: Use ONLY when performing Jekyll operations (build, serve, bundle) on this repo.
---

# Containerized Jekyll Workflow

All Ruby/Bundler/Jekyll operations in this repo MUST run via **podman**.
Never install Ruby or gems directly on the host.

Exact copy-paste recipes (with auth setup, registry order, fallbacks) live in:
**`.opencode/rules/containerized-tooling.md`** — auto-loaded by opencode whenever Gemfile/Bundler/Jekyll files are touched.
