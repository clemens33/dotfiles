---
name: cross-model-review
description: >
  Get a second model provider onto work: classify the producer by its served model, pick a
  write-denied reviewer on another provider, route through ae or run a read-only CLI, and reuse
  the prompt templates. Use when requesting a cross-model review or second opinion, or when a
  commit is gated on one. Not the policy on when review is mandatory (that stays in AGENTS.md)
  and not a reviewer itself (use `code-review` or `security-review`).
metadata:
  category: preference

---

# Cross-model review — invocation mechanics

The gate is satisfied by **provider diversity of the served model**, never by a different
harness. Run in the **same repository directory** for full codebase access.

## Step 1 — classify the producer by served provider

Classify the model that produced the work, not the CLI it ran in:

| Served model | Provider |
|---|---|
| `fable*`, `opus*`, `sonnet*`, `haiku*`, `claude*` | Anthropic |
| `gpt-*`, `codex-*` | OpenAI |
| `grok-*` | xAI |
| `gemini-*` (Antigravity / `agy`) | Google |
| `muse-*` (Muse Spark, Muse Wonder; native `muse` CLI) | Meta |
| anything else | declare it explicitly |

Meta contributor variants (Muse Spark/Wonder CONTRIBUTOR) train on input — never route MIC or customer content to them.

Harness-mutable profiles carry no provider of their own. OpenCode serving
`github-copilot/claude-opus-5` is **Anthropic** and needs an OpenAI, xAI or Google reviewer; a
harness name does not establish the provider. When a profile's upstream is not obvious from its
name, state the active provider/model before choosing a reviewer, or ask the seat to declare it.

Then pick a reviewer whose provider differs from the producer's. Provider first, task fitness
second, cost third.

## Step 2 — inside an ae session, route through ae

Use an existing ae agent on a different provider, or spawn one. Helpers are not on `PATH`;
invoke them by their full session path:

```bash
/Users/ckriech/.ae/sessions/<session>/review <agent> "<review request>"   # critical review, requires a reply
/Users/ckriech/.ae/sessions/<session>/ask <agent> "<question>"            # question, requires a reply
/Users/ckriech/.ae/sessions/<session>/spawn <name> --using <profile> "<briefing>"
/Users/ckriech/.ae/sessions/<session>/retire <name>                       # you spawned it, you retire it
```

A reviewer seat must **deny writes**, so it cannot mutate the checkout it reads. Choose a
profile on an eligible provider whose launch line in `~/.ae/config` shows the denial; never use
a build profile. The properties to look for:

- Codex: `-s read-only` — denies built-in writes only (see the gap below)
- Claude: `--restricted --strict-mcp-config`, Edit/Write/NotebookEdit disallowed, no Bash
- Grok: `--sandbox read-only`

Confirm the profile exists in `~/.ae/config` and carries the denial before naming it. A
same-named build profile does not count: a write-capable reviewer can mutate the live checkout
it was asked to read, which is exactly what these seats exist to prevent. If no write-denied
seat on a different provider is available, say so: the mandatory gate stays OPEN and nothing
is committed unless the user explicitly waives it. A write-denied seat can still author
acceptance tests under the spec-first rule: it supplies the frozen test content, and the driver
installs it byte-identically; authorship grants it no write access.

**Known gap on Codex seats.** `-s read-only` covers the model's built-in filesystem tools. It
does **not** disable write-capable tools reached through a configured MCP server: an MCP server
with an edit or shell tool in scope can still mutate the checkout. Claude seats close this with
`--strict-mcp-config`; Codex seats have no equivalent. Read a Codex seat as *built-in writes
denied*, not as read-only, and keep write-capable MCP servers out of a reviewer's config rather
than relying on the sandbox flag.

Claude review seats have no Bash and no MCP, so the **producer** writes the diff for them to
read:

```bash
git diff <base>...HEAD > .local/review/<id>.diff   # producer writes; reviewer only Reads
```

Do not shell out to another CLI (`codex exec`, `claude -p`, `grok -p`) and do not use your
harness's internal subagents for cross-model review. ae agents are visible to the human (own
pane), steward-monitored, and messageable; CLI and internal runs are invisible to everyone but
you. The CLI forms below are for non-ae contexts only.

## Outside ae — CLI invocation

Pick the form by the *provider you need*, not by the tool you are running in — an OpenCode
session already serving an Anthropic model calls Codex, and a Claude Code session reviewing
OpenAI-produced work calls Claude.

**Need an OpenAI reviewer → Codex:**

```bash
# Review / read-only analysis. Always pass the sandbox explicitly: the configured default can be
# danger-full-access (it is in this setup). The CLI writes the -o file itself, outside the sandbox.
codex exec -s read-only -c approval_policy="never" -o .local/<output>.md "<PROMPT>"

# ONLY when codex must apply changes itself — never concurrently with another
# agent editing the same checkout (one writer per file); prefer an isolated
# git worktree for this:
codex exec -s workspace-write -c approval_policy="never" -o .local/<output>.md "<PROMPT>"
```

A write-enabled sandbox grants write access to the checkout it runs in. A reviewer invoked
with it can mutate uncommitted work (observed: a review run reverted an in-flight fix and
deleted an untracked test to probe pre-fix behavior). Review invocations always pass
`-s read-only`; `codex exec` has no `-a` flag, so approval comes from the `-c` override.

For code review, `codex review -c sandbox_mode="read-only" -c approval_policy="never" --uncommitted`
is a shortcut when available. These overrides are untested on `codex review`; if the installed
version rejects them, use the `codex exec` form above with a review prompt.

**Need an Anthropic reviewer → Claude:**

```bash
CLAUDECODE= CLAUDE_CODE_SESSION= claude -p --restricted --strict-mcp-config \
  --disallowedTools Edit,Write,NotebookEdit -- "<PROMPT>" > .local/<output>.md
```

`--allowedTools` is a preapproval list, not a sandbox: it suppresses prompts for the tools
named, it does not deny the others. Denying the write tools (`--disallowedTools`) plus
`--strict-mcp-config` is what keeps a reviewer read-only — an MCP server left in scope can
write even when Edit and Write are gone. Never pair `--permission-mode bypassPermissions` with
unrestricted `Bash` and call the run read-only. For research or debugging that genuinely needs
to write, grant it deliberately and run in an isolated worktree.

## Prompt templates

Adapt the output filename and prompt to the task.

**Code review** (mandatory for significant changes — see AGENTS.md for the threshold):

```
Review these uncommitted changes critically and constructively.
Read AGENTS.md for project conventions before reviewing.
Intent: <what was changed and why>.
Form your first findings from the requirements, the standards and the diff BEFORE reading the producer's controls, conclusions or verdicts; then check those against your own findings.
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
gate: OpenAI/<write-denied-profile> PASS
gate: Anthropic/<write-denied-profile> BLOCKER x1, IMPORTANT x2
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
