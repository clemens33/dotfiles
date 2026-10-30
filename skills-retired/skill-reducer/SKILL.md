---
name: skill-reducer
description: >
  Audit and compress an existing skill file using progressive disclosure.
  Split essential rules from supplementary reference material so the main
  SKILL.md loads cheaply while exhaustive examples and tables stay accessible
  on demand. Use when reviewing existing skills, when subagent spawn cost
  feels expensive, or before adding new heavy skills. Not for creating,
  updating, or relocating skills — use manage-skills for lifecycle work.
  Based on SkillReducer (arXiv:2603.29919).
source: based on https://arxiv.org/abs/2603.29919v2
metadata:
  category: capability

---

# Skill Reducer

Audit a skill file. Identify what's essential vs supplementary. Restructure via progressive disclosure to cut per-load token cost without losing functionality.

## Why this matters

Heavy skills cost tokens **every time they load**. The cost compounds where loading is eager:

- Subagent spawns that preload via `skills:` frontmatter (full content injected at startup)
- Skill-triggered invocations in long sessions
- Multiple agents in agent-team workflows each preloading the same skills

The SkillReducer preprint surveyed 55,315 published skills and reported:

| Reported on the paper's corpus | Value |
|---|---|
| Skills lacking a usable routing description | 26.4% |
| Body content classified non-actionable | >60% |
| Body compression achieved, at 0.965 retention | ~39% |

Those are **external measurements on someone else's corpus**. They are a reason to try
progressive disclosure here; they are not a target, and not a gain you may promise before
measuring. Quote your own before/after numbers as the result.

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

### 4. Verify retention with before/after cases

Reading the new `SKILL.md` cold is a smoke test, not evidence. Before splitting, write down 3-5
concrete cases the skill must still handle, taken from what it is actually used for. Cover both
kinds of retention:

- **Critical behavior** — a task whose decision or output must be unchanged from `SKILL.md`
  alone, with nothing loaded. Pick the ones where being wrong is expensive.
- **Reference retrieval** — a task that needs relocated content, testing whether `SKILL.md`
  still names the file that now holds it. A split that hides its own references is a regression
  even when every rule survived.

Run each case against the original and against the split, and record it:

| Case | Before | After | Verdict |
|---|---|---|---|
| <task> | <what it produced> | <what it produced> | same / degraded / improved |

A degraded case means content moved that should have stayed — move it back rather than
compensating with a longer pointer. Report the cases alongside the measured line/token delta: a
compression number without retention cases is not a result.

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

## Choosing what to compress

Do not work from a static ranking — line counts drift, skills get split, and a list written six
months ago names skills that no longer exist. Pick by **observed load cost weighed against task
importance**:

1. **How often does it load, and how?** Eager preload costs on every spawn; a manual-only skill
   costs once when invoked. Find out what actually pulls it in rather than assuming:
   `grep -rl '<skill-name>' ~/.claude/agents/ ~/.claude/skills/`.
2. **What does one load cost?** Measure it: `wc -lc skills/<name>/SKILL.md`, and read the
   linter's own gate-4 numbers (`body is N lines`, `~T est. tokens`).
3. **How much of that is non-actionable on a typical run?** Bucket the body with the table
   above. A body that is mostly reference tables is a candidate; one that is mostly rules is not.
4. **How much does the task matter?** A rarely-loaded skill that is load-bearing when it fires
   deserves less compression risk than a hot skill nothing depends on precisely.

Rank by loads-per-session × tokens-per-load × non-actionable share, then sanity-check against
step 4. The skills currently carrying gate-4 waivers in `./scripts/lint-skills.waivers` are the
standing backlog: a waiver is an IOU for this skill, not a permanent exemption.

Skills under ~100 lines are not candidates at any load rate — audit overhead exceeds savings.

## Source

"SkillReducer: Optimizing LLM Agent Skills for Token Efficiency", arXiv:2603.29919v2 (revised
2026-06-24). It is a preprint, not an Anthropic publication — do not cite it as vendor
guidance, and re-check the current version before quoting a figure, since v2 already revised
v1. It contributes the progressive-disclosure architecture and the corpus measurements quoted
above. No reference implementation was released; this skill applies the principles by hand.
