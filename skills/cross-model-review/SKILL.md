---
name: cross-model-review
description: >
  How to get a second model provider onto a problem: classify the producer by its served
  model, pick a reviewer seat on another provider, ae routing, write-denied profiles, CLI
  invocations, prompt templates. Use when requesting a cross-model review or second opinion,
  or when a commit is gated on one. Covers HOW to invoke — the policy on WHEN it is mandatory
  stays in AGENTS.md. Not a reviewer itself: use `code-review` or `security-review` to review
  code yourself.
metadata:
  category: preference

---

# Cross-model review — invocation mechanics

A single model has predictable blind spots. The gate is satisfied by **provider diversity of
the served model**, never by a different harness. Run in the **same repository directory** for
full codebase access.

## Step 1 — classify the producer by served provider

Classify the model that produced the work, not the CLI it ran in:

| Served model | Provider |
|---|---|
| `fable*`, `opus*`, `sonnet*`, `haiku*`, `claude*` | Anthropic |
| `gpt-*`, `codex-*` | OpenAI |
| `grok-*` | xAI |
| `gemini-*` (Antigravity / `agy`) | Google |
| anything else | declare it explicitly |

Harness-mutable profiles carry no provider of their own. OpenCode serving
`github-copilot/claude-opus-5` is **Anthropic**, and must be reviewed by OpenAI, xAI or Google —
routing it to Codex because "it isn't Claude Code" does not satisfy the gate. OpenCode serving
`openrouter/z-ai/glm-5.3-flash` is Z.AI. When a profile's upstream is not obvious from its name,
state the active provider/model before choosing a reviewer, or ask the seat to declare it.

Then pick a reviewer whose provider differs from the producer's. Provider first, task fitness
second, cost third.

## Step 2 — inside an ae session, route through ae (STRONG RULE)

Use an existing ae agent on a different provider, or spawn one. Helpers are not on `PATH`;
invoke them by their full session path:

```bash
/Users/ckriech/.ae/sessions/<session>/review <agent> "<review request>"   # critical review, requires a reply
/Users/ckriech/.ae/sessions/<session>/ask <agent> "<question>"            # question, requires a reply
/Users/ckriech/.ae/sessions/<session>/spawn <name> --using <profile> "<briefing>"
/Users/ckriech/.ae/sessions/<session>/retire <name>                       # you spawned it, you retire it
```

Reviewer seats are **write-denied profiles** — use these rather than a build profile so a
reviewer cannot mutate the checkout it is reading:

| Profile | Provider | How writes are denied |
|---|---|---|
| `gpt56sol-review` | OpenAI | Codex sandbox `-s read-only -a never` — built-in writes only, see gap below |
| `gpt6astra-review` | OpenAI | Codex sandbox `-s read-only -a never` — built-in writes only, see gap below |
| `fable5-review` | Anthropic | `--restricted --strict-mcp-config`, Edit/Write/NotebookEdit disallowed, no Bash |
| `opus5-review` | Anthropic | `--restricted --strict-mcp-config`, Edit/Write/NotebookEdit disallowed, no Bash |
| `grok46-review` | xAI | `--sandbox read-only` |

All five were write-denial canary-tested on 2026-09-07. Confirm the profile still exists in
`~/.ae/config` before naming it. If it does not, pick a **different write-denied profile** on an
eligible provider — never the plain build profile of the same name. A write-capable reviewer can
mutate the live checkout it was asked to read, which is exactly what these seats exist to
prevent. If no write-denied profile on an eligible provider is available, say so: the mandatory
gate stays OPEN and nothing is committed unless the user explicitly waives it.

⚠️ **Known gap on the Codex seats.** The Codex `-s read-only` sandbox covers the model's
built-in filesystem tools. It does **not** disable write-capable tools reached through a
configured MCP server — an MCP server with an edit or shell tool in scope can still mutate the
checkout. The Claude seats close this with `--strict-mcp-config`; the Codex seats have no
equivalent. Read the Codex column as **built-in writes denied**, not as read-only, and keep
write-capable MCP servers out of a reviewer's config rather than relying on the sandbox flag.

The Claude review seats have no Bash and no MCP, so the **producer** writes the diff for them
to read:

```bash
git diff <base>...HEAD > .local/review/<id>.diff   # producer writes; reviewer only Reads
```

Do NOT shell out to another CLI (`codex exec`, `claude -p`, `grok -p`) and do NOT use your
harness's internal subagents for cross-model review. ae agents are visible to the human (own
pane), steward-monitored, and messageable; CLI and internal runs are invisible to everyone but
you. The CLI forms below are for NON-ae contexts only.

If no seat on a different provider is available, say so plainly. The mandatory gate stays OPEN
and nothing is committed unless the user explicitly waives it.

## Outside ae — CLI invocation

These forms are for non-ae contexts only. Pick them by the *provider you need*, not by the tool
you happen to be running in — an OpenCode session already serving an Anthropic model calls Codex,
and a Claude Code session reviewing OpenAI-produced work calls Claude.

**Need an OpenAI reviewer → Codex:**

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

**Need an Anthropic reviewer → Claude:**

```bash
CLAUDECODE= CLAUDE_CODE_SESSION= claude -p --restricted --strict-mcp-config \
  --disallowedTools Edit,Write,NotebookEdit -- "<PROMPT>" > .local/<output>.md
```

⚠️ `--allowedTools` is a preapproval list, not a sandbox: it suppresses prompts for the tools
named, it does not deny the others. Denying the write tools (`--disallowedTools`) plus
`--strict-mcp-config` is what actually keeps a reviewer read-only — an MCP server left in scope
can write even when Edit and Write are gone. Never pair `--permission-mode bypassPermissions`
with unrestricted `Bash` and call the run read-only. For research or debugging that genuinely
needs to write, grant it deliberately and run in an isolated worktree.

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

Record the reviewer's provider and profile in the verdict line, so a later reader can check the
diversity gate was met rather than take it on trust:

```
gate: OpenAI/gpt56sol-review PASS
gate: Anthropic/opus5-review BLOCKER x1, IMPORTANT x2
```

- **BLOCKER** → must fix, no exceptions
- **IMPORTANT** → fix unless you have explicit reasoning why not
- **NIT** → apply if quick and sensible, otherwise skip

Disagree with sound reasoning, not to save effort. When you disagree, verify the reviewer's
claim yourself and say what you measured — a reviewer's proposed fix can be wrong even when
the finding is right.

**Fixes go back to the same reviewer.** Send the focused recheck to the seat that raised the
findings — it already holds the context, and a fresh reviewer restarts the whole review. Give it
the diff of the fixes plus a per-finding disposition (fixed / disputed with reasoning / deferred),
not the whole change again.

**A verdict is not itself reviewable work.** Do not gate a review on a second review, and do not
route the reviewer's report to a third provider to adjudicate it. The producer weighs the
findings and decides; an unresolved disagreement goes to the human, not to another model.
