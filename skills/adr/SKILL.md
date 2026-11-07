---
name: adr
description: >
  Write an Architecture Decision Record: the constraints, alternatives ruled out and trade-offs
  accepted behind a resolved decision. Use when the user asks for an ADR, asks to document a
  decision, or after a design discussion that reached a clear choice. Not for describing the
  current system (use `arch-docs`).
metadata:
  category: preference

---

# ADR

An ADR preserves the reasoning behind a decision across time and team turnover. The code shows
what got built; an ADR shows why this option won, what was ruled out, and which trade-offs were
accepted on purpose.

## When to use

Write an ADR when:

- A non-obvious architectural choice was made (technology, boundary, protocol,
  data model, deployment topology)
- A trade-off was accepted on purpose and a future reader would otherwise
  reverse it without context
- A constraint forced a non-default choice (compliance, performance budget,
  legacy compatibility)
- The conversation surfaced alternatives that were considered and rejected

Skip the ADR when:

- The choice is local and reversible (variable naming, formatter config,
  test layout)
- It's a TODO or aspiration, not a resolved decision
- The "decision" is just following the existing pattern in the codebase
- It's already documented in code comments where the constraint lives

## Process

### Step 1: Detect the repo's ADR convention

First, check for an `.adr-dir` file at the repo root (adr-tools convention) —
it points at the ADR directory. If present, use it.

Otherwise, check in this order for an existing ADR directory:

1. `docs/architecture/adr/`
2. `docs/decisions/` (MADR default)
3. `docs/adr/`
4. `adr/`
5. `doc/adr/`
6. `architecture/decisions/`
7. `decisions/`

If found:

- Read 1–2 existing ADRs to detect the template structure, frontmatter format,
  numbering pattern (`0001`, `ADR-001`, date-based), and slug style
  (`kebab-case`, `snake_case`)
- Look for a `template.md` in the same directory and reuse it verbatim if
  present
- Match the existing convention exactly — consistency beats opinion
- Skip subdirectories named `archived/`, `superseded/`, `examples/`, or
  prefixed `_` when computing the next number; only count files matching the
  detected naming pattern

**Repo convention vs mandatory visualization — precedence:** The repo's
template wins for section names and order. Insert the Mermaid block into the
closest equivalent decision/outcome section (or `Context` for before/after
diagrams). If the repo template explicitly disallows diagrams or has no
sensible place for one, write `No diagram: follows repo ADR template` in
place of the visualization.

If not found:

- Use the opinionated default: create `docs/adr/` and use the MADR-inspired
  fallback template in `references/madr-template.md`
- Numbering: `0001-` zero-padded 4-digit sequential
- Filename: `NNNN-imperative-kebab-case-title.md`

### Step 2: Confirm this is actually a decision

Before writing, verify the input qualifies:

- **Is it resolved?** "We should consider X" is a TODO, not an ADR. Push back
  if the conversation didn't reach a clear conclusion; a decision that was
  never made is worse than no record.
- **Is there a meaningful "why"?** Capture at least one of: an alternative
  considered, a rejected baseline, or a forcing constraint (compliance,
  vendor, migration, safety, compatibility). A "constraint-forced
  non-choice" is one of the most valuable ADR types — explain *why* the
  apparently odd constraint was accepted, even if no realistic alternative
  survived. The status-quo "do nothing" option is a valid alternative if
  applicable.

