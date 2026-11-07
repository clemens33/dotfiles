---
name: scope
description: >
  Decomposes a non-trivial task into a phased plan with change surface, risks
  and a test gate per phase. Use when starting work that touches several files
  or systems, when the approach is unclear, or before parallel agent work. Not
  for trivial changes, which need no plan, or for multi-agent convergence
  artifacts (use `collab`).
metadata:
  category: preference

---

# Scope

Break a task into a phased plan before jumping into code.

## When to use

- Before starting any non-trivial feature or refactor, especially one that touches multiple files, modules, or systems
- When the approach isn't obvious and you want to align before coding, or the user asks "how would you approach this?" or "what's the plan?"
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
Search the repo; don't guess.

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

The phase fields (Do, Files, Complexity, Test gate, Depends on) are in the plan template.

### Step 5: Define the verification plan

How do you know the whole thing works? Not just "tests pass" — what does the user see?
What would a manual smoke test look like?

## Output format

Use `references/plan-template.md` as the skeleton of the plan document: header, change surface, risks & unknowns, rollout & operability, phases, verification, out of scope.

## Complexity levels

Classify by **worst-of-three** (`WORKFLOW.md`): take the worst of **effort**, **blast radius**
and **uncertainty**. Not file count, not elapsed time — a one-line change to a shared auth
default is not trivial, and a forty-file mechanical rename is not complex.

| Worst of the three | Bucket | Plan field | What to do |
|---|---|---|---|
| all three low | S | `trivial` | Skip scoping — just do it |
| medium | M | `moderate` | Scope briefly: goal, change surface, 1-3 phases |
| any one high | L | `complex` | Full scope: written plan first, phased execution, each phase ends green-or-stop |

Add `needs-spike` when uncertainty dominates — the first phase is then a time-boxed
investigation, not implementation. It is a shape, not a fourth size: an L whose unknowns have
to be retired before the rest of the plan is worth writing.

## Rules

- **Phases must be verifiable.** "Refactor the module" is not a phase; "Phase 3: test everything" has no test gate. "Extract X into Y and verify tests pass" is a phase.
- **Be honest about unknowns.** "I don't know if this API supports X" is better than assuming it does.
- **Stay concrete.** File paths, function names, specific commands — not "update the relevant modules." The plan says *what*, not *how* line by line.
- **Out of scope is valuable.** Explicitly saying what you won't do prevents scope creep.
- **Don't gold-plate the plan.** A good plan is a tool, not a commitment. 10 minutes of scoping, not 2 hours.
- **Update the plan.** If reality diverges during implementation, update the plan — don't silently abandon it.

## Boundary with other skills

- **`code-review`**: reviews implementation after the fact. This skill plans before implementation.
- **`collab`**: use when multiple agents need formal convergence artifacts (positions, reviews, signoffs). Use `scope` for single-task planning by one agent.

## Integration with cross-model workflow

The plan is the contract; implementation traces back to it. In the plan → review → implement → verify workflow from AGENTS.md: scope (this skill) produces the plan, a reviewer on a different model provider reviews it for gaps, you implement and check the gates, then code review checks the implementation against the plan.
