---
name: collab
description: >
  Run a structured, auditable research or design collaboration between agents: positions,
  reviews, merge and signoff files, a decision log and one authoritative plan. Use when two
  agents must converge on a design, when research needs auditable decisions, or when a solo run
  may gain a second agent later; works in batch rounds or live with the user. Not for reviewing
  a diff (use `code-review`).
metadata:
  category: preference

---

# Structured Research & Collaboration Protocol

Reusable protocol for structured research, design, and multi-agent collaboration in any repo. It
works in sequential and parallel runs, and with one agent when a second may join later.

## Two Operating Modes

**Round Mode (batch convergence).** Use when agents work asynchronously or need formal agreement
on architecture-level changes. Flow: draft → review → merge → signoff.

**Live Mode (continuous collaboration).** Use when the user is actively driving the session,
decisions emerge in conversation, and direction changes frequently. Flow: research notes →
decisions logged immediately → signoff when direction stabilizes. Don't force artificial round
boundaries.

You can switch between modes within a session. A live session can trigger a mini-round when
there's real disagreement.

## Workspace Location

All collaboration artifacts live in `.local/collab/{topic}/` within the target repo. This directory is **gitignored** — collaboration artifacts are ephemeral working state, not permanent documentation. Ensure `.local/` is in the repository's `.gitignore` before starting.

The durable output is the code itself (committed) and optionally `PLAN.md` if the team wants to preserve the plan alongside the implementation.

## Quick Start

1. Create workspace in target repo:
   - `.local/collab/{topic}/`
2. Create `SESSION.md` (human-owned):
   - Goal, scope, deliverable, agents, merge owner, operating mode.
3. Create `DECISIONS.md` (append-only) and `rounds/r1/`.
4. Follow the flow for your operating mode (see below).

### Round Mode Flow

1. Each agent writes its own draft (`codex.md` / `claude.md`).
2. Each agent reviews the other draft (`*_review.md`), addressing every numbered point.
3. Merge owner writes `merged.md` after both reviews exist.
4. Both agents sign off (`signoff_*.md`) with explicit coverage mapping.
5. Update `PLAN.md` from accepted `merged.md`.

### Live Mode Flow

1. Agents write research notes as needed (`<agent>_<topic>.md`).
2. Decisions are logged to `DECISIONS.md` immediately when made (see Decision Capture SLA).
3. When direction stabilizes, merge owner writes `merged.md` summarizing the agreed state.
4. Both agents sign off.
5. Update `PLAN.md` from accepted `merged.md`.

## Artifact Taxonomy

Every file in a round must declare its type at the top:

| Type | Purpose | Naming |
|------|---------|--------|
| `position` | Agent's stance/draft on the topic | `<agent>.md` |
| `review` | Review of another agent's position | `<agent>_review.md` |
| `research-note` | Mid-round analysis that isn't a position or review | `<agent>_<topic>.md` |
| `merge` | Converged direction (merge owner only) | `merged.md` |
| `signoff` | Explicit approval with coverage mapping | `signoff_<agent>.md` |

Research notes are first-class artifacts. They feed into the eventual merge but don't require the formal review cycle. Use them for: analysis of code, exploration of options, responses to user questions, bootstrap/import mapping, etc.

## Target Structure

```text
.local/collab/{topic}/
  SESSION.md          # human-owned, read-only for agents
  DECISIONS.md        # append-only, shared
  PLAN.md             # authoritative implementation plan
  ARCHITECTURE.md     # optional: diagrams, component maps
  rounds/
    r1/
      codex.md                  # position
      claude.md                 # position
      codex_review.md           # review
      claude_review.md          # review
      codex_<topic>.md          # research-note (zero or more)
      claude_<topic>.md         # research-note (zero or more)
      merged.md                 # merge
      signoff_codex.md          # signoff
      signoff_claude.md         # signoff
```

## Roles and Ownership

- Human/coordinator writes `SESSION.md` and keeps it read-only for agents.
- Each agent edits only its own position/review/signoff/research-note files.
- Merge owner (set in `SESSION.md`) is the only writer of `merged.md`.
- Shared editable files: `DECISIONS.md`, `PLAN.md`.

## Rules

1. Never edit another agent's files.
2. Reviews must address every numbered point from the other draft.
3. No `merged.md` until both reviews exist (Round Mode) or direction has stabilized (Live Mode).
4. Signoff must map each review point to outcome (`addressed`, `dropped via D-xxx`, `escalated`).
5. Disagreements go to `DECISIONS.md`; unresolved items are `ESCALATE`.
6. New round only for substantial redesign; minor issues stay in current round.
7. **Decision Capture SLA**: any non-trivial decision must be written to `DECISIONS.md` within the same interaction cycle it was made. Do not defer to signoff.
8. **User decrees override agent consensus** without requiring a review cycle. Log immediately with `owner: user`.

## Decision Log

Use `DECISIONS.md` as append-only table:

```text
id | topic | option_a | option_b | decision | rationale | owner | timestamp
```

