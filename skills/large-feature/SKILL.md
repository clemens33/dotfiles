---
name: large-feature
description: >
  Full-rigor 7-stage playbook for high-rigor large features in this repo —
  multi-slice features where blast radius is real, the design isn't trivial,
  or the deliverable needs to be defensible long after the work ships. Use
  when invoked explicitly ("use the large-feature playbook" / "/large-feature"),
  when starting multi-day or multi-slice feature work that warrants planning
  + cross-model review + per-phase test gates, or when WORKFLOW.md's lean L
  bucket (plan + phased execution) isn't enough rigor. Stages: grill the
  idea, plan + cross-model critique, vertical tracer-bullet slice
  decomposition, per-slice red-green-refactor with phase isolation,
  trigger-based drift checks, integrated review + ADR if needed, separate
  architecture refactor cadence. Skip for S/M work, routine L work that
  doesn't need the full ceremony, and bug-shaped tasks (use diagnose
  instead).
---

# Large Feature Full-Rigor Playbook

Opinionated 7-stage shape for **high-rigor** L-bucket features — multi-slice
features where blast radius is real, the design isn't trivial, or the
deliverable needs to be defensible long after the work ships.

## Relationship to other docs

- **`WORKFLOW.md`** keeps L's *mandatory* shape minimal: written plan + phased
  execution. That doesn't change.
- **This playbook** is an *optional* full-rigor path for L features where the
  baseline two-mandate shape isn't enough.
- Reach for it when: blast radius high, multi-slice work, regulatory or
  audit-relevant change, work spans sessions, or you'd be uncomfortable
  shipping without an audit trail of *why*.
- Skip it when: a `scope`-style plan + per-phase tests is sufficient and
  you're not bottlenecked on uncertainty or review bandwidth.

## Source-tier legend

Each stage is labeled by how well-supported it is in May 2026 SOTA:

- 🅐 **documented practitioner pattern** — explicit in named SOTA sources
- 🅛 **local repo doctrine** — formalized in `shared/AGENTS.md` / `WORKFLOW.md` / `KNOWLEDGE.md`
- 🅡 **research-backed adjacent** — academic or vendor research supports the *concept*; specific shape is interpretation
- 🅔 **experimental synthesis** — extrapolation from neighboring patterns, not yet documented

---

## Stage 0 — Sharpen via `grill-with-docs` 🅐 🅛

**Gate:** Run if domain language uncertainty or prior-decision ambiguity is high. Skip if the request is unambiguous and the project's `CONTEXT.md` / ADRs already settle the relevant terms.

Use the `grill-with-docs` skill against `CONTEXT.md`, `docs/adr/`, and existing skills in the area. Output is **sharpened understanding**, not yet a plan. If you can already write a clean one-sentence "done" definition (M↔L bright-line test from `WORKFLOW.md`), this stage probably isn't needed — drop to M.

**For greenfield features without a spec yet:** add a pre-stage using `to-prd` to write the spec, then grill against it. This repo's vendored Matt-Pocock pipeline is `to-prd` → `scope` → `to-issues`. (Upstream Matt-Pocock also offers `prd-to-plan` / `plan-from-prd` for finer-grained planning steps; those are not vendored here.)

## Stage 1 — Plan + cross-model plan critique 🅐 🅛

**Gate:** Always for L features under this playbook.

### Stage 1 preflight — discover and run the validation harness 🅐

Before `scope`, before any planning: **run the repo's existing test/lint/typecheck commands.** This is Willison's first-do-no-harm pattern — it teaches the agent the validation harness, surfaces broken baseline state, and puts the agent into testing mode before any change.

