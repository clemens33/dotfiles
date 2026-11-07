---
name: large-feature
description: >
  Full-rigor playbook for large, multi-slice features with high blast radius,
  non-trivial design or a result that must stay defensible after shipping.
  Use when invoked as /large-feature, for multi-day work needing
  cross-provider review and per-phase test gates, or when the lean L bucket in
  WORKFLOW.md is not enough. Not for S/M work, or for bugs (use `diagnose`).
metadata:
  category: preference

---

# Large Feature Full-Rigor Playbook

Optional 7-stage path for high-rigor L-bucket features. `WORKFLOW.md` keeps L's mandatory shape minimal: written plan + phased execution. That does not change; this playbook adds to it.

## When to use

- Use it when blast radius is high, the work is multi-slice, the change is regulatory or audit-relevant, the work spans sessions, or you would be uncomfortable shipping without an audit trail of *why*.
- Skip it when a `scope`-style plan plus per-phase tests is sufficient and you are not bottlenecked on uncertainty or review bandwidth.
- Do not run all 7 stages on every L feature. Most L work sits between the `WORKFLOW.md` baseline and this playbook.

Sources and method grounding: `references/provenance.md`.

---

## Stage 0 — Sharpen via `grill-with-docs`

**Gate:** Run if domain language uncertainty or prior-decision ambiguity is high. Skip if the request is unambiguous and the project's `CONTEXT.md` / ADRs already settle the relevant terms.

Use the `grill-with-docs` skill against `CONTEXT.md`, `docs/adr/`, and existing skills in the area. Output is **sharpened understanding**, not yet a plan.

If you can already write a clean one-sentence "done" definition, skip this stage — the language is already settled. That does **not** reclassify the work. A clear done definition lowers *uncertainty*; it leaves effort and blast radius exactly where they were, and the bucket is the worst of the three (`WORKFLOW.md`). A well-understood change to a shared contract is still L.

**Greenfield features without a spec:** write a short spec (PRD) first, then grill against it. The pipeline is spec → `scope` → slices.

## Stage 1 — Plan + cross-model plan critique

**Gate:** Always for L features under this playbook.

### Preflight — discover and run the validation harness

Before `scope`, before any planning: **run the repo's existing test/lint/typecheck commands.** This teaches the agent the validation harness, surfaces a broken baseline, and puts it into testing mode before any change.

