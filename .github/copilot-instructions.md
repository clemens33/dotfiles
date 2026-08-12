# Repo context for automated review

Personal dotfiles (WSL + macOS, fish shell, Dotbot symlinks) that also carry the AI tooling
layer: shared agent doctrine (shared/AGENTS.md), per-tool configs (claude/, codex/, opencode/,
antigravity/, grok/), and an agent-skill library (skills/*/SKILL.md).

Standing invariants to check on every PR:

- **No secrets, ever** — no API keys, tokens, or passphrases in any tracked file; `${VAR}`
  placeholders + `~/.config/<service>/credentials.env` is the only pattern. Flag anything that
  looks like a real credential, including in shell history-style strings or MCP configs.
- **Skills**: structural rules are enforced by `scripts/lint-skills.sh` in CI — do not re-check
  structure. Semantic review guidance for skill changes: `.github/instructions/skills.instructions.md`.
- **Workflows**: actions pinned to full commit SHAs, least-privilege `permissions:`,
  `persist-credentials: false` on checkouts.
- **Commit hygiene**: no AI-tool attribution in commit messages or metadata.
- Keep findings scoped to the diff; BLOCKER/IMPORTANT/NIT severity; "No findings" explicitly
  when clean.
