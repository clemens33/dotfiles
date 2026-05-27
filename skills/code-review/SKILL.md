---
name: code-review
description: |
  Adversarial code review with structured findings. Use after implementing
  changes, before committing. Works with uncommitted diffs, staged changes,
  or branch comparisons. Produces BLOCKER/IMPORTANT/NIT findings.
---

# Code Review

Adversarial, structured code review. Not a rubber stamp — find what's wrong.

## When to use

- After implementing a feature or fix, before committing
- When reviewing someone else's changes
- When the cross-model review in AGENTS.md triggers (significant changes)
- Anytime you want a second pair of eyes on a diff

## Inputs

Determine the review scope automatically:

1. **Uncommitted changes** (default): `git diff` + `git diff --cached` + untracked files
2. **Branch comparison**: `git diff main...HEAD` (all commits on current branch)
3. **Specific files**: when the user names files or paths
4. **PR review**: when given a PR number, URL, or patch (availability depends on tool/environment)

If no scope is specified, use uncommitted changes.

## Review process

### Step 1: Understand intent

Before reviewing, understand what the change is trying to do:
- Read commit messages, PR description, or ask the user
- Identify the category: new feature, bug fix, refactor, config change, dependency update
- Note the expected behavior change

### Step 2: Read the diff carefully

Read every changed file. For each change:
- Understand what the code did before and what it does now
- Check if the change is complete (no half-done refactors, no orphaned references)
- Look at surrounding code for context — don't review lines in isolation

### Step 3: Analyze against checklist

**Correctness:**
- Does the logic actually do what the intent says?
- Are there off-by-one errors, race conditions, null/undefined risks?
- Are error paths handled? What happens when things fail?
- Are there implicit assumptions that could break with different inputs?

**Completeness:**
- Are all callers/references updated? (`grep` for renamed functions, changed signatures)
- Are tests added or updated to cover the change?
- Are docs updated if behavior changed?
- Is the migration/rollback story clear for data changes?

**Architecture:**
- Does this follow existing patterns in the codebase, or introduce a new one?
- If a new pattern: is it justified? Will it cause confusion alongside the old one?
- Is the abstraction level right? (not over-engineered, not a hack)
- Does this belong in this file/module/package?

**Security:**
- Input validation at system boundaries (user input, API responses, file reads)
- No secrets, credentials, or PII in code or logs
- No SQL injection, XSS, command injection, path traversal
- Auth/authz checks in place for new endpoints or operations
- Dependency additions: known vulnerabilities? Maintained?

**Performance:**
- N+1 queries, unbounded loops, missing pagination
- Large allocations or copies where streaming would work
- Missing indexes for new query patterns
- Cache invalidation issues

**Operability & rollout:**
- Can this be deployed incrementally? Feature flags, gradual rollout?
- Is the change revertable without data loss?
- Are logging, metrics, or alerts affected? New failure modes observable?
- Backward compatibility with live systems (API consumers, queued jobs, cached data)
- Does this need a maintenance window or coordinated deployment?

**Edge cases:**
- Empty inputs, zero-length collections, nil/null values
- Concurrent access, reentrant calls
- Unicode, timezone, locale issues
- Boundary values (max int, empty string, very long strings)

### Step 4: Produce findings

Each finding must have:
- **Severity**: BLOCKER, IMPORTANT, or NIT
- **Location**: file path + line number or function name
- **What**: what's wrong (be specific)
- **Why**: why it matters (consequence if not fixed)
- **Fix**: concrete suggestion (not "consider improving this")

**Severity definitions:**
- **BLOCKER**: Must fix before commit. Bugs, security issues, broken callers, data loss risks, incorrect behavior.
- **IMPORTANT**: Should fix before commit. Architectural concerns, missed edge cases, incomplete changes, missing tests for critical paths.
- **NIT**: Optional. Style, naming, minor suggestions, readability improvements. Apply if quick.

### Step 5: Verdict

End with one of:
- **APPROVE** — No blockers, no important findings. Ship it.
- **APPROVE WITH NITS** — No blockers, no important findings, some nits. Ship it, fix nits if quick.
- **REQUEST CHANGES** — Has IMPORTANT or BLOCKER findings. Fix before committing.
- **BLOCKER** — Critical issues. Do not commit.

## Output format

```markdown
## Code Review

**Scope:** <what was reviewed — files, diff range, PR#>
**Intent:** <one-line summary of what the change does>
**Verdict:** <APPROVE | APPROVE WITH NITS | REQUEST CHANGES | BLOCKER>

### Findings

#### BLOCKER

1. **[file:line]** <title>
   - What: <specific description>
   - Why: <consequence>
   - Fix: <concrete suggestion>

#### IMPORTANT

1. **[file:line]** <title>
   - What: <specific description>
   - Why: <consequence>
   - Fix: <concrete suggestion>

#### NIT

1. **[file:line]** <title>
   - Suggestion: <what to change>

### Summary

<2-3 sentences: overall assessment, patterns noticed, things done well>
```

If no findings at a severity level, omit that section entirely.
If there are no findings at all, state **"No findings"** explicitly.

## Relationship to cross-model review

This skill structures a code review within a single tool session. It does **not** satisfy the mandatory cross-model review policy in AGENTS.md for significant changes. That policy requires a different AI tool (e.g. Codex reviewing Claude's work). Use this skill to structure the review prompt and findings format for both same-tool and cross-model reviews.

## Boundary with other skills

- **`inter-agent-collab`**: use for multi-agent design convergence. This skill reviews diffs/changesets, not architectural positions.
- **`scope`**: use before implementation to plan. This skill runs after implementation to verify.

## Rules

- **Be adversarial.** Your job is to find problems, not confirm the code works.
- **Be specific.** "This could be improved" is not a finding. Say what's wrong, where, and how to fix it.
- **Be honest.** "No findings" is a valid and respectable outcome. Don't manufacture nits to look thorough.
- **No false positives.** Every finding must have a concrete consequence. "I don't like the style" is not IMPORTANT.
- **Check callers.** Renamed a function? Changed a return type? Added a required param? `grep` for all references.
- **Read surrounding code.** A change that looks fine in isolation may break invariants in context.
- **Don't rewrite.** You're reviewing, not reimplementing. Suggest fixes, don't produce alternative implementations unless asked.

## Anti-patterns

- Rubber-stamping ("LGTM looks good")
- Inventing findings to appear thorough
- Reviewing only the diff without reading surrounding code
- Marking style preferences as BLOCKER
- Suggesting rewrites of code that wasn't changed
- Ignoring test coverage
- Missing broken callers after signature changes