- Never silently rewrite prior decisions; add a new row that supersedes an older one.
- Valid owners: `<agent>`, `user`, `consensus` (both agents agreed), `<agent>:lead` (merge owner decided).
- User decrees: log immediately when the user makes a decision. These can only be superseded by a new explicit user decree, not by agent consensus.

## Single Source of Truth

`PLAN.md` is the **authoritative** implementation plan. There must be no parallel "active plan" documents.

- If the tool has its own plan mechanism (e.g., Claude Code plan files), `PLAN.md` is canonical. The tool's plan file should reference or be generated from `PLAN.md`.
- `merged.md` is design rationale and convergence record. `PLAN.md` is the actionable output.
- After signoff, `PLAN.md` must reflect the latest accepted direction.

## Completion Gate

Collaboration is complete only when all are true:
- Both signoffs exist for the latest round
- `PLAN.md` reflects the latest accepted merged direction
- `DECISIONS.md` contains all decisions as decided or escalated
- Consistency check passes (see below)

### Consistency Check (before signoff)

Before signing off, verify:
1. All files referenced in `Observed:` blocks exist
2. `PLAN.md` reflects the latest accepted merge
3. `DECISIONS.md` has no gaps (all decisions made during the round are logged)
4. No unresolved items remain without `ESCALATE` status

Single-agent exception:
- A single-agent run may end as `PROVISIONAL COMPLETE` with one signoff.
- It becomes fully complete only after second-agent review/signoff or explicit human waiver.

## Freshness and Observed Blocks

In each review/signoff include an `Observed:` block with timestamps or git SHAs:

```md
Observed:
- rounds/r1/codex.md @ git abc123
- rounds/r1/claude.md @ 2026-02-23T14:30Z
```

- Prefer timestamps over git SHAs in fast-moving working trees where files aren't committed yet.
- If observed references are stale, refresh before signoff.
- If a referenced file was renamed or removed, note it explicitly.

## Merge Revisions

Minor fixes to `merged.md` (typos, formatting) can be updated in place. If the substance changes significantly, start a new round rather than silently rewriting the merge.

## Single-Agent Bootstrap Mode

If only one agent is active, the protocol still works with provisional artifacts in the same
layout:

- `rounds/r1/<agent>.md` (a numbered draft)
- `rounds/r1/<agent>_self_review.md` (addresses every numbered point critically)
- `rounds/r1/merged.md` and `rounds/r1/signoff_<agent>.md`, both marked `Status: PROVISIONAL`

Record non-trivial tradeoffs in `DECISIONS.md`. When a second agent joins later:

1. The second agent writes `rounds/r1/<other>.md` and review file.
2. The original agent reviews the new draft.
3. Re-write `merged.md` and both signoffs as final (remove `PROVISIONAL`).
4. Then update `PLAN.md`.

## Inside an ae session — adapt, don't duplicate

This protocol is standalone by default and stays fully usable with no ae session. Inside one,
ae already owns the session state, and a second copy of it is the failure mode: two plans, two
decision logs, two owners, and nobody sure which is current.

Map onto what the session already has rather than recreating it:

| Collab artifact | Inside an ae session |
|---|---|
| `SESSION.md` (goal, agents, merge owner) | The session goal and the roster in `workspace.md` — read them, don't restate them |
| `DECISIONS.md` | `memo add --topic decision` is the durable record; keep `DECISIONS.md` only if the session's leads agree it is the one log, and then nobody duplicates rows into memo |
| `PLAN.md` | The session's existing plan document. One plan, one path, named once. If a plan already exists, collab writes into it — it does not open a rival |
| Merge owner | The lead or colead seat that already owns the gate. Do not appoint a second one |
| Per-agent positions, reviews, research notes | Unchanged — these stay per-agent files and are where collab still earns its keep |

Two rules survive the mapping intact:

1. **One writer per shared artifact.** The merge owner is the only writer of `merged.md` and of
   the plan. Everyone else writes their own evidence files and sends findings to the owner.
2. **Provider diversity still applies.** A collab round between two seats on the same provider
   is depth, not a review gate — see `cross-model-review`.

## Isolation

Prefer **git worktrees** for parallel agent work — each agent gets its own working tree, no file conflicts. Merge only after tests pass and signoff is complete. Avoid two agents editing the same branch or working tree simultaneously.

## Templates (read on demand)

`references/templates.md` holds the position, research-note, review and signoff templates (`<agent>.md`, `<agent>_<topic>.md`, `*_review.md`, `signoff_*.md`) with their `Observed:` blocks, review-point numbering and signoff coverage checklist. Read it when writing or reviewing a round artifact; the Artifact Taxonomy, Rules and Completion Gate above are enough to run the protocol without it.

## Practical Guidance

- Keep rounds short and concrete.
- Prefer explicit disagreement over vague "looks good" reviews.
- Don't build complex lock infrastructure for human turn-taking.
- Don't require frontmatter or tooling metadata no one actually parses.
- Don't force artificial review quotas instead of addressing actual points.
- Fix protocol friction in the protocol itself instead of working around it.
