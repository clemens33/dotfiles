---
name: code-review
description: >
  Adversarial review of uncommitted changes, a branch or a PR, with BLOCKER/IMPORTANT/NIT
  findings and a verdict. Use when changes are implemented and about to be committed. Not the
  cross-provider review gate (use `cross-model-review` for that).
metadata:
  category: preference

---

# Code Review

Adversarial, structured code review of a diff.

## When to use

- After implementing a feature or fix, before committing
- When reviewing someone else's changes
- When the cross-model review in AGENTS.md triggers (significant changes): this skill supplies the findings format

## Inputs — resolve the scope, then fingerprint it

Explicit user scope always wins. Otherwise:

1. **Uncommitted changes** (default): staged + unstaged + *selected* untracked files
2. **Branch comparison**: every commit on this branch since its real base
3. **Specific files**: when the user names files or paths
4. **PR review**: when given a PR number, URL, or patch (availability depends on tool/environment)

### Resolve the actual base

Never hard-code `main`. Resolve it, in this order, and say which step answered:

```bash
# 1. An explicit target always wins: the PR's base branch, or the branch the user named.
BASE="${REVIEW_BASE:-}"
# 2. The repository's default branch.
[ -n "$BASE" ] || BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || true
# 3. Last resort: a conventional name that actually exists.
[ -n "$BASE" ] || BASE=$(git rev-parse --verify -q --abbrev-ref main ||
                         git rev-parse --verify -q --abbrev-ref master) || true
# 4. Nothing resolved — ask, never guess.
[ -n "$BASE" ] || { echo "no base branch resolved — ask the user which one to diff against"; exit 1; }
MERGE_BASE=$(git merge-base "$BASE" HEAD)
```

**Do not use `@{upstream}`.** On a feature branch it is almost always `origin/<same-branch>`,
the pushed copy of the branch under review, not the merge target. Once the branch is pushed,
`git merge-base '@{upstream}' HEAD` lands on the pushed tip and every pushed commit silently
drops out of the review. Treat an upstream as the base only when it is provably the merge
target, which is what step 1 is for. A hard-coded `main...HEAD` reviews the wrong commits just
as quietly in a repo based on `develop`, and breaks on a detached HEAD. Step 4 fails loudly on
purpose: when nothing resolves, ask.

### Select untracked files deliberately

```bash
git ls-files --others --exclude-standard
```

**Never sweep the whole list into the review.** Untracked space is the user's scratch area:
`.env` files and credentials, unrelated experiments, large binaries, another agent's in-flight
work. Pick the files that belong to the change under review, name them in the scope line, and
leave the rest alone. When relevance is unclear, ask.

### Record the scope

Announce before reviewing — and store this with any persisted record of the review:

- the resolved base, which step resolved it, base SHA and head SHA
- counts: committed / staged / unstaged / untracked-selected
- a deterministic fingerprint of exactly the content reviewed

```bash
# SELECTED = newline-separated list of the untracked files you chose (may be empty)
{
  printf 'base %s\nhead %s\n' "$MERGE_BASE" "$(git rev-parse HEAD)"
  git diff "$MERGE_BASE"...HEAD          # committed
  git diff --cached                      # staged
  git diff                               # unstaged
  printf '%s\n' "$SELECTED" | sort | while IFS= read -r f; do
    [ -n "$f" ] && printf '%s  %s\n' "$(git hash-object -- "$f")" "$f"
  done
} | git hash-object --stdin
```

Emit only the parts your resolved scope actually covers, always in that order, so the same
scope yields the same fingerprint. For a **named-file scope** (input 3), append `-- <paths>` to
all three `git diff` calls and list only those files in `SELECTED`; otherwise an unrelated edit
elsewhere in the live checkout changes the fingerprint of a review that never looked at it.
`git hash-object` is the hash because git is already a hard dependency: `sha256sum` is absent on
macOS and `shasum` on some minimal Linux images. It answers "did the reviewed content move", and
is not a security hash.

## Review process

### Step 1: Understand intent

Read the commit messages or PR description, or ask the user. Identify the category (feature,
bug fix, refactor, config change, dependency update) and the expected behavior change.

### Step 2: Read the diff carefully

Read every changed file. For each change, understand what the code did before and what it does
now, check that the change is complete (no half-done refactor, no orphaned reference), and read
the surrounding code rather than the lines in isolation.

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

Each finding has a severity, a location (file path + line or function), what is wrong, why it
matters (the consequence if not fixed) and a concrete fix, not "consider improving this".
The format is below.

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

This skill structures a review inside one session. It does **not** satisfy the mandatory cross-model review gate in AGENTS.md for significant changes. That gate requires a reviewer on a different model provider (by served model, not harness), for example an OpenAI-served reviewer for Anthropic-produced work. Use this skill's findings format in the review prompt for same-provider and cross-model reviews; `cross-model-review` covers how to invoke the second provider.

## Boundary with other skills

- **`collab`**: use for multi-agent design convergence. This skill reviews diffs/changesets, not architectural positions.
- **`scope`**: use before implementation to plan. This skill runs after implementation to verify.

## Rules

- **Be adversarial.** Your job is to find problems, not confirm the code works.
- **Be specific.** "This could be improved" is not a finding. Say what's wrong, where, and how to fix it.
- **Be honest.** "No findings" is a valid and respectable outcome. Don't manufacture nits to look thorough.
- **No false positives.** Every finding must have a concrete consequence. A style preference is a NIT, never IMPORTANT or BLOCKER.
- **Check callers.** Renamed a function? Changed a return type? Added a required param? `grep` for all references.
- **Read surrounding code.** A change that looks fine in isolation may break invariants in context.
- **Don't rewrite.** You're reviewing, not reimplementing. Suggest fixes, don't produce alternative implementations unless asked.
