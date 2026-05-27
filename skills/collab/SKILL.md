---
name: collab
description: Structured research and collaboration protocol for one or more agents. Use for design sessions, research tasks, or multi-agent collaboration with auditable decisions and a shared plan. Works solo with a second agent joining later.
---

# Structured Research & Collaboration Protocol (V3)

Reusable protocol for structured research, design, and multi-agent collaboration in any repo.

Use this when:
- two agents work on the same topic
- you need auditable decisions and explicit convergence
- you want it to work in both sequential and parallel runs
- you start with one agent and may add a second agent later

Born from real collaboration sessions. V3 adds Live Mode for continuous user-driven sessions, based on retro from the CLI mode design collaboration.

## Two Operating Modes

### Round Mode (batch convergence)

Use when agents work asynchronously or need formal agreement on architecture-level changes.

Flow: draft → review → merge → signoff (same as V2).

### Live Mode (continuous collaboration)

Use when the user is actively driving the session, decisions emerge in conversation, and direction changes frequently.

Flow: research notes → decisions logged immediately → signoff when direction stabilizes.

**When to use which:**
- **Live Mode**: user is present, fast-moving design discussion, decisions made in real-time
- **Round Mode**: offline review, major redesign checkpoint, formal disagreement resolution
- You can switch between modes within a session. A live session can trigger a mini-round when there's real disagreement.

## Workspace Location

All collaboration artifacts live in `.local/.local/collab/{topic}/` within the target repo. This directory is **gitignored** — collaboration artifacts are ephemeral working state, not permanent documentation. Ensure `.local/` is in the repository's `.gitignore` before starting.

The durable output is the code itself (committed) and optionally `PLAN.md` if the team wants to preserve the plan alongside the implementation.

## Quick Start

1. Create workspace in target repo:
   - `.local/.local/collab/{topic}/`
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

If only one agent is active, the protocol still works.

Use the same folder layout with provisional artifacts:

- `rounds/r1/<agent>.md`
- `rounds/r1/<agent>_self_review.md`
- `rounds/r1/merged.md` (marked `Status: PROVISIONAL`)
- `rounds/r1/signoff_<agent>.md` (marked `Status: PROVISIONAL`)

Rules in single-agent mode:

1. Write a numbered draft.
2. Write a self-review that addresses every numbered point critically.
3. Record non-trivial tradeoffs in `DECISIONS.md`.
4. Mark outputs as `PROVISIONAL` until a second agent reviews.

When a second agent joins later:

1. The second agent writes `rounds/r1/<other>.md` and review file.
2. The original agent reviews the new draft.
3. Re-write `merged.md` and both signoffs as final (remove `PROVISIONAL`).
4. Then update `PLAN.md`.

## Isolation

Prefer **git worktrees** for parallel agent work — each agent gets its own working tree, no file conflicts. Merge only after tests pass and signoff is complete. Avoid two agents editing the same branch or working tree simultaneously.

## Templates

### Position template (`<agent>.md`)

```md
# Position
Artifact type: position

## Proposed Decisions

1. ...
2. ...
3. ...

## Open Questions

1. ...
2. ...
```

### Research note template (`<agent>_<topic>.md`)

```md
# <Topic> Analysis (<Agent>)
Artifact type: research-note

## Findings

...

## Implications for Design

...
```

### Review template (`*_review.md`)

```md
# Review
Artifact type: review

Reviewed file: rounds/rN/<other>.md

Observed:
- rounds/rN/<other>.md @ <sha or timestamp>

1) Point 1: agree/disagree + rationale
2) Point 2: agree/disagree + rationale
3) Point 3: agree/disagree + rationale

Open items:
- ...
```

### Signoff template (`signoff_*.md`)

```md
# Signoff
Artifact type: signoff

Observed:
- rounds/rN/merged.md @ <sha or timestamp>

Consistency check:
- [ ] All referenced files exist
- [ ] PLAN.md reflects latest merge
- [ ] DECISIONS.md has no gaps
- [ ] No dangling unresolved items

Coverage:
- Review point 1 -> addressed in section X
- Review point 2 -> dropped via D-003
- Review point 3 -> escalated via D-004

Status: APPROVED
```

## Practical Guidance

- Keep rounds short and concrete.
- Prefer explicit disagreement over vague "looks good" reviews.
- Converge in signoff, not by ad-hoc edits to the other agent's docs.
- In Live Mode, don't force artificial round boundaries. Log decisions as they happen, merge when stable.
- If the user makes a decision, log it to DECISIONS.md immediately — don't wait.

## Anti-Patterns

- Building complex lock infra for human turn-taking.
- Requiring frontmatter/tooling metadata no one actually parses.
- Forcing artificial review quotas instead of addressing actual points.
- Letting both agents edit the same draft/review file.
- Declaring done without explicit signoff coverage.
- Deferring DECISIONS.md updates to "later" or signoff time.
- Maintaining parallel plan documents that drift apart.
- Writing merged.md before the round's scope has settled.
- Working around protocol friction instead of fixing the protocol itself.
