---
name: manage-skills
description: Create, update, and manage Claude Code skills across the public dotfiles repo and the optional private overlay. Use when the user wants to save a workflow as a skill or update existing skills.
---

# Manage Skills

Create, update, and manage Claude Code skills (slash commands) across the two-layer dotfiles setup.

## Two-layer model

AI coding tool configs live in two repos:

- **Public layer** — `~/projects/clemens33/dotfiles/`
  - Remote: `git@github.com:clemens33/dotfiles.git`
  - Generic, shareable skills (planning, refactoring, security review, doctrine, etc.)
- **Private overlay** (optional submodule) — `~/projects/clemens33/dotfiles/dotfiles-mic/`
  - Remote: `git@github.com:clemens33/dotfiles-mic.git`
  - Org-specific skills + agents (jira, grafana, internal infra, credentials patterns)
  - Only fetched on machines with auth to the private repo

Both layers contribute skill symlinks into `~/.claude/skills/` (real directory, NOT a directory symlink — each skill is its own symlink). The wrapper `./install` script runs the public layer's Dotbot pass, then optionally runs the private overlay's Dotbot pass if the submodule is present.

## Decide which layer

| Skill characteristic | Layer |
|---|---|
| Generic engineering practice (TDD, refactoring, code review, scope, doctrine-shaped) | Public |
| References internal URLs, hostnames, project keys, or customer/product names | Private |
| Wraps an internal API or credential pattern | Private |
| Uses only standard tooling (git, ripgrep, generic CLI) | Public |
| Domain knowledge tied to a specific company/customer | Private |

When in doubt: start public. Move to private only if leak-checking surfaces internal content.

## Creating a new public skill

```bash
cd ~/projects/clemens33/dotfiles
mkdir -p skills/<skill-name>
$EDITOR skills/<skill-name>/SKILL.md
```

Add YAML frontmatter at the top:

```yaml
---
name: <skill-name>
description: What this skill does and when to use it.
---
```

**Add a symlink entry in the public `install.conf.yaml`** for both Claude Code (`~/.claude/skills/<skill-name>: skills/<skill-name>`) and Codex (`~/.codex/skills/<skill-name>: skills/<skill-name>`).

Re-run install to pick up the new symlinks:

```bash
./install
```

Commit + push:

```bash
git add skills/<skill-name>/SKILL.md install.conf.yaml
git commit -m "add <skill-name> skill"
git push
```

## Creating a new private skill

```bash
cd ~/projects/clemens33/dotfiles/dotfiles-mic
mkdir -p skills/<skill-name>
$EDITOR skills/<skill-name>/SKILL.md
```

Same frontmatter as above. Add symlink entries in the **private overlay** `install.conf.yaml`. Re-run install from the public root:

```bash
cd ~/projects/clemens33/dotfiles
./install
```

Commit + push in the private repo first, then update the public submodule pointer:

```bash
cd dotfiles-mic
git add skills/<skill-name>/SKILL.md install.conf.yaml
git commit -m "add <skill-name> skill"
git push
cd ..
git add dotfiles-mic
git commit -m "submodule: bump dotfiles-mic"
git push
```

## Skill file format

```markdown
---
name: my-skill
description: What this skill does and when Claude should use it.
---

# Skill Title

One-line description of what this skill does.

## Configuration

API URLs, env vars, credentials paths, etc. Private skills reference
`~/.config/<service>/credentials.env` and `$ENV_VAR` placeholders — never
inline secrets.

## Workflow

Step-by-step instructions with commands, API calls, code patterns.

## Examples

Concrete examples of common operations.

## Philosophy / Important Notes

Guiding principles for decision-making within this skill.
```

**Keep skills focused.** One skill = one domain. If a skill grows too broad, split it.

**Include runnable commands.** Claude will use these directly — make them copy-paste ready with placeholders clearly marked.

**Include decision guidance.** Tell Claude when to take which action (e.g. "suppress if X, fix if Y").

## Updating an existing skill

Edit `SKILL.md` directly in whichever layer owns it. Re-run `./install` only if you added or removed a skill (symlinks change); pure edits within a skill take effect immediately because the file is symlinked.

Commit and push in the layer that owns the skill. If you edit a private skill, also update the public submodule pointer (see private-skill workflow above).

## Listing installed skills

```bash
ls -la ~/.claude/skills/   # all installed skills (both layers merge here)
ls -la ~/.codex/skills/    # codex curated subset
```

## When to create a skill

Create a skill when you discover a **repeatable workflow** during a session:

- API interactions with specific services (URLs, auth, endpoints)
- Deployment procedures with specific commands and checks
- Troubleshooting runbooks with diagnostic steps
- Tool-specific triage/review workflows
- Doctrine-shaped guidance that repeats across projects

Don't create a skill for one-off tasks or things already well-documented elsewhere.

## Promoting a private skill to public

Audit the skill for internal content:

```bash
rg -ni 'mic|miccust|jira\.|grafana\.|kcml|MICPD|MICAZ|internal.*url|company.*name' skills/<skill-name>/
```

Sanitize references → generic examples. Then `git mv` the directory from private overlay to public layer, update symlink entries in both `install.conf.yaml` files (add public, remove private), re-run install.
