---
name: manage-skills
description: Create, update, and manage Claude Code skills across the public dotfiles repo and the optional private overlay. Use when the user wants to save a workflow as a skill, update existing skills, or promote a private skill to public. Not for shrinking an oversized skill body — use skill-reducer for compression.
metadata:
  category: preference

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

Start from the canonical template below — it is the only skill template in this repo, and it
is written to pass `lint-skills.sh` on the first run.

**Add a symlink entry in the public `install.conf.yaml`** for both Claude Code (`~/.claude/skills/<skill-name>: skills/<skill-name>`) and Codex (`~/.agents/skills/<skill-name>: skills/<skill-name>`). Codex user-scope skills live in `~/.agents/skills`; `~/.codex/skills` is legacy and holds Codex's own `.system` set.

Re-run install to pick up the new symlinks:

```bash
./install
```

Commit + push:

```bash
git add -- skills/<skill-name>/ install.conf.yaml
git commit -m "add <skill-name> skill"
git push
```

Stage the **skill directory**, not just `SKILL.md`: any `references/`, `scripts/` or `assets/`
you created alongside it would otherwise stay untracked, and the skill would land broken for
everyone else. Never `git add -A` — other lanes' work is in this checkout too.

## Creating a new private skill

```bash
cd ~/projects/clemens33/dotfiles/dotfiles-mic
mkdir -p skills/<skill-name>
$EDITOR skills/<skill-name>/SKILL.md
```

Same template as above. Add symlink entries in the **private overlay** `install.conf.yaml`. Re-run install from the public root:

```bash
cd ~/projects/clemens33/dotfiles
./install
```

Commit + push in the private repo first, then update the public submodule pointer:

```bash
cd dotfiles-mic
git add -- skills/<skill-name>/ install.conf.yaml
git commit -m "add <skill-name> skill"
git push
cd ..
git add dotfiles-mic
git commit -m "submodule: bump dotfiles-mic"
git push
```

## Canonical skill template

One template, both layers. Copy it verbatim and fill it in:

```markdown
---
name: my-skill
description: >
  What this skill does, front-loaded in the first clause. Use when <the
  concrete triggers — what the user says, or the situation that calls for it>.
  Not for <the nearest adjacent skill's job> — use `that-skill` instead.
metadata:
  category: capability

---

# Skill Title

One line on what this skill does.

## Configuration

API URLs, env vars, credentials paths. Private skills reference
`~/.config/<service>/credentials.env` and `$ENV_VAR` placeholders — never
inline secrets.

## Workflow

Step-by-step instructions with commands, API calls, code patterns.

## Examples

Concrete examples of common operations.

## Philosophy / Important Notes

Guiding principles for decision-making within this skill.
```

The frontmatter fields the linter enforces, and why each one is not optional:

| Field | Rule | Gate |
|---|---|---|
| `name` | Must equal the directory name; lowercase alphanumerics and single hyphens, 1-64 chars | gate 1 |
| `description` | Required, at most 500 chars, no embedded newlines (use folded `>`, not literal `\|`) | gates 1-2 |
| `description` | Must contain the exact-case substring `Use when` — house grammar, checked literally | gate 3 |
| `metadata.category` | Must be exactly `capability` or `preference` | gate 7 |

`capability` vs `preference` is an ablation test, not a topic label: if removing the skill
would make a task *impossible*, it is a `capability`; if the task would still get done but in a
way the user does not want, it is a `preference`.

Body limits: 500 lines and ~5000 estimated tokens (gate 4). Over either, do not add a waiver —
run `skill-reducer` and split the reference material out.

**Keep skills focused.** One skill = one domain. If a skill grows too broad, split it.

**Include runnable commands.** Claude will use these directly — make them copy-paste ready with placeholders clearly marked.

**Include decision guidance.** Tell Claude when to take which action (e.g. "suppress if X, fix if Y").

## Updating an existing skill

Edit `SKILL.md` directly in whichever layer owns it. Re-run `./install` only if you added or removed a skill (symlinks change); pure edits within a skill take effect immediately because the file is symlinked.

Commit and push in the layer that owns the skill. If you edit a private skill, also update the public submodule pointer (see private-skill workflow above).

## Listing installed skills

```bash
ls -la ~/.claude/skills/    # all installed skills (both layers merge here)
ls -la ~/.agents/skills/    # the same set, linked for Codex
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

## Reviewing a skill (two tiers)

**Deterministic** (structure — always, CI enforces the same): `./scripts/lint-skills.sh skills/ dotfiles-mic/skills/`

**Semantic** (judgment — routing quality, collisions, filler, drift): the canonical checklist
lives in `.github/instructions/skills.instructions.md`. GitHub Copilot applies it automatically
on PRs touching `skills/**` (via `copilot-review.yml`).

To run it locally, route through `cross-model-review` — do not shell out to another CLI
yourself. Inside an ae session that means an agent on a different provider than the one that
wrote the skill:

```bash
/Users/ckriech/.ae/sessions/<session>/review <reviewer-agent> \
  "Apply .github/instructions/skills.instructions.md to <names or git diff scope>. \
   BLOCKER/IMPORTANT/NIT. State 'No findings' if clean."
```

Outside ae, use the CLI forms in `cross-model-review`. Either way the reviewer's provider must
differ from the author's, and the verdict records which provider ran it.

One instruction file, every consumer — edit it there, never fork the checklist.

## Lifecycle order

Skill edits are shared agent behavior, so they hit the mandatory cross-model gate. Run it in
this order:

1. **Lint** — `./scripts/lint-skills.sh skills/ dotfiles-mic/skills/` plus
   `./scripts/lint-skills-test.sh` if you touched the linter. Green before anyone reviews.
2. **Cross-provider review** — the semantic checklist above, through `cross-model-review`.
   Apply BLOCKER, apply IMPORTANT unless you can say why not, and send the fixes back to the
   same reviewer.
3. **Install** — `./install` only when symlinks changed (a new or removed skill). Pure edits
   to an existing `SKILL.md` take effect immediately through the existing symlink.
4. **Commit and push** — following the session's standing authorization, in the layer that owns
   the skill; private first, then the public gitlink bump. Stage the whole skill directory plus
   the `install.conf.yaml` you touched (`git add -- skills/<name>/ install.conf.yaml`) and
   nothing else. Never `git add -A`.
