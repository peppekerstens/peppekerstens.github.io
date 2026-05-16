---
match: "*"
---

# Working Principles — Hard Requirements

These two rules are NON-NEGOTIABLE. They MUST be obeyed in every circumstance.

## 1. Work via opencode

All work in this repo is done through opencode. Use the tools, skills, rules, and commands defined in `.opencode/`. Do not bypass the configured workflow.

## 2. Defer to subtasks to overcome looping

When a task risks becoming circular or repetitive, immediately delegate it to a subagent (`task` tool). Specify the exact work to be done and the information to return back. Do not spin in place — offload and continue.
