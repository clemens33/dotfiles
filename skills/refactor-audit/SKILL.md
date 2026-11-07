---
name: refactor-audit
description: >
  Audits a codebase for architecture drift and recommends whether a structural
  refactor is warranted, with evidence and guardrail candidates. Use when asked
  "is this codebase getting messy?", "should we refactor?" or "run a refactor
  audit", after a cluster of feature slices, or before a release-hardening
  pass. Does not execute the refactor (use `scope` or `large-feature` to plan
  and run it).
source: local-dotfiles
metadata:
  category: preference

---

# Refactor Audit

Decide whether structural refactoring is warranted, with evidence. The skill answers *"is there enough architecture drift to justify a separate refactor right now?"* and routes to the right next workflow. It does not perform the refactor.

## When to invoke

Any of:

- Explicit user request — *"audit this codebase"*, *"are we drifting?"*, *"run a refactor audit"*
- After completing a cluster of related feature slices (post-feature-cluster review)
- Before a tagged release (release-hardening pass)
- When a zoom-out reflection flags drift during long-running work
- When the same agent mistake recurs across sessions
- When review bandwidth feels disproportionate to PR size

No calendar cadence default: calendar sweeps are busywork unless the team already runs scheduled maintenance windows. Trigger-based is the default.

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
  structural-refactor (requires-plan: no) /
  structural-refactor (requires-plan: yes — scope first) /
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
- **Static-analysis findings cluster** (Sonar, Semgrep) in one module.

Always compare against the **repo's own baseline**. There is no universal "20% slower" threshold; if no baseline exists, record under tooling-gap and propose recording one.

### Soft signals (judgment / observation)

These rely on session notes, commit history, or agent recall.

- Same agent mistake recurring across two or more sessions
- "Just one more thing" responsibility creep — one module growing across unrelated features
- Repeated cross-file edits to express one concept — coupling smell
- Review burden disproportionate to PR size — review requires repeated clarification rounds, multiple missed-caller findings, or reviewer cannot validate a small PR without reconstructing several modules
- A zoom-out reflection flagged drift during long-running work
- Multiple recent slices needed an unplanned "fix this adjacent thing" detour
- Missed-caller surprises during reviews (completeness gaps)

### Tooling-gap signals

Plausible signals we cannot currently observe because the tool isn't configured. Examples:
- "Import cycles" in a Python repo that has no `import-linter` or `grimp` — log as tooling-gap, propose adding the tool.
- "Duplication" in a JS/TS repo with no `jscpd` configured — same.

Tooling-gap signals do not count toward the decision rule. They appear in the guardrail-candidates section.

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

The audit makes two separate decisions in order. Scope shape never triggers refactor on its own — evidence must justify separate refactor work first, then scope shape chooses the workflow.

### Stage 1 — Should separate refactor work exist? (evidence-gated)

| Stage 1 trigger | Outcome |
|---|---|
| 2+ hard signals fired this audit | Yes → proceed to Stage 2 |
| 1 hard + 2 soft signals fired this audit | Yes → proceed to Stage 2 |
| 2+ soft signals repeated from the previous audit (`Repeated soft signals` field; see Prior-audit comparison above) | Yes → proceed to Stage 2 |
| Explicit user request **with evidence** (user named a concrete drift) | Yes → proceed to Stage 2 |
| Explicit user request, no evidence | Produce the artifact, record signals, recommendation = `no-action`; do not proceed to Stage 2 |
| Only soft signals this audit, no repeats from prior | `no-action`; log soft signals so next audit can detect repeats |
| Nothing fired | `no-action` |

### Stage 2 — Which workflow routes the refactor? (scope-shape choice)

Reached only after Stage 1 says yes.

| Scope shape | Recommendation |
|---|---|
| Bounded area, one module, no cross-cutting impact | `structural-refactor` directly (`requires-plan: no`: TDD refactor steps, normal review) |
| Non-trivial surface or unclear shape | `structural-refactor` with `requires-plan: yes` (run `scope` first, then execute the phased plan) |
| Multi-slice / high blast radius / audit-relevant / multi-session / needs defensible handoff | `large-feature` playbook (treat the refactor itself as an L feature) |

Multi-slice / high blast radius / etc. are routing choices in Stage 2, not triggers in Stage 1. A high-blast potential refactor that has no evidence supporting it stays at `no-action`. The recommendation routes to a workflow; it does not perform the work.

## Recommendation classes

- **no-action** — signals don't justify separate refactor work. Note in artifact for next audit.
- **micro-refactor-in-slice** — surface area is small enough to be a TDD refactor step inside the current feature work. Do not escalate to separate refactor.
- **structural-refactor** — structural drift confirmed; do the refactor as its own work, routed by the Stage 2 table. Older audits label this class `improve-codebase-architecture` (same meaning).
- **large-feature playbook** — the refactor is multi-slice or high blast radius; see the Stage 2 table.

## Guardrail candidates — promote soft to hard

Every repeated soft signal should either become a hard guardrail (CI check, lint rule, contract) or be explicitly accepted/documented in the audit so it stops re-firing as a "discovery." Always close the audit with concrete guardrail candidates:

- *"Import cycle in `module X` was noticed manually twice → add `import-linter` contract preventing imports between X and Y."*
- *"Same forgotten validation appeared in three PRs → add a Semgrep rule."*
- *"Test walltime regressing without alarm → add `pytest --durations` to CI with a baseline threshold."*
- *"Coverage drifted down silently → set `fail_under` in `pyproject.toml`."*

These move drift from "agent has to notice" to "CI surfaces it."

## Relationship to feature work

During feature work, do only the micro-refactor after green (`large-feature` Stage 3). If a feature slice surfaces structural drift, log it as a soft signal for the next audit — don't escalate inside the feature, and don't smuggle "clean up while I'm here" work into the slice. The audit is the gate that converts soft signals into a separate refactor task.

Do not start a structural refactor without test coverage in the affected area. A coverage gap is itself a guardrail candidate; address it first.

## Cross-references

- `skills/scope/` — phased planning when the refactor is non-trivial.
- `skills/large-feature/` — full-rigor 7-stage playbook when the refactor is multi-slice or high blast radius.
- `WORKFLOW.md` — the lean L mandate (plan + phased execution) still applies to substantial refactor work.
- `references/background.md` — SOTA grounding and practitioner references.
