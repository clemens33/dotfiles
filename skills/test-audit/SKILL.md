---
name: test-audit
description: |
  Audit test-suite QUALITY (not coverage) after heavy AI-agent work. Use when
  the user says "audit the tests", after a large feature lands, before
  release-hardening, or when refactor-audit routes here. Four evidence lanes:
  scoped mutation testing (Python/JS-TS/Rust), high-confidence bypass facts,
  gamed-test forensics, and a detached judge pass. Produces a triaged findings
  report with guardrail candidates. Advisory — never gates, never installs.
---

# Test Audit

Green tests are not evidence when the same agent wrote code, tests, and ran
them. This skill audits whether the suite would actually catch bugs: mutation
probes, bypass detection, weakening forensics, and an independent judge.
Coverage is a quantity signal and is out of scope (refactor-audit tracks it).

Prior art acknowledged: `Jott2121/crucible` (pytest+mutmut tester/critic loop —
its rule "kill/survive is the receipt, never ask the model if tests are good"
is adopted here), Jeremy Longshore's `audit-tests` gist (mutation + review;
its universal thresholds are deliberately NOT adopted), tsDetect/PyNose smell
taxonomies (precision lessons: automated smell detection has ~0.36 F-measure —
which is why contextual smells are review candidates here, never findings).

## Ground rules

1. **Mutants are probes, not proof.** A surviving mutant becomes a finding
   only after triage (see Lane 1). Equivalent mutants, no-coverage, timeouts,
   and tool errors are separate statuses — never collapse them into "weak test".
2. **Two evidence tiers.** High-confidence facts can be reported directly.
   Contextual smells are review candidates for the judge/human — a zero-assertion
   test may be a legitimate exception/snapshot/property test.
3. **No universal thresholds.** No assertion-density minimums, mock-count
   caps, or negative-test ratios. Counts do not establish oracle quality.
4. **Never modify anything.** No installs, no config edits, no cache deletion,
   no test changes. Audit only. Report side-effect artifacts the tools create.
5. **Advisory.** Findings route to fixes (tdd skill), structure work
   (improve-codebase-architecture), or guardrail promotion (refactor-audit).

## Scope resolution

Default: **merge-base of the target branch through the current worktree**,
including uncommitted and untracked test/CI/config files (same resolution as
quiz-diff; never hard-code `main`). Announce base, head, dirty-state, file
counts. Record a scope hash.

- Mutation targets = **changed production lines/modules**.
- Test-only diff → map changed tests to production modules via imports or
  existing coverage data; if ambiguous, ask for a named module.
- Deletion-only production change → target the surrounding module (no
  new-side lines exist to overlap).
- Explicit user scope (named modules, "whole suite forensics") always wins.

## Lane 1 — Scoped mutation testing (hard evidence, after triage)

**Preflight (mandatory, ~1 min):**
1. Detect stack + installed tool. Supported v1: `mutmut` (Python),
   StrykerJS (JS/TS), `cargo-mutants` (Rust). `pytest-gremlins` is an
   optional alpha adapter — only if already configured, never suggested as
   an install during an audit.
2. Capability-probe the tool version + project config *without changing
   either*. If the contract below can't be met → mark the lane
   **unavailable** with the reason, continue with other lanes.
3. Run the selected tests unmutated. Not green → stop this lane
   ("mutation on a red baseline is meaningless"), report.

**Per-tool scoping contract (these are NOT interchangeable):**

| Tool | Real interface | Use |
|---|---|---|
| StrykerJS | `--mutate <path>` / `--mutate <path>:<start>-<end>` (replaces configured mutate). `--incremental` is a cache, not a diff selector; first run is cold. | Generate changed-line `--mutate` args; note cold/warm cache in the report. |
| cargo-mutants | `--in-diff <file>` — needs a generated diff file; selects new-side overlapping mutants only; ignores test-only diffs; worktree must match new side. Exit codes 2–6 are distinct tool outcomes. | Generate merge-base→worktree diff to a temp file; map exit codes; module target for test-only/deletion cases. |
| mutmut (3.x) | **No diff/line flag.** Module/function scoping via `mutmut run "<module>*"`; config key is `source_paths` (3.6 rename). Probe can fail before help prints. | Call it module-scoped honestly; scope to changed modules. Artifacts land in `mutants/` — report, don't clean. |

**Budget:** default 5 minutes *after* preflight (interactive). A killed run =
**partial**: quick-mutant bias, score not comparable, cannot support strong
claims — say so explicitly.

