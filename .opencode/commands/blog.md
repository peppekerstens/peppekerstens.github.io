---
description: Draft a new blog post for peppekerstens.github.io (usage: /blog <brief description of what to write about>)
---
Load the `writing-style` skill first, then draft a new blog post for
`peppekerstens.github.io` about: $ARGUMENTS

## Hard requirements (NON-NEGOTIABLE)

The rule `.opencode/rules/blog-creation.md` is auto-loaded for all `_posts/*` files. It contains two hard requirements that MUST be obeyed in every circumstance:

1. **Date synthesis** — every post MUST have a unique date. If multiple posts are created on the same calendar day, synthesize different dates to guarantee correct chronological display.
2. **Tone calibration** — read part-1 through part-12 in `_posts/` before drafting. These twelve posts define the writing style for the entire series.

## Post requirements

- Series: "Linux Command Wrapping" — the next part number is the current count + 1
- Filename: `YYYY-MM-DD-<slug>-linux-command-wrapping-part-N.md` using today's date. If multiple posts are created on the same day, synthesize a date increase (different days) to ensure correct chronological display.
- Frontmatter:
  ```yaml
  ---
  title: <Title — sentence case, no trailing period> — Linux Command Wrapping Part N
  toc: true
  ---
  ```
- Length: 600–1000 words. Dense, not padded.
- Structure: no rigid template — follow the pattern of the existing posts. Start with
  the problem or situation, not an introduction. End with what was learned or what is next.
- Voice rules from writing-style skill apply in full.

## What to produce

1. The complete post content, ready to save.
2. The exact filename to use.
3. A one-line summary of what the post covers (for the commit message).

Do not save the file until the content is reviewed and confirmed. Once confirmed,
save to `_posts/<filename>` and propose a commit message following Conventional Commits.