If the input is unresolved or falls under "Skip the ADR when", tell the user and don't write the ADR. If
alternatives are absent, write the ADR with the constraint that forced the call (and use "Only
viable option because \<constraint>" in Decision Outcome).

### Step 3: Gather inputs

**From the conversation, without re-asking:** the decision, the alternatives discussed and
rejected, the file paths, modules or systems touched, the constraints mentioned (deadlines,
compliance, performance, compatibility), and any tickets, prior ADRs or external docs.

**Ask the user only for what's missing or unclear:**

- A clear imperative title ("Use Postgres for primary store" — not "Database
  decision")
- The final decision wording (the one-line outcome)
- The **negative** consequences and trade-offs — these are usually understated
  in chat and are the most valuable part of the ADR
- Status: usually "Proposed" unless the decision is already shipped, in which
  case "Accepted"

Don't fabricate alternatives that weren't actually considered, and don't invent constraints
that weren't mentioned. If a section would be guesswork, leave it short and honest rather than
padding it.

### Step 4: Add a visualization (default ON)

**Every ADR includes at least one Mermaid diagram by default.** It hands the
future reader the mental model faster than prose. Use the `viz` skill for
technique and templates.

Pick the diagram type from what the decision is *about*:

| Decision is about… | Diagram |
|---|---|
| Service / module boundaries, what calls what | C4 Container (`flowchart` with `subgraph`) |
| Protocol, RPC, async message flow | `sequenceDiagram` |
| Lifecycle, status transitions | `stateDiagram-v2` |
| Data model, relationships | `erDiagram` |
| Control flow, decision logic | `flowchart` |

Place the diagram in **Decision Outcome** (the "after" state). For decisions
that change an existing structure, also put a "before" diagram in **Context**
so the reader sees what changed.

**Skip the diagram only when one of these is genuinely true** (and say so
explicitly in the ADR — write "No diagram: <reason>"):

- The decision is purely textual or policy (e.g. "use UTF-8 everywhere",
  "all timestamps in UTC")
- The decision is a version pin or single-library swap with no structural
  change
- The decision is a deletion of a single component (the diagram would be
  empty)
- The decision is about a single function or data field with no system
  context

When in doubt, draw something small: a 3-node diagram beats no diagram.

### Step 5: Write the ADR

Compute the next number from existing files. Use the imperative title as the
slug. Fill in the repo's template, or the fallback in `references/madr-template.md`.

### Step 6: Report next steps

Print:

- The file path
- The proposed conventional commit message (`docs(adr): add ADR-NNNN <title>`)
- Any candidate index/overview file that might want a link: check
  `docs/architecture/README.md`, `docs/architecture/index.md`,
  `docs/adr/README.md`, `docs/decisions/README.md`, the repo root
  `README.md`, and (if MkDocs) `mkdocs.yml`'s nav. Suggest the most
  specific match, not all of them.

Committing follows the repository's standing authorization, not a rule in
this skill. If the session or the repo's `AGENTS.md` / `CLAUDE.md` already
authorizes committing completed work, commit the ADR with the message above
and say so in the report; otherwise leave the file uncommitted and report the
proposed message. Either way, stage only the ADR and any index file you
touched — never the user's unrelated work in progress.

## MADR-inspired fallback template

`references/madr-template.md` holds the fallback template for repos with no ADR convention — frontmatter, the section skeleton down to Consequences, Confirmation and More Information — and the three deliberate deviations from MADR v3.0 with how to restore strict fidelity. Read it when Step 1 found no repo template. Repo template, numbering and filename rules stay in Step 1; the Rules below apply to either template.

## Rules

- **Lean by default.** Target ~300–400 words of prose, plus one diagram. If
  it's longer, you're documenting the discussion, not the decision. Cut.
- **An ADR is not a conversation dump.** Distill what was decided and why,
  not how the conversation unfolded. No quotes, no chronology, no recap of
  the design discussion. The reader doesn't need the journey, they need
  the destination.
- **Rejected alternatives get a name and one line on why they lost.** Don't
  paste the rejected design.
- **Code is truth.** If the ADR contradicts the source, fix the ADR or
  supersede it — never the other way around. `Accepted` status implies the
  decision is reflected in the current code.
- **Every node and edge in the diagram must be evidenced.** Trace each one
  to a real file, service, or explicit user statement. No invented
  components.
- **One decision per ADR.** If you find yourself writing "and also we
  decided to…" — that's a second ADR.
- **Imperative titles.** "Use X for Y", not "X adoption" or "Decision on Y".
- **The negative consequences section is the most valuable.** A future
  reader asking "why did they do this?" needs to see the trade-offs that
  were accepted on purpose. Don't soften them, and be specific: "may have
  performance implications" is not a consequence — name it or delete the line.
- **Link to code, don't restate it.** Full paths to affected components.
  Don't paste code blocks unless the snippet itself is the decision.
- **No implementation steps.** "Phase 1: do X. Phase 2: do Y." belongs in
  `scope`, not an ADR.
- **Status is a lifecycle, not a label.** `Proposed` → `Accepted` →
  `Deprecated` or `Superseded by ADR-NNNN`. Don't edit Accepted ADRs to
  reverse them — write a new one that supersedes.
- **No AI/co-author trailers in the file or commit.**

## Boundary with other skills

- **`viz`**: the technique for drawing the diagrams every ADR includes by
  default. ADR is the container, viz is the diagrammer.
- **`arch-docs`**: describes the current system. An ADR records one decision
  and its why; link to architecture docs, don't restate the codebase.
- **`scope`**: plans how to implement. **`adr`**: records why this approach
  was chosen over alternatives. Often used together — scope a phase, then
  ADR the architectural choices the scope assumed.
- **`code-review`**: reviews the implementation. ADRs are referenced by
  reviewers when invariants are at stake.
- **`collab`**: multi-agent design discussion. The output of a collab session
  often becomes one or more ADRs.

## Notes on detection edge cases

- If multiple ADR directories exist (rare), prefer the deepest one under
  `docs/` — it's usually the live one.
- If existing ADRs use a non-MADR format (e.g. Nygard's original 4-section
  format), match that format exactly. Don't impose MADR. With ADRs but no
  `template.md`, reproduce the sections of the most recent ADR.
- If the repo has a CONTRIBUTING.md or AGENTS.md with explicit ADR rules,
  follow those over the detection defaults.