- If commands are unknown, discover them: read `package.json`, `pyproject.toml`, `justfile`, `Makefile`, `.github/workflows/`, the project's `CLAUDE.md` / `AGENTS.md`
- Record the discovered validation commands in `.local/plan.md` so every slice's acceptance contract can reference them
- If existing tests fail on a clean checkout, **stop and declare the verification gap explicitly** before adding new work (`WORKFLOW.md` universal principle #1)

### Plan

1. Use the `scope` skill → `.local/plan.md` with phased plan, test gates per phase, and acceptance criteria. Include the validation commands discovered in preflight.
2. **Cross-model plan critique** per the `WORKFLOW.md` cross-model rule, by a reviewer on a different model provider (the served model, not the harness; see `cross-model-review`). Findings to `.local/plan-review.md`. Apply BLOCKER and IMPORTANT before slicing.

Do all planning before the first line of code.

## Stage 2 — Decompose into vertical tracer-bullet slices

Build thin end-to-end slices, get feedback, then move on. Produce a slice list. Each slice must:

- **Cut through every relevant layer** (schema/data → service → API → UI → tests) — vertical, not horizontal
- **Be demoable or verifiable on its own** — not "the API is done, UI next sprint"
- **Be independently revertable** — one slice undone shouldn't break the others

### Ordering

**First the walking skeleton**, then risk-prioritized within dependency constraints.

The thinnest end-to-end slice that proves the spine works comes *first* — even if it's not the highest-risk feature. Once the spine is demonstrable, prioritize subsequent slices by risk, **bounded by dependency order**. Don't disguise enabling work or spikes as feature slices — if a migration or technical spike is needed before an honest vertical slice exists, label it as such.

### Anti-patterns

- **Fake vertical slices** — a "slice" that's actually horizontal layered work hidden behind a slice-shaped issue title. If it's not demoable end-to-end, it's not a slice.
- **Risk-first without a skeleton** — attacking the hardest behavior before proving the path exists. Spike first if needed; don't force the hard slice as #1.
- **Slice inertia between candidates** — "we did A–E so let's do F" is not a reason to do F. Before adding a slice from an audit list, apply the **actively-biting test**: does this seam cause PR friction, recurring bugs, or block a feature? Long ≠ tangled. If just long, scope it tighter or skip.

## Stage 3 — Per-slice red → green → refactor with strict phase isolation

For each slice:

### Red — write the failing test first

- Test behavior through the slice's **public interface**, not implementation shape
- Test must fail for the right reason (not import error, not undefined symbol)
- Tests are written against the slice's **acceptance contract** (template at the end) — not invented behavior
- **Spec-first (default at M/L):** a **different-provider** agent authors and freezes the acceptance tests before implementation; the TDD loop governs implementer-level tests inside that frame. The author works strictly from the acceptance contract plus domain docs, and challenges tests that encode implementation shape (imagined behavior, accidental API shape). A waiver names the triage reason. Contract: `shared/AGENTS.md` → Engineering principles → **Spec-first for M/L**.
- **Strict isolation red|green.** Different-provider authorship is the default form; the context-clear fallback applies only under a named waiver.

**Targeted test selection:** tell the agent which tests the change impacts; that beats a generic "run tests".

- **With an impact map or reliable code intelligence** (a dependency-graph tool, Sourcegraph/Amp-style): provide the targeted impacted test set
- **Otherwise:** run the new failing test plus the nearest relevant existing tests (same module, same callers). Run broader validation at phase boundary and final integration (Stage 5), not after every green
- A manually guessed impact set is weaker than a tooled one — do not over-trust it

### Green — make the test pass

- Smallest impl that makes the failing test pass
- Don't add behavior the test doesn't require
- Run the targeted tests (see Targeted test selection)

### Refactor (micro) — inside the slice

This is the TDD refactor step: micro-refactoring inside the green slice, scoped to the slice only. A micro-refactor inside a slice is not an architecture-deepening refactor (Stage 6). Don't smuggle structural refactors into feature slices.

### Per-slice review

Spec-first author reviews impl by default — that different-provider pass satisfies the slice's cross-model gate. `WORKFLOW.md` dual-trigger applies to work not already reviewed (plan, integrated delta), not a second pass on the same implementation; purely mechanical slices batch at Stage 5. Frozen acceptance tests keep their own separate review against requirements.

**Pre-flight your own diff before sending it.** A closure round (a second review pass on the same slice to address findings the first pass surfaced) signals that self-review missed something. It is not a routine step; target **0 closure rounds per slice**. Before the cross-model review:

- Read every hunk in the slice diff
- Grep for dead helpers / orphan imports / stale test patches the rewire didn't clean up
- Run the full test gate (lint + types + unit) — don't outsource that catch
- Ask "what would the reviewer flag here?" and pre-fix it

If a closure round IS needed (real BLOCKER, hidden invariant surfaced), treat it as an exception. More than one closure on the same slice means the slice was over-scoped, hides a BLOCKER, or your diff hygiene slipped: re-scope it, do not add more reviews.

### Per-slice commit

Each slice = revertable unit. Commit message names the slice and its acceptance criterion.

## Stage 4 — Trigger-based drift checks (not cadence)

Run a zoom-out reflection (go up a layer of abstraction, map the relevant modules and callers, check against the plan) when **any** of these fire:

- Phase boundary crossed (one phase of the plan is done; before starting the next)
- About to cross a new architectural boundary (new module, new service, new external dep)
- Repeated validation failures on the same slice
- Scope expansion observed ("we noticed X also needs to change")
- Context reset / handoff happened (you cleared, or another session is picking up)
- Before final integration (immediate predecessor to Stage 5)

Triggers are the primary mechanism. You may also zoom out periodically on genuinely long-running work, but a fixed cadence turns bureaucratic and gets skipped.

## Stage 5 — Final integration & merge

1. **Integrated diff review** — read the full delta from spine to last slice. Catches inter-slice drift the per-slice review missed.
2. **Optional, human-initiated in Claude Code:** the user can run `/code-review ultra` (billed) for same-provider multi-pass depth. It does not replace the cross-provider review.
3. **Cross-model integrated review** — a reviewer on a different model provider (the served model, not the harness) reads the integrated diff. Required if the `WORKFLOW.md` dual-trigger fires (which it almost always will for L work).
4. **Manual QA / taste pass** — final tests are necessary but not sufficient for UX/product shape. Especially for user-facing features.
5. **ADR** if a real design decision was made along the way (genuine alternatives, hard to reverse, surprising without context). Rare; not for every L feature.
6. **`arch-docs` update** if the change touches the system's living architecture (new module, new boundary, new invariant).

## Stage 6 — Architecture-deepening refactor as separate cadence

- **Micro-refactor inside a slice (Stage 3)** is part of TDD; do it.
- **Architecture-deepening / module-boundary refactor (this stage)** is *separate work*. It gets its own plan, its own review, and is not interleaved with feature delivery.

Run an architecture-improvement pass (start from `refactor-audit`) on a backlog rhythm (e.g., after N features, or when drift becomes visible via a zoom-out reflection). Treat as its own L-feature workflow if substantial.

**Anti-pattern**: "Just clean this up while I'm here" inside a feature slice. Either it's covered by the slice's micro-refactor (small, scoped), or it's separate work — never the smuggled middle.

---

## Per-slice acceptance contract template

Every slice carries this short artifact. Put it in the slice's GitHub issue, the plan file, or the slice's commit-message preamble. Without it a different agent cannot author tests safely and the feature becomes a black box:

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

It also lets a future session resume the work without re-deriving context.

---

## Cross-cutting requirements

Apply these alongside the stages, not as separate stages:

### Context & handoff

Follow `WORKFLOW.md` Long-running mode. For any L feature that spans sessions or pauses:

- `.local/session-state.md` — what's done / in-flight / next, updated end-of-session
- `.local/agent-brief.md` — initializer brief the next session reads cold
- `ae memo` — shared workspace handoff in multi-agent sessions
- ADRs in `docs/adr/` for durable decisions made mid-feature

### Codebase intelligence / impact analysis

For high-blast-radius slices, do an explicit impact pass before committing:

- Identify callers, ownership boundaries, contracts, migrations, tests affected
- Use local search first — whatever your harness offers for grep/glob and a delegated read-only exploration pass
- For very large codebases or cross-repo work where completeness matters: Sourcegraph/Amp-style code intelligence or MCP-backed code-search tools

Grep-based exploration is *not enough* when completeness matters (`KNOWLEDGE.md` §18).

### Harness engineering

Every repeated agent mistake becomes a script, check, `AGENTS.md` rule, or tool. If the agent makes the same mistake across two slices, fix the harness, not the agent's prompt.

### Security / dependency / license gate

For any slice that adds dependencies, GitHub Actions workflows, auth/permissions, external network calls, or generated code from third-party sources: run the `security-review` skill (or `gha-security-review` for `.github/workflows/`) before merge. Even if the dual-trigger doesn't fire on its own, security-relevant changes get this pass.
