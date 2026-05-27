---
name: scope
description: |
  Decompose a task into a phased implementation plan with test gates.
  Use before starting non-trivial work to align on approach, identify
  risks, and break work into verifiable steps. Produces a structured
  plan document.
---

# Scope

Break down a task into a phased plan before jumping into code. Think first, build second.

## When to use

- Before starting any non-trivial feature or refactor
- When a task touches multiple files, modules, or systems
- When the approach isn't obvious and you want to align before coding
- When the user asks "how would you approach this?" or "what's the plan?"
- Before parallel agent work (each agent needs a clear scope boundary)

## Inputs

Gather enough context to plan, but don't over-research:

1. **Task description**: what needs to happen (from user or issue)
2. **Codebase recon**: read relevant files, understand current structure
3. **Constraints**: deadlines, compatibility requirements, things that must not break
4. **Prior art**: has something similar been done in this repo? Follow the pattern or explicitly decide not to.

## Scoping process

### Step 1: Restate the goal

Write a single sentence describing what "done" looks like. This is your north star.
If you can't write this sentence, the task isn't clear enough — ask.

### Step 2: Identify the change surface

List every file, module, API, database table, or config that will be touched.
For each, note whether it's a create, modify, or delete.

Use `grep`, `glob`, and file reads — don't guess.

### Step 3: Identify risks and unknowns

What could go wrong? What don't you know yet?

Categories:
- **Breaking changes**: callers, consumers, downstream systems
- **Data concerns**: migrations, backfills, backward compatibility
- **Performance**: will this change hot paths? Add load?
- **Security**: new attack surface? Auth changes? Input handling?
- **Dependencies**: new packages, version constraints, license issues
- **Unknowns**: things you need to investigate before committing to an approach

### Step 4: Break into phases

Each phase must be:
- **Independently verifiable** — has a test gate (automated test, manual check, or both)
- **Safely commitable** — the codebase works after each phase, even if the feature is incomplete
- **Small enough to review** — if a phase would produce a 500-line diff, split it

Phase structure:
1. Description: what this phase does
2. Files touched: specific paths
3. Test gate: how to verify this phase is correct
4. Dependencies: which phases must complete first
5. Estimated complexity: trivial / moderate / complex

### Step 5: Define the verification plan

How do you know the whole thing works? Not just "tests pass" — what does the user see?
What would a manual smoke test look like?

## Output format

```markdown
## Scope: <task title>

**Goal:** <one sentence — what "done" looks like>
**Complexity:** trivial | moderate | complex | needs-spike
**Estimated phases:** <N>

### Change surface

| Path | Action | Notes |
|------|--------|-------|
| `src/foo.py` | modify | add new endpoint |
| `tests/test_foo.py` | create | cover new endpoint |
| `db/migrations/003.sql` | create | add column |

### Risks & unknowns

- <risk 1: description + mitigation>
- <risk 2: description + mitigation>
- <unknown 1: what needs investigating + how>

### Rollout & operability

- **Rollout strategy:** big-bang | feature flag | gradual | canary
- **Rollback plan:** <how to revert if things go wrong>
- **Observability:** <logging, metrics, or alerts to add/modify>
- **Backward compatibility:** <API consumers, queued jobs, cached data affected?>

### Phases

#### Phase 1: <title>
- **Do:** <what to implement>
- **Files:** `path/a`, `path/b`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** none

#### Phase 2: <title>
- **Do:** <what to implement>
- **Files:** `path/c`, `path/d`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** Phase 1

#### Phase 3: <title>
- **Do:** <what to implement>
- **Files:** `path/e`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** Phase 1, Phase 2

### Verification

- <end-to-end check 1>
- <end-to-end check 2>
- <manual smoke test description>

### Out of scope

- <thing explicitly NOT included>
- <follow-up work for later>
```

## Complexity levels

- **Trivial**: single file, obvious change, no dependencies. Skip scoping — just do it.
- **Moderate**: 2-5 files, clear approach, some test coverage needed. Scope briefly.
- **Complex**: many files, architectural decisions, multiple phases. Full scope.
- **Needs-spike**: unknowns dominate. The first phase should be a time-boxed investigation, not implementation.

## Rules

- **Don't scope trivial work.** If it's a one-file, obvious change — just do it. Scoping a typo fix is waste.
- **Phases must be verifiable.** "Refactor the module" is not a phase. "Extract X into Y and verify tests pass" is.
- **Be honest about unknowns.** "I don't know if this API supports X" is better than assuming it does.
- **Stay concrete.** File paths, function names, specific commands — not "update the relevant modules."
- **Out of scope is valuable.** Explicitly saying what you won't do prevents scope creep.
- **Don't gold-plate the plan.** A good plan is a tool, not a deliverable. 10 minutes of scoping, not 2 hours.
- **Update the plan.** If reality diverges during implementation, update the plan — don't silently abandon it.

## Boundary with other skills

- **`code-review`**: reviews implementation after the fact. This skill plans before implementation.
- **`inter-agent-collab`**: use when multiple agents need formal convergence artifacts (positions, reviews, signoffs). Use `scope` for single-task planning by one agent.

## Integration with cross-model workflow

When using the plan → review → implement → verify workflow from AGENTS.md:

1. **Scope** (this skill) → produces the plan
2. **Cross-model review** → second tool reviews the plan for gaps
3. **Implement** → follow the phases, check gates
4. **Code review** → review the implementation against the plan

The plan is the contract. Implementation should trace back to it.

## Anti-patterns

- Scoping for 2 hours then implementing in 20 minutes
- Plans with no test gates ("Phase 3: test everything")
- Phases that can't be committed independently
- Ignoring unknowns and hoping they resolve themselves
- Over-specifying implementation details (the plan says *what*, not *how* line-by-line)
- Never updating the plan when reality changes
- Treating the plan as a commitment instead of a tool
