---
name: quiz-diff
description: |
  Quiz the human on a diff to fight comprehension debt, then teach only the
  gaps. Use when the user says "quiz me on the diff/changes", before a PR of
  a large AI-built feature, or after a large-feature phase. Tests the human's
  understanding with free-response questions (program model, rationale,
  failure modes), grades honestly, teaches what was missed, and persists a
  fingerprinted gap record. Advisory — never blocks.
---

# Quiz Diff

Test the **human's** understanding of a diff — the inverse of code review.
Code review asks "is the code right?"; quiz-diff asks "does the human hold a
correct mental model of it?" AI-assisted work erodes that model silently
("comprehension debt"): tests stay green while understanding decays.

Evidence base: retrieval practice beats passive explanation; pretesting (answer
first, corrective feedback after) improves encoding; real comprehension spans a
program model (control/data flow) AND a situation model (rationale/goals)
(Pennington). Developers who only delegate score far lower on comprehension
than those who engage conceptually.

Prior art acknowledged: `Ciucky/no-numb` (session-gating quiz plugin, last-turn
scope, MCQ), `RonaldSit/comprehension-debt` (own-words repay/confirm CLI).
This skill differs deliberately: finished branch/PR scope, advisory not gated,
free-response with evidence-validated grading, fingerprinted gap records.

## Hard rules

1. **Quiz before explaining.** Never summarize or walk through the diff before
   the questions — pretesting only works if the attempt comes first.
2. **Free response by default.** No multiple choice unless the user asks for
   "quick mode" — MCQ tests recognition and cues answers. Short typed answers
   reveal real gaps.
3. **Validate every question before asking it** (see Item validation). A
   question you cannot ground in evidence is a question you must not ask.
4. **Lock all answers before teaching.** Collect answers to every question
   first; explanations for Q1 must not leak answers to Q2.
5. **"I don't know" is a first-class answer** — route straight to teaching,
   never shame.
6. **Advisory, never blocking.** Report the outcome; do not gate commits,
   pushes, or PRs on it.
7. **Honest claims only.** A pass does not prove understanding; say "no gaps
   surfaced", not "understanding verified". Call it "the selected diff", not
   "AI-written code" (provenance is usually mixed).

## Flow

### 1. Resolve scope — announce before asking

Default (pre-PR ritual): merge-base of the target branch through the current
worktree — committed + staged + unstaged + untracked. Resolve the target from
the configured/upstream default branch (`git symbolic-ref refs/remotes/origin/HEAD`,
fall back `main`/`master`); never hard-code. Explicit user scope always wins
(staged-only, last N commits, a phase's recorded range, named files).

Announce: resolved base, endpoints (SHAs), file count. Capture `base SHA`,
`head SHA`, and a diff hash (`git diff <base>...<head> | sha256sum`) for the
gap record.

Skip only mechanically-recognizable noise: whitespace/formatting-only,
typo-only, generated artifacts, pure version bumps. Do NOT auto-exempt tests,
docs, or config — tests encode contracts and mocks; config carries
consequential decisions. A zero-question result is legitimate when no valid
item exists — say so and stop.

### 2. Select at most 3 concepts by semantic risk

Read the changed code PLUS relevant unchanged context (callers, types, config,
tests) — never reason from the patch alone. Rank candidate concepts by
semantic impact: blast radius, boundary behavior, security/data effects,
novelty, undocumented rationale. Complexity is one signal, not the ranking —
a one-line auth default or timeout change can outrank a dense helper.

### 3. Build an internal item spec per question (do not show it)

For each question, record before asking:
- the construct tested (which concept, which model — program / situation / transfer)
- expected answer + accepted variants
- evidence that uniquely determines the answer (file:line at CURRENT revision)
- the likely misconception the question probes

**Item validation gate:**
- Behavior questions: evidence must uniquely determine the answer.
- Rationale questions ONLY when the rationale is on record (request, ADR,
  comment, test name, session context). Otherwise ask "what trade-off does
  this implementation make?" and accept multiple defensible answers.
- Reject ambiguous items; replace or drop them.

### 4. Ask — one at a time, three-question default shape

1. **Program model**: predict/trace actual control or data flow
   ("Given X empty, what executes and what is returned?")
2. **Situation model**: explain a supported trade-off or design constraint
   ("What does this approach trade away vs the obvious alternative?")
3. **Transfer**: predict a failure, boundary, or maintenance consequence
   ("What silently breaks if Y is removed/changed?")

2 questions for a single small concept; 4 for a genuinely multi-concept diff;
5 only on explicit "deep mode". Never pad. No hints, no citations in the
question stem (they leak answers — cite in the teaching phase).

### 5. Grade against the stored rubric

Four outcomes per answer: `correct | partial | incorrect | invalid`.
`invalid` = the user challenged the question and the challenge holds (evidence
ambiguous, question wrong) — treat as a defect in the quiz, not a miss.
Re-check challenged items against the code before ruling.

### 6. Teach only the gaps

For each `partial`/`incorrect`: a focused, line-cited walkthrough at the
current revision of exactly what was missed — misconception first, then the
evidence. When useful, offer a tiny executable check (a command or micro-test
that demonstrates the behavior). Do not re-explain what was answered correctly.

### 7. Persist a fingerprinted gap record

Append to `.local/comprehension/log.jsonl` (`.local/` is gitignored), one JSON
object per run:

```json
{"ts": "<ISO>", "branch_label": "<sanitized>", "base": "<sha>", "head": "<sha>",
 "diff_hash": "<sha256>", "concepts": ["..."],
 "items": [{"construct": "...", "outcome": "correct|partial|incorrect|invalid",
            "challenged": false, "evidence": ["file:line"]}],
 "gaps": ["one-line descriptions of what was missed"]}
```

Mark prior entries stale when their diff fingerprint no longer matches. Do not
store the user's raw answers. On a later run in the same repo, glance at prior
gaps — if one resurfaces as a fresh miss, say so (recurring gap = highest-value
teaching target). No spaced-repetition claims in v1.

## Output shape (after teaching)

- Scope line (base..head, N files)
- Per question: construct → outcome (one line each)
- Gaps taught (or "no gaps surfaced")
- One-line pointer: recurring gaps from prior runs, if any

## Anti-patterns

- Trivia (variable names, line numbers, syntax) — decision-level only
- Padding to a question count when the diff holds fewer real concepts
- Explaining the diff first, quizzing second
- Treating a challenged question as a user failure
- Claiming the quiz "proves" or "verifies" understanding
- Gating anything on the result
