---
name: refactor-audit
description: >
  Audit a codebase for architecture drift and produce a `refactor-audit.md`
  with evidence, recommendation, and guardrail candidates. Use when asked
  "is this codebase getting messy?", "are we drifting?", "should we
  refactor?", "run a refactor audit", "architecture health check", or
  before a release-hardening pass. Discovers the repo's existing tooling
  first, then collects hard / soft / tooling-gap signals, compares
  against the previous audit, and applies a two-stage decision rule
  (evidence-gated trigger, then workflow routing). Recommends the next
  workflow: improve-codebase-architecture (with or without scope first)
  or large-feature playbook for multi-slice / high-blast-radius work.
  Does NOT execute the refactor itself — produces evidence and a routing
  decision. Promotes repeated soft signals into CI/lint/check candidates
  per Hashimoto harness engineering.
source: local-dotfiles
---

# Refactor Audit

Decide whether structural refactoring is warranted, with evidence. The skill answers *"is there enough architecture drift to justify a separate refactor right now?"* and routes to the right next workflow. It does not perform the refactor.

## When to invoke

Any of:

- Explicit user request — *"audit this codebase"*, *"are we drifting?"*, *"run a refactor audit"*
- After completing a cluster of related feature slices (post-feature-cluster review)
- Before a tagged release (release-hardening pass)
- When `zoom-out` skill flags drift during long-running work
- When the same agent mistake recurs across sessions (Hashimoto's harness rule)
- When review bandwidth feels disproportionate to PR size

**No calendar cadence default.** Calendar sweeps are busywork unless the team already runs scheduled maintenance windows. Trigger-based is the default.

## Output artifact

Produces `.local/refactor-audit-YYYY-MM-DD.md` with the structure below. The artifact is the deliverable — never just inline a verbal answer.

```
# Refactor Audit — <repo> — <date>

## Previous audit reviewed
<path to latest prior .local/refactor-audit-*.md, or "none">

## Tooling discovered
<commands found in justfile / Makefile / pyproject.toml / package.json /
.github/workflows / sonar-project.properties — what CAN be measured here>

## Signals

### Hard signals (CI/baseline-backed metrics)
| Signal | Fired? | Evidence | Baseline |

### Soft signals (judgment / agent observations)
| Signal | Fired? | Evidence (commit refs, session notes) |

### Tooling-gap signals (plausible but no tool/baseline exists)
| Signal | Why we can't measure | Candidate tool to add |

## Repeated soft signals
<soft signals that ALSO fired in the previous audit — names + brief
diff vs prior evidence; empty list if no prior audit or no repeats>

## Decision

### Stage 1 — Separate refactor work warranted?
<yes / no, with the trigger row that fired from the Stage 1 table>

### Stage 2 — Workflow routing (only if Stage 1 = yes)
<one of:
  improve-codebase-architecture (requires-plan: no) /
  improve-codebase-architecture (requires-plan: yes — scope first) /
  large-feature playbook>

## Rationale
<2-4 sentences citing which signals support the decision, and how the
Repeated soft signals list (if any) influenced Stage 1>

## Guardrail candidates
<repeated soft signals → CI checks/lints/import-linter contracts/coverage
thresholds that would convert these into hard signals next time>

## Validation gaps
<things we couldn't check because tooling is missing; record explicitly,
do not silently skip>
```

## Discover tooling first

Read these files to discover what's actually measurable in *this* repo before claiming any signal:

- `justfile`, `Makefile`, `package.json`, `pyproject.toml`
- `.github/workflows/*`, `.gitlab-ci.yml`
- `sonar-project.properties`, `.semgrep.yml`, `import-linter.cfg`
- Repo `AGENTS.md` / `CLAUDE.md` for declared conventions
- `docs/adr/` for prior architectural decisions

If a signal's tool isn't present in the repo, record it under **tooling-gap**, not under hard signals.

## Signals — three tiers

### Hard signals (CI/baseline-backed)

These have evidence the agent can produce; they require the repo to have the tool configured.

- **Test walltime regression** vs. the repo's own baseline. Python: `pytest --durations=10`. JS/TS: jest/vitest reporters.
- **Coverage regression** vs. baseline. Python: `pytest-cov`. JS/TS: `c8`/`nyc`/jest coverage.
- **Repeated CI failures in the same area** — git log + CI history; same module failing on unrelated PRs is a structural smell.
- **Lint/type complexity threshold crossed** — Python: `ruff` complexity rules (`C90`, `PLR`), `mypy --strict` regressions. JS/TS: eslint complexity rules.
- **Import cycle detected** — Python: `import-linter`, `grimp`, `pydeps --max-bacon`. JS/TS: `madge --circular`.
- **Duplication threshold breach** — Python: `pylint duplicate-code`, `radon`. JS/TS: `jscpd`.
- **Sonar / Trail-of-Bits / fp-check findings cluster** in one module.

Always compare against the **repo's own baseline**. There is no universal "20% slower" threshold; if no baseline exists, record under tooling-gap and propose recording one.

### Soft signals (judgment / observation)

These rely on session notes, commit history, or agent recall.

- Same agent mistake recurring across two or more sessions (Hashimoto's harness trigger)
- "Just one more thing" responsibility creep — one module growing across unrelated features
- Repeated cross-file edits to express one concept — coupling smell
- Review burden disproportionate to PR size — review requires repeated clarification rounds, multiple missed-caller findings, or reviewer cannot validate a small PR without reconstructing several modules
- `zoom-out` skill flagged drift during long-running work
- Multiple recent slices needed an unplanned "fix this adjacent thing" detour
- Missed-caller surprises during reviews (Sourcegraph/Amp lens — completeness gaps)

### Tooling-gap signals

Plausible signals we cannot currently observe because the tool isn't configured. Examples:
- "Import cycles" in a Python repo that has no `import-linter` or `grimp` — log as tooling-gap, propose adding the tool.
- "Duplication" in a JS/TS repo with no `jscpd` configured — same.

Tooling-gap signals do NOT count toward the decision rule. They DO appear in the guardrail-candidates section.

## Prior-audit comparison

Before running the decision rule, **read the latest prior audit** if one exists:

```bash
ls -t .local/refactor-audit-*.md 2>/dev/null | head -1
```

If a prior audit exists:

1. Record its path in the `Previous audit reviewed` field of the new artifact.
2. Compare its `Soft signals — fired` list against this audit's `Soft signals — fired` list.
3. Populate `Repeated soft signals` with any soft signal that fired in BOTH audits (note any change in evidence).
4. Repeated soft signals are the only mechanism that escalates soft-only audits in Stage 1. Without this comparison, soft signals can never trigger separate refactor work, no matter how many audits in a row note them informally.

If no prior audit exists, set `Previous audit reviewed: none` and leave `Repeated soft signals` empty. This audit becomes the baseline for the next one.

## Decision rule — two stages

The audit makes two separate decisions in order. **Scope shape never triggers refactor on its own** — evidence must justify separate refactor work first, then scope shape chooses the workflow.

### Stage 1 — Should separate refactor work exist? (evidence-gated)

| Stage 1 trigger | Outcome |
|---|---|
| 2+ hard signals fired this audit | Yes → proceed to Stage 2 |
| 1 hard + 2 soft signals fired this audit | Yes → proceed to Stage 2 |
| 2+ soft signals repeated from the previous audit (`Repeated soft signals` field; see Prior-audit comparison above) | Yes → proceed to Stage 2 |
| Explicit user request **with evidence** (user named a concrete drift) | Yes → proceed to Stage 2 |
| Explicit user request, no evidence | Produce the artifact, record signals, recommendation = `no-action`; do NOT proceed to Stage 2 |
| Only soft signals this audit, no repeats from prior | `no-action`; log soft signals so next audit can detect repeats |
| Nothing fired | `no-action` |

### Stage 2 — Which workflow routes the refactor? (scope-shape choice)

Reached only after Stage 1 says yes.

| Scope shape | Recommendation |
|---|---|
| Bounded area, one module, no cross-cutting impact | `improve-codebase-architecture` directly |
| Non-trivial surface or unclear shape | `improve-codebase-architecture` with `requires-plan: yes` (run `scope` first) |
| Multi-slice / high blast radius / audit-relevant / multi-session / needs defensible handoff | `large-feature` playbook (treat the refactor itself as an L feature) |

Multi-slice / high blast radius / etc. **are routing choices in Stage 2, not triggers in Stage 1.** A high-blast potential refactor that has no evidence supporting it stays at `no-action`.

The recommendation routes to a workflow; it does not perform the work.

## Recommendation classes

- **no-action** — signals don't justify separate refactor work. Note in artifact for next audit.
- **micro-refactor-in-slice** — surface area is small enough to be a TDD refactor step inside the current feature work. Do NOT escalate to separate refactor.
- **improve-codebase-architecture** — invoke that skill; structural drift confirmed. Carries a `requires-plan: yes/no` flag:
  - `requires-plan: no` — bounded area, one module. Invoke `improve-codebase-architecture` directly.
  - `requires-plan: yes` — non-trivial surface or unclear shape. Run `scope` first to produce a phased plan, then execute via `improve-codebase-architecture`.
- **large-feature playbook** — refactor is multi-slice or high blast radius; treat as an L feature with full rigor (vertical tracer-bullet slices, per-slice red-green, cross-model at plan + merge).

## Guardrail candidates — promote soft to hard

Per Hashimoto's harness-engineering rule: every repeated soft signal should either become a hard guardrail (CI check, lint rule, contract) or be explicitly accepted/documented in the audit so it stops re-firing as a "discovery." Always close the audit with concrete guardrail candidates:

- *"Import cycle in `module X` was noticed manually twice → add `import-linter` contract preventing imports between X and Y."*
- *"Same forgotten validation appeared in three PRs → add a Semgrep rule."*
- *"Test walltime regressing without alarm → add `pytest --durations` to CI with a baseline threshold."*
- *"Coverage drifted down silently → set `fail_under` in `pyproject.toml`."*

These move drift from "agent has to notice" to "CI surfaces it." Over time, the audit relies less on soft signals and more on hard ones.

## Anti-patterns

- **Cadence-without-signal busywork** — don't run the audit on a calendar if no signals fired; you'll either find nothing (waste) or invent something (worse).
- **Refactoring during feature work** — keep Stage 3 micro-refactor inside the slice; use this audit's recommendation for *separate* structural refactor.
- **Big-bang structural refactor** — if recommendation is L, slice it via `to-issues` like any other L feature.
- **Refactor without test coverage in the affected area** — coverage gap is itself a guardrail candidate; address before structural work.
- **"Clean up while I'm here" smuggling** — anything beyond the slice's scope goes into a separate refactor task driven by this audit.
- **Treating tooling-gap signals as fired** — they're not measured yet. They count toward guardrail candidates, not toward the decision rule.
- **Inventing thresholds** — no universal "20% slower" / "10% coverage drop" — always compare against the repo's own baseline. If no baseline exists, record that explicitly.

## Relationship to feature work

During feature work, only do Stage 3 micro-refactor after green. If a feature slice surfaces structural drift, log it as a soft signal for the next audit — don't escalate inside the feature. The audit is the gate that converts soft signals into a separate refactor task.

## Cross-references

- `skills/improve-codebase-architecture/` — the HOW skill. This audit's recommendation routes to it.
- `skills/scope/` — phased planning when the refactor is non-trivial.
- `skills/large-feature/` — full-rigor 7-stage playbook when the refactor is multi-slice or high blast radius.
- `skills/zoom-out/` — soft-signal source during long-running work.
- `WORKFLOW.md` — the lean L mandate (plan + phased execution) still applies to substantial refactor work.
- `KNOWLEDGE.md` §18 — practitioner refs for the SOTA voices cited (Hashimoto harness engineering, Sourcegraph/Amp completeness, Anthropic 2026 "generated code is debt").

## SOTA grounding

- **Hashimoto harness engineering** — every repeated soft signal becomes a guardrail (CI check, lint rule, or tool) or an accepted/documented exception. The audit is the bootstrap mechanism.
- **Sourcegraph/Amp completeness lens** — missed callers and cross-repo surprises are drift signals; grep is not enough on large codebases.
- **Anthropic 2026 Trends Report** — "generated code is debt until validated." Refactor is debt repayment; this audit prioritizes which debt to repay.
- **Pi/minimal-agent counter-take** — the durable solution is making drift observable via tooling, not a recurring process. Use this skill to bootstrap guardrails, then retire its scope as guardrails mature.
