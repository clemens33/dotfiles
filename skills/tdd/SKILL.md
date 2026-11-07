---
name: tdd
description: >
  Builds features or fixes bugs in vertical red-green-refactor slices, one
  failing test at a time. Use when the user asks for TDD, test-first development or
  integration-style tests, or names red-green-refactor. Not for finding the
  cause of a bug (use `diagnose`) or auditing existing tests (use
  `test-audit`).
license: MIT
source: https://github.com/mattpocock/skills/tree/main/skills/engineering/tdd
metadata:
  category: preference

---

# Test-Driven Development

## Philosophy

**Core principle**: Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs and describe _what_ the system does, not _how_. "User can checkout with valid cart" reads like a specification and survives refactors.

**Bad tests** are coupled to implementation: they mock internal collaborators, test private methods, or verify through external means (such as querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

Do not write all tests first, then all implementation ("horizontal slicing": RED = write all tests, GREEN = write all code). Tests written in bulk test _imagined_ behavior and the _shape_ of things (data structures, function signatures) instead of real behavior. They pass when behavior breaks and fail when it is fine.

Correct approach: vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### 1. Planning

When exploring the codebase, use the project's domain glossary so that test names and interface vocabulary match the project's language, and respect ADRs in the area you're touching.

Before writing any code, work from what is already settled (the request, existing public API, ADRs, domain glossary):

- [ ] Derive the needed interface change
- [ ] Rank the behaviors to test by blast radius, boundary behavior and complexity, and list them (behaviors, not implementation steps)
- [ ] Prefer deep modules (small interface, lots of implementation behind it: fewer methods, simpler parameters, more complexity hidden) and interfaces that are easy to test (accept dependencies instead of creating them, return results instead of producing side effects, keep the surface small)
- [ ] State the plan and proceed, unless an approval is genuinely still outstanding

Ask the user only what the available context does not already answer, and only when a different answer would change what you build or test — a public interface that is still genuinely open, or two behaviors you cannot rank from evidence. Otherwise state your assumption in one line and continue; do not re-ask a decision the request or the repo already settled.

**You can't test everything.** Focus testing effort on critical paths and complex logic, not every possible edge case.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet - proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior, through the public interface only

### 4. Refactor

After all tests pass, look for refactor candidates:

- Duplication → extract function/class
- Long methods → break into private helpers (keep tests on the public interface)
- Shallow modules → combine or deepen
- Feature envy → move logic to where the data lives
- Primitive obsession → introduce value objects
- Existing code the new code reveals as problematic

Apply SOLID principles where natural. Run tests after each refactor step. Never refactor while RED; get to GREEN first.
