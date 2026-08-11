---
name: cross-model-review
description: >
  How to get a second AI model family onto a problem: ae routing rules, exact CLI invocations,
  prompt templates for review / plan critique / research, artifact conventions. Use when
  requesting a cross-model review or second opinion, or when a commit is gated on one. Covers
  HOW to invoke — the policy on WHEN it is mandatory stays in AGENTS.md. Not a reviewer itself:
  use `code-review` or `security-review` to review code yourself.
---

# Cross-model review — invocation mechanics

A single model has predictable blind spots. If you are Claude, call Codex. If you are Codex,
call Claude. If you are Gemini/Antigravity or Grok, call either. The value is model diversity,
not the specific tool. Run in the **same repository directory** for full codebase access.

## Inside an ae session — route through ae (STRONG RULE)

Use an existing ae agent of a different model family, or spawn one:

```bash
.../ask <agent> "<review request>"        # requires a reply
.../review <agent> "<review request>"     # critical review
.../spawn <alias>:reviewer "<briefing>"   # no suitable agent exists yet
```

Do NOT shell out to another CLI (`codex exec`, `claude -p`, `grok -p`) and do NOT use your
harness's internal subagents for cross-model review. ae agents are visible to the human (own
pane), steward-monitored, and messageable; CLI and internal runs are invisible to everyone but
you. The CLI forms below are for NON-ae contexts only.

## Outside ae — CLI invocation

**From Claude Code, OpenCode, Antigravity, Grok, or any non-OpenAI tool → call Codex:**

```bash
# Review / read-only analysis (the default — reviews need NO write access;
# the CLI writes the -o file outside the sandbox):
codex exec -o .local/<output>.md "<PROMPT>"

# ONLY when codex must apply changes itself — never concurrently with another
# agent editing the same checkout (one writer per file); prefer an isolated
# git worktree for this:
codex exec --full-auto -o .local/<output>.md "<PROMPT>"
```

⚠️ `--full-auto` grants write+git access to the checkout it runs in. A reviewer invoked with it
can mutate uncommitted work (observed 2026-07-15: a review run reverted an in-flight fix and
deleted an untracked test to probe pre-fix behavior). Review invocations use the read-only
default, always.

For code review specifically, `codex review --uncommitted` is a useful shortcut when available.

**From Codex → call Claude:**

```bash
CLAUDECODE= CLAUDE_CODE_SESSION= claude -p --permission-mode bypassPermissions \
  --allowedTools Read Glob Grep Bash -- "<PROMPT>" > .local/<output>.md
```

`--allowedTools` above is a read-only default suitable for review. For research or debugging,
adjust tool access as needed.

## Prompt templates

Adapt the output filename and prompt to the task.

**Code review** (mandatory for significant changes — see AGENTS.md for the threshold):

```
Review these uncommitted changes critically and constructively.
Read AGENTS.md for project conventions before reviewing.
Intent: <what was changed and why>.
Assess: correctness, architectural consistency, missed references
or callers needing updates, edge cases, security implications.
Do not rubber-stamp. Be specific about issues found.

Output findings with BLOCKER/IMPORTANT/NIT severity.
If no issues found, state "No findings" explicitly.
Write to .local/cross-review.md.
```

**Plan critique** (recommended before implementing non-trivial plans):

```
Review the implementation plan in .local/plan.md critically.
Read AGENTS.md for project conventions.
Assess: Is the goal clear? Is the change surface complete? Are phases
independently verifiable? Are test gates concrete? Missing risks?

Output findings with BLOCKER/IMPORTANT/NIT severity.
If no issues found, state "No findings" explicitly.
Write to .local/plan-review.md.
```

**Research cross-validation** (recommended when stakes are high or you're unsure):

```
Cross-validate the following findings/conclusions: <summary>.
Check for factual errors, missing alternatives, outdated information,
or logical gaps. Verify key claims against the codebase and docs.

Write validated findings and corrections to .local/research.md.
```

## Artifacts

Cross-model output goes to `.local/` (gitignored, never committed). Ensure `.local/` is in the
repository's `.gitignore` before proceeding; add it if missing.

## Acting on the verdict

- **BLOCKER** → must fix, no exceptions
- **IMPORTANT** → fix unless you have explicit reasoning why not
- **NIT** → apply if quick and sensible, otherwise skip

Disagree with sound reasoning, not to save effort. When you disagree, verify the reviewer's
claim yourself and say what you measured — a reviewer's proposed fix can be wrong even when
the finding is right.