**Report counts, not just a score:** attempted / valid / killed / survived /
no-coverage / timeout / error. Do **not** compare against a historical
whole-repo mutation score (different lines, operators, config = incomparable).
Optional stronger design when safe: run the same mutants against the *old*
tests vs *new* tests (differential).

**Survivor triage — required before a survivor becomes a finding:**
1. Baseline was green in the same environment.
2. Mutant actually ran (not no-coverage/timeout/error).
3. The mutation changes behavior required by a spec, issue, invariant, or
   stable public contract (else: possible equivalent mutant — record, drop).
4. The test that would kill it asserts *behavior*, not implementation detail.

Triaged survivors are the audit's strongest artifact: name the mutant, the
behavior it breaks, and the missing assertion.

## Lane 2 — High-confidence bypass facts (static, cheap, reportable)

- Focused/disabled tests: `.only` / `fit` / `fdescribe`, unconditional skip
- Literal no-ops: empty bodies, `assert True`, `assert x == x`
- Swallowed exceptions in test paths (`except: pass`, empty catch)
- **Collection integrity**: test discovery count dropped vs base;
  `--passWithNoTests`; suite "passes" with zero tests; CI `continue-on-error`
  added
- New exclusions in test/coverage/CI configuration
- Bulk snapshot/golden regeneration in the same change without review
- **Oracle coupling** (high-confidence subset only): expected value computed
  by calling the SUT or its helper

NOT in this tier (review candidates for Lane 4, never auto-findings):
zero-assertion tests, mocked SUT, assertion weakening, deleted tests,
reasoned skip/xfail, `sys.exit` in CLI tests, happy-path bias, assertion
count/roulette, near-duplicate tests. Note: hardcoded literal expected values
are usually a *good* independent oracle — never flag them as a smell.

## Lane 3 — Weakening forensics (git, behavior-tracked)

Scope: merge-base→worktree by default; deeper history only on request.
For each candidate, show **before/after** and check whether the behavior is
still tested elsewhere (renames/parameterization are not deletions):

- Assertion weakening diffs (`assertEquals` → `assertNotNull`, tightened →
  loosened matchers) — candidate, may be a corrected contract
- Deleted tests correlated with previously-failing runs
- New `xfail`/`skip` — higher confidence only when unconditional, reasonless,
  replacing an active relevant test, or xpass-without-strict
- Hermeticity/flakiness probes where the framework supports it cheaply:
  bounded repeat or order-shuffle on the changed tests; retries-added,
  time/network/randomness dependence

## Lane 4 — Detached judge (opinion, evidence-cited)

Spawn a **genuinely detached** reviewer — in an ae session, spawn/ask an ae
agent of a different model family (per AGENTS.md); otherwise a fresh-context
subagent. Give it only: the production diff, the tests, relevant requirements/
ADRs, and the Lane 2/3 review candidates. Anchor on the intended contract
("does this test pin the *required* behavior?"), not just sensitivity.
Judge output is an **opinion with cited evidence** — it can raise a review
candidate to a finding only together with Lane 1/2/3 evidence, never alone.

## Report

`.local/test-audit-<UTC-timestamp>-<scope-hash>.md`:

- Scope: base/head SHAs, dirty fingerprint, tool + version + config hash,
  test command, budget, completion state (complete/partial/unavailable lanes)
- Findings by severity, each with its evidence class (triaged survivor /
  bypass fact / forensic diff / judge opinion + corroboration)
- Review candidates left open (honest about what was NOT auto-judged)
- **Guardrail candidates** (refactor-audit promotion style): changed-line
  mutation check in CI, tests/-dir diff review gate, collection-count
  assertion, protected regression suite (a CODEOWNERS+branch-protection
  directory — call it that; a true holdout requires storage the agent cannot
  read, e.g. private CI, and is a governance decision, not a skill feature)
- Routing: fixes → tdd; structural test friction →
  improve-codebase-architecture; recurring signals → refactor-audit

## Anti-patterns

- Coverage worship; chasing 100% mutation score (ignore-comment gaming, cost)
- Full-suite mutation runs (budget explosion) — scoped only
- Auto-deleting "redundant" tests — minimization is unsafe without deep review
- Calling a survivor "proof" before triage; calling judge opinion a verdict
- Flagging literal expected values as a smell (inverted oracle logic)
- Installing or reconfiguring tools mid-audit
- Comparing mutation scores across different scopes/configs/versions
