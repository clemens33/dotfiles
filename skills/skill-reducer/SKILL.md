---
name: skill-reducer
description: >
  Audit and compress an existing skill file using progressive disclosure.
  Split essential rules from supplementary reference material so the main
  SKILL.md loads cheaply while exhaustive examples and tables stay accessible
  on demand. Use when reviewing existing skills, when subagent spawn cost
  feels expensive, or before adding new heavy skills. Based on SkillReducer
  (arXiv:2603.29919).
source: based on https://arxiv.org/abs/2603.29919
---

# Skill Reducer

Audit a skill file. Identify what's essential vs supplementary. Restructure via progressive disclosure to cut per-load token cost without losing functionality.

## Why this matters

Heavy skills cost tokens **every time they load**. The cost compounds where loading is eager:

- Subagent spawns that preload via `skills:` frontmatter (full content injected at startup)
- Skill-triggered invocations in long sessions
- Multiple agents in agent-team workflows each preloading the same skills

Per the SkillReducer paper survey of 55,315 skills:

- 26.4% lack proper routing descriptions
- **>60% of body content is non-actionable**
- Target on real skills: ~**39% body compression with 0.965 retention**

## When NOT to use this

- Skills under ~100 lines — already tight, audit overhead exceeds savings
- Skills loaded rarely and only manually — preload cost doesn't compound
- Skills where supplementary content IS the value (reference tables that callers need every time)

## Method

### 1. Categorize content

Read the target `SKILL.md`. Bucket every section into:

| Category | Example | Disposition |
|----------|---------|-------------|
| **Routing** | YAML frontmatter `description:` | Stay in `SKILL.md`, audit for clarity |
| **Essential rules** | Operating principles, safety rules, output format | Stay in `SKILL.md` |
| **One canonical example** | Best example per pattern type | Stay in `SKILL.md` |
| **Reference tables** | Custom field IDs, endpoint catalogs, error code dictionaries | Extract to `reference/` |
| **Exhaustive examples** | All the JQL patterns, every endpoint variant | Extract to `reference/` |
| **Troubleshooting** | Long failure-mode walkthroughs | Extract to `reference/` |
| **Setup / install** | One-time prerequisites the agent doesn't re-do | Extract to `reference/` |

### 2. Propose the split

Output a plan showing:
- Sections moving to `skills/<name>/reference/<topic>.md`
- What stays in `SKILL.md`
- Estimated line/token delta
- A pointer block to add to `SKILL.md` so the agent can find the references

### 3. Apply on confirmation

Implement the split. Keep:

- YAML frontmatter **exactly** as-is (do not rewrite the description while compressing)
- All content — never delete, only relocate
- File markers in `SKILL.md` so the agent can find supplementary material:
  ```
  ## Reference
  See `reference/jql-patterns.md` for exhaustive JQL examples.
  See `reference/custom-fields.md` for the full custom field table.
  ```

### 4. Verify

After the split, the agent should still be able to do everything the original skill enabled. Spot-check by reading the new `SKILL.md` cold and asking: "could a fresh session use this skill correctly without loading the references?" If yes, ship. If no, move content back.

## Output format

```
## Audit: skills/<name>/SKILL.md

Original: <N> lines (~<T> tokens)
Proposed: <N'> lines (~<T'> tokens) — <reduction>%

### Stay in SKILL.md
- <section name> — <reason>
...

### Move to reference/
- <section name> → reference/<file>.md — <reason>
...

### Pointer block to add to SKILL.md
<exact markdown to add>
```

Then ask for confirmation before applying.

## Anti-patterns

- **Compressing the YAML frontmatter description**. That's the routing key — agents match on it. Touch only with explicit user approval.
- **Deleting content** instead of relocating. SkillReducer is restructuring, not pruning. If something is genuinely dead, that's a separate cleanup task.
- **Splitting into too many reference files.** Aim for 1-3 reference files per skill, grouped by callable purpose. Twenty tiny files defeats progressive disclosure.
- **Ignoring the routing-description audit**. The paper found 26.4% of skills lack proper descriptions. While you're auditing the body, also check the frontmatter `description:` is concrete and trigger-worthy.
- **Compressing skills that aren't loaded heavily.** Audit overhead exceeds savings on rarely-loaded skills.

## Candidates in this repo (heuristic)

Skills most likely to benefit (by line count and load pattern):

- `jira` — ~258 lines, preloaded by `jira-agent` on every spawn
- `grafana-explore` — ~311 lines, preloaded by `grafana-agent` on every spawn
- `m365-graph` — heavy reference content typical of API skills
- `mcp-server` — long enough to plausibly benefit

Skills that probably don't:

- `caveman` — ~70 lines, already tight
- `humanizer` — focused, single-purpose
- `simplify` — small
- `viz` — small

## Source

Anthropic / academic survey: arXiv:2603.29919 — "SkillReducer: Optimizing LLM Agent Skills for Token Efficiency". The paper provides the 39% compression / 0.965 retention numbers and the progressive-disclosure architectural pattern. No reference implementation released; this skill applies the principles manually.