- If commands are unknown, discover them: read `package.json`, `pyproject.toml`, `justfile`, `Makefile`, `.github/workflows/`, the project's `CLAUDE.md` / `AGENTS.md`
- Record the discovered validation commands in `.local/plan.md` so every subsequent slice's acceptance contract can reference them
- If existing tests fail on a clean checkout, **stop and declare the verification gap explicitly** before adding new work (per `WORKFLOW.md` universal principle #1)

### Stage 1 plan

1. Use the `scope` skill → `.local/plan.md` with phased plan, test gates per phase, and acceptance criteria. Include the validation commands discovered in preflight.
2. **Cross-model plan critique** per `WORKFLOW.md` cross-model rule. From a different model family (Codex if you're Claude, vice versa). Findings to `.local/plan-review.md`. Apply BLOCKER and IMPORTANT before slicing.

Hashimoto's "planning/execution split" applies: do all the planning before you write the first line of code.

## Stage 2 — Decompose into vertical tracer-bullet slices 🅐

**Strongly SOTA-supported.** Matt Pocock's `to-issues` skill is the canonical shape. ai-hero.dev's argument:

> *"AI wants to produce complete solutions all at once… Force the agent to think small, build end-to-end, get feedback, and move forward with confidence."*

Use the `to-issues` skill to produce a slice list. Each slice must:

- **Cut through every relevant layer** (schema/data → service → API → UI → tests) — vertical, not horizontal
- **Be demoable or verifiable on its own** — not "the API is done, UI next sprint"
- **Be independently revertable** — one slice undone shouldn't break the others

### Ordering

**First the walking skeleton**, then risk-prioritized within dependency constraints.

The thinnest end-to-end slice that proves the spine works comes *first* — even if it's not the highest-risk feature. Once the spine is demonstrable, prioritize subsequent slices by risk, **bounded by dependency order**. Don't disguise enabling work or spikes as feature slices — if a migration or technical spike is needed before an honest vertical slice exists, label it as such.

### Anti-pattern

- **Fake vertical slices** — a "slice" that's actually horizontal layered work hidden behind a slice-shaped issue title. If it's not demoable end-to-end, it's not a slice.
- **Risk-first without a skeleton** — attacking the hardest behavior before proving the path exists. Spike first if needed; don't force the hard slice as #1.
- **Slice inertia between candidates** — "we did A–E so let's do F" is not a reason to do F. Before adding a slice from an audit list, apply the **actively-biting test**: does this seam cause PR friction, recurring bugs, or block a feature? Long ≠ tangled. If just long, scope it tighter or skip.

## Stage 3 — Per-slice red → green → refactor with strict phase isolation 🅐 🅡

**The TDD core. Strongly supported.** For each slice:

### Red — write the failing test first

- Test behavior through the slice's **public interface**, not implementation shape
- Test must fail for the right reason (not import error, not undefined symbol)
- Tests written against the slice's **acceptance contract** from the per-slice template (see below) — not invented behavior
- **Strict context isolation between red and green.** Either:
  - Clear the agent's context between writing the test and writing the impl, OR
  - Use a different agent / model for test authoring (see hardening options below)

The agentic-coding-handbook makes the isolation rule explicit:

> *"Each phase runs in complete isolation: the test writer focuses purely on test design, the implementer sees only the failing test, and the refactorer evaluates clean implementation code. This isolation is the only way to get genuine test-first development from an LLM."*

**Targeted test selection** 🅡: TDAD (arxiv:2603.17973) finds that telling the agent *which specific tests* the change impacts beats generic "run tests." TDAD's result depends on an explicit dependency map / impact-analysis tool. This repo does not currently have that machinery. Pragmatic fallback:

- **When an impact map or reliable code intelligence exists** (Sourcegraph/Amp-style, or a dependency-graph tool): provide the targeted impacted test set
- **Otherwise**: run the new failing test plus the nearest relevant existing tests (same module, same callers). Run broader validation at phase boundary and final integration (Stage 5), not after every green
- A manually guessed impact set is weaker than TDAD's tooled version — do not over-trust it

### Hardening options for tests (high-risk slices only)

These add cost; use only when slice risk warrants it:

- 🅡 **Cross-model test review** — different-model agent reads the test and challenges whether it encodes implementation shape vs. behavior. Better-supported than cross-model authorship.
- 🅔 **Cross-model test authoring** — a different model writes the failing test from acceptance criteria, the implementing model writes only the impl. *Experimental synthesis from cross-model review patterns; not documented as established SOTA*. Risk: tests authored in isolation can encode imagined behavior or accidental API shape (see Hora et al. *"Are Coding Agents Generating Over-Mocked Tests?"*). If used, require the test author to work strictly from the per-slice acceptance contract + domain docs, and have the implementer challenge any test that encodes impl shape.

### Green — make the test pass

- Smallest impl that makes the failing test pass
- Don't add behavior the test doesn't require
- Run the new failing test plus the nearest relevant existing tests (per "Targeted test selection" above); broader runs come at phase boundary / final integration

### Refactor (micro) — inside the slice 🅐

This is the TDD refactor step — **micro-refactoring inside the green slice**. Matt Pocock's `tdd` skill includes a refactor step after green; apply it scoped to the slice only. (Claude Code's built-in `simplify` slash command is a useful tool-specific helper for this if you're on Claude Code, but it's not a repo-shared skill — don't rely on it for cross-tool portability.)

Note the distinction: micro-refactor inside a slice ≠ architecture-deepening refactor (see Stage 6). Don't smuggle structural refactors into feature slices.

### Per-slice review

Trigger cross-model review per `WORKFLOW.md`'s dual-trigger rule. If the slice modifies shared agent behavior or embeds a design decision, one cross-model pass per slice. If purely mechanical, batch at Stage 5.

**Pre-flight your own diff before sending it.** Closure rounds (a second review pass on the same slice to address findings the first pass surfaced) are a process signal that the rewire-phase self-review missed something — not a routine step. Target **0 closure rounds per slice**. Before the cross-model review:

- Read every hunk in the slice diff
- Grep for dead helpers / orphan imports / stale test patches the rewire didn't clean up
- Run the full test gate (lint + types + unit) — don't outsource that catch
- Ask "what would the reviewer flag here?" and pre-fix it

If a closure round IS needed (real BLOCKER, hidden invariant surfaced), treat it as an exception. Closures > 1 on the same slice = the slice was over-scoped, has a hidden BLOCKER, or your diff hygiene slipped.

### Per-slice commit

Each slice = revertable unit. Commit message names the slice and its acceptance criterion.

## Stage 4 — Trigger-based drift checks (not cadence) 🅡 🅛

**Concept SOTA-supported. Fixed cadence is opinion-based — don't hard-code it.**

Run `zoom-out` skill (or equivalent reflection prompt) when **any** of these fire:

- Phase boundary crossed (one phase of the plan is done; before starting the next)
- About to cross a new architectural boundary (new module, new service, new external dep)
- Repeated validation failures on the same slice
- Scope expansion observed ("we noticed X also needs to change")
- Context reset / handoff happened (you cleared, or another session is picking up)
- Before final integration (immediate predecessor to Stage 5)

May also run periodically if the work is genuinely long-running — but trigger-based is the primary mechanism. Cadence-based zoom-out becomes bureaucratic and gets skipped.

## Stage 5 — Final integration & merge 🅐 🅛

1. **Integrated diff review** — read the full delta from spine to last slice. Catches inter-slice drift the per-slice review missed.
2. **`/ultrareview`** (Opus 4.7) — same-model multi-pass for depth. Not a substitute for cross-model.
3. **Cross-model integrated review** — different model family reads the integrated diff. Required if `WORKFLOW.md` dual-trigger fires (which it almost always will for L work).
4. **Manual QA / taste pass** — Matt Pocock + Ronacher: final tests are necessary but not sufficient for UX/product shape. Especially for user-facing features.
5. **ADR** if a real design decision was made along the way (genuine alternatives, hard to reverse, surprising without context). Rare; not for every L feature.
6. **`arch-docs` update** if the change touches the system's living architecture (new module, new boundary, new invariant).

## Stage 6 — Architecture-deepening refactor as separate cadence 🅛

**Important distinction from Stage 3 refactor:**

- **Micro-refactor inside a slice (Stage 3)** is part of TDD; do it.
- **Architecture-deepening / module-boundary refactor (this stage)** is *separate work*. It gets its own plan, its own review, and is not interleaved with feature delivery.

Use `improve-codebase-architecture` skill on a backlog rhythm (e.g., after N features, or when drift becomes visible via `zoom-out`). Treat as its own L-feature workflow if substantial.

**Anti-pattern**: "Just clean this up while I'm here" inside a feature slice. Either it's covered by the slice's micro-refactor (small, scoped), or it's separate work — never the smuggled middle.

---

## Per-slice acceptance contract template

Every slice carries this short artifact. Put it in the slice's GitHub issue, the plan file, or the slice's commit-message preamble:

```
# Slice: <name>

## Acceptance behavior
<one paragraph: what user-visible behavior does this slice add or change?>

## Public interface touched
<list of public functions/endpoints/UI surfaces affected>

## Test to add/run
<the failing test that defines done; or a description sufficient for a different agent to author it>

## Non-goals
<what this slice deliberately does NOT do>

## Validation command
<the exact command(s) that prove this slice works; runnable by a different session>

## Rollback note
<how to undo this slice cleanly if it ships and is wrong>

## Residual risks
<known limitations or follow-ups>
```

This is the artifact that lets a different model author/review tests without inventing behavior, and lets a future session resume the work without re-deriving context.

---

## Cross-cutting requirements

Apply these alongside the stages, not as separate stages:

### Context & handoff 🅛

Cross-reference `WORKFLOW.md` Long-running mode. For any L-feature that spans sessions or pauses:

- `.local/session-state.md` — what's done / in-flight / next, updated end-of-session
- `.local/agent-brief.md` — initializer brief the next session reads cold (Matt Pocock `triage` / `AGENT-BRIEF.md` pattern)
- `ae memo` — shared workspace handoff in multi-agent sessions
- ADRs in `docs/adr/` for durable decisions made mid-feature

### Codebase intelligence / impact analysis 🅡

For high-blast-radius slices, do an explicit impact pass before committing:

- Identify callers, ownership boundaries, contracts, migrations, tests affected
- Use repo tools first (`Grep`, `Glob`, `Explore` subagent)
- For very large codebases or cross-repo work where completeness matters: Sourcegraph/Amp-style code intelligence or MCP-backed code-search tools

Grep-based exploration is *not enough* when completeness matters (Sourcegraph/Amp lesson, `KNOWLEDGE.md` §18 practitioner refs).

### Harness engineering 🅐

Hashimoto's rule: every repeated agent mistake becomes a script, check, `AGENTS.md` rule, or tool. If the agent makes the same mistake across two slices, fix the harness, not the agent's prompt.

### Security / dependency / license gate 🅛

For any slice that adds dependencies, GitHub Actions workflows, auth/permissions, external network calls, or generated code from third-party sources: run the `security-review` skill (or `gha-security-review` for `.github/workflows/`) before merge. Even if the dual-trigger doesn't fire on its own, security-relevant changes get this pass.

---

## Anti-patterns specific to this playbook

- **Running all 7 stages on every L feature** — over-prescription. The playbook is full-rigor; the baseline `WORKFLOW.md` L is plan + phased. Most L features sit between.
- **Fake vertical slices** — horizontal layered work in slice-shaped issue titles
- **Disguising spikes as features** — call enabling work and technical spikes what they are
- **Cross-model test authoring as default** — it's experimental; use only when slice risk warrants the overhead
- **Cadence-based zoom-out** — gets skipped when bureaucratic; use triggers
- **Smuggling architecture refactor into feature slices** — Stage 3 is micro only; Stage 6 is the place for structural work
- **Per-slice acceptance contract missing** — without it, a different agent can't author tests safely and the feature becomes a black box
- **Closure rounds as routine** — the cross-model review's job is to catch what your self-review missed; closures as a workflow step mean the slice review pass got sloppy. Treat them as exceptions, not steps. Target 0 closures per slice; multi-closure slices want re-scoping, not more reviews.

---

## What's genuinely novel here vs. published SOTA

To be transparent about what this playbook is doing beyond pure synthesis:

- 🅔 **Cross-model test authoring** as a documented hardening option (Stage 3) — extrapolation, not yet documented elsewhere. Labeled experimental.
- 🅛 **Architecture-deepening refactor as a separate cadence with explicit micro-refactor allowance inside TDD** (Stage 6 + Stage 3 distinction) — local doctrine that resolves the apparent contradiction between "refactor inside features" and "separate architectural work."
- 🅛 **Per-slice acceptance contract template** — synthesizes Matt Pocock `to-issues` + Hashimoto harness-engineering + Willison test-first into a single artifact per slice.

Everything else is documented practitioner pattern or research-backed adjacent (see source labels per stage).

---

## Cross-references

- `WORKFLOW.md` — the operating doctrine. This playbook is an optional deep path for L features.
- `KNOWLEDGE.md` §18 (References / Practitioner references) — cited SOTA voices
- `shared/AGENTS.md` — the cross-model collaboration contract that Stages 1 and 5 enforce
- `skills/to-issues/` — Matt Pocock's vertical-slice decomposition (Stage 2)
- `skills/tdd/` — Matt Pocock's TDD loop (Stage 3 core)
- `skills/grill-with-docs/` — Stage 0
- `skills/scope/` — Stage 1 plan production
- `skills/zoom-out/` — Stage 4 drift check
- `skills/improve-codebase-architecture/` — Stage 6 architecture work
- `skills/security-review/`, `skills/gha-security-review/` — security gate
- `skills/diagnose/` — bug-shaped tasks (use this playbook's structure if a bug requires L-scale work)

---

## Sources

- Matt Pocock — `to-issues`, `tdd`, `to-prd` skills (vendored); `tracer-bullets`, `prd-to-plan`, `plan-from-prd` upstream-only, not vendored here [C]
- ai-hero.dev — "Tracer Bullets: Keeping AI Slop Under Control" [C]
- Simon Willison — Agentic Engineering Patterns / Red-Green TDD [C]
- Tweag — Agentic Coding Handbook, TDD workflow — https://tweag.github.io/agentic-coding-handbook/WORKFLOW_TDD/ [C]
- arxiv:2603.17973 — "TDAD: Test-Driven Agentic Development — Reducing Code Regressions in AI Coding Agents via Graph-Based Impact Analysis" [B]
- arxiv:2604.26615 — "TDD Governance for Multi-Agent Code Generation via Prompt Engineering" [B]
- Hora et al. — "Are Coding Agents Generating Over-Mocked Tests?" [B]
- Mitchell Hashimoto — My AI Adoption Journey (harness engineering) [C]
- Addy Osmani — Long-running agents (handoff patterns) [C]
- Boris Cherny — "Always give Claude a way to verify its work" [A]
- Armin Ronacher — judgment-not-abdication; manual QA / taste pass [C]
- Anthropic 2026 Agentic Coding Trends Report [A]
- `shared/AGENTS.md` Cross-Model Collaboration section [L]
- `WORKFLOW.md` L bucket + Long-running mode [L]

---

*Last updated: 2026-05-11.*
*Drafted by Claude, adversarially reviewed by codex:coworker via `ae review` (review-20260511T094422Z-ddda2333). All IMPORTANT findings applied before this draft was written; not yet committed pending user review.*
