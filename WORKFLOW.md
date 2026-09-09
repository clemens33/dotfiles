# Agentic Engineering Workflow

Operating doctrine for how to actually approach a task with an agent in this
repo. Sibling to `KNOWLEDGE.md` (field knowledge — what's true) and
`shared/AGENTS.md` (the contract rendered into every tool's global
instruction file — what to never do). This file answers *what to do*.

Synthesized from the practitioner shortlist in `KNOWLEDGE.md` §18
(References / Practitioner references) and stress-tested via the
`grill-with-docs` skill. Source tier discipline (`KNOWLEDGE.md` §3) applies.

---

## At a glance

Triage every task on three dimensions, take the worst. Bug-shaped work routes
through `diagnose` regardless of size. L work with high rigor reaches for the
`large-feature` skill. Cross-model review fires on its own dual-trigger,
decoupled from the bucket — and is satisfied only by a different model provider.

```mermaid
flowchart TD
    Task([Task]) --> BugCheck{Bug-shaped?}
    BugCheck -- yes --> Diag[diagnose skill loop<br/>reproduce → minimise → fix]
    BugCheck -- no --> Triage{"Triage:<br/>worst of effort × blast × uncertainty"}

    Triage -- low all 3 --> S["S — Small<br/>effort by seat policy<br/>agent runs test, eyeball diff<br/>direct main"]
    Triage -- medium worst --> M["M — Medium<br/>effort by seat policy<br/>inline outline<br/>full local validation<br/>read diff before commit"]
    Triage -- high any --> L["L — Large<br/>effort by seat policy<br/>plan + phased execution<br/>scope or equivalent written plan"]

    L -. high rigor / audit-relevant .-> Playbook["large-feature skill<br/>7-stage full-rigor playbook"]
    L -. multi-session / unattended .-> LR["Long-running overlay<br/>.local/session-state.md<br/>.local/agent-brief.md<br/>ae memo · ADRs in repo"]

    S --> Gate
    M --> Gate
    L --> Gate
    Playbook --> Gate
    LR --> Gate
    Diag --> Gate

    Gate{"Cross-model trigger?<br/>(a) hard to undo cheaply<br/>OR (b) agent made a decision"}
    Gate -- no --> Ship([Ship])
    Gate -- yes --> CMR{Already reviewed via<br/>different-provider path?}
    CMR -- yes --> Ship
    CMR -- no --> Review[Different-provider review<br/>ae review inside ae<br/>read-only CLI outside ae]
    Review --> Ship
```

The rest of this file is the detail: what each bucket mandates, when triggers
fire, what counts as "different model," and the universal principles that
apply to all buckets.

---

## Triage (do this first)

Score the task on three dimensions; **take the worst**.

| Dimension | Low | Medium | High |
|---|---|---|---|
| **Effort** — reasoning load | one obvious change | normal multi-step | hard reasoning / architecture |
| **Blast radius** — cost if wrong | revert in one command | PR review catches it | prod incident or design wrong-turn |
| **Uncertainty** — can you write a one-sentence "done" definition right now without hand-waving? | yes, clean sentence | partial / some unknowns | "we'll figure out…" |

Worst dimension → bucket. **File count is not a triage criterion** — it's an outcome.

### Special triage — bug-shaped work

If the task is "something is broken / regressing / failing": route through the **`diagnose` skill** regardless of size. The structured loop (reproduce → minimise → hypothesise → instrument → fix → regression-test) prevents the guess-and-check failure mode. After `diagnose` produces a fix, re-triage the fix itself for review needs.

---

## S — Small

Hashimoto's "outsource slam dunks." Stay in minimal-harness mode.

**Must:**
- Agent runs the relevant test / lint / type check
- You eyeball the diff before committing

**Settings:**
- Effort: follow the seat policy below; workers start at the vendor default.
- Skills: none forced; caveman-lite tone is enough
- Subagents: none
- Branch: direct main is fine (the "YOLO main" stance applies)

**Skip:** plans, `scope`, `/ultrareview`, cross-model — unless a trigger below fires.

---

## M — Medium

Skill-augmented single agent. Cherny's "always give Claude a way to verify."

**Must:**
- Brief inline outline in the prompt — one paragraph: what you're doing, what done looks like, how you'll know
- Agent runs full local validation (tests, lint, types — whatever the repo has)
- You read the diff before committing

**Settings:**
- Effort: follow the seat policy below; move worker effort only on measured outcome.
- Skills: domain skills as needed (load from a private overlay if applicable). Consider `code-review` after implementation for non-trivial diffs.
- Subagents: `Explore` for codebase recon *only if* the change surface is unclear
- Branch: feature branch + PR for shared repos; direct main for personal/dotfiles

**Trigger cross-model review per the rule below — not by default.**

---

## L — Large

Plan-first. Phased execution. Osmani's long-running-agents discipline.

**Must (only two):**
1. **Written plan first** — `scope` skill produces a phased plan with test gates *before* code. If `scope` feels heavy, write the equivalent to `.local/plan.md` by hand.
2. **Phased execution** — each phase ends green-or-stop. No "let me just finish this one more thing."

**Recommended before execution:**
- **Grill the plan** with the `grill-with-docs` skill (or a cross-model plan critique) — catches handwaves before they cost you code.
- **`to-issues`** if the work needs to be broken into independently-grabbable tracer-bullet slices (especially when handing off to another agent or a teammate).

**Use as needed (context-dependent):**
- **Subagent split** (planner / implementer / reviewer fan-out) if work parallelizes. Skip if you can hold the plan in your head.
- **Worktrees** if parallel tracks exist. Overkill for sequential phases.
- **ADR** if a real design decision was made (genuine alternatives, hard to reverse, surprising without context). Rare.
- **`arch-docs` update** if the change touches the living architecture (new module, new boundary, new invariant). Not for every L task.

**Settings:**
- Effort: judgment seats use `xhigh`; builders follow the vendor-default policy below.
- Branch: feature branch minimum. Worktree if you need to context-switch.
- Commits: per-phase. Each phase = revertable unit.

**Full-rigor option:** for L features that are multi-session, multi-slice, high blast radius, audit-relevant, or need a defensible handoff, see the **`large-feature` skill** — a 7-stage playbook covering grill → plan+critique → vertical tracer-bullet slices → per-slice red-green-refactor with phase isolation → trigger-based drift checks → integrated review → separate architecture refactor cadence. Invoke via `/large-feature` or *"use the large-feature playbook."* The lean two-mandate L shape above remains the default; the skill is the opinionated deeper path.

---

## L → Long-running mode (overlay)

When an L task spans sessions or runs unsupervised, additional patterns apply. This is the Osmani / Hashimoto long-running-agents territory — and where the multi-agent `ae` workspace shines.

**Must (additional) — repo-visible state is primary:**
- **Session-state file** in `.local/session-state.md` capturing what's done, what's in-flight, what's next. Updated at the end of each session, read at the start of the next. (`.local/` is gitignored but repo-visible.)
- **Initializer brief** in `.local/agent-brief.md` the next session reads cold. (Matt Pocock's `triage`/`AGENT-BRIEF.md` pattern is the canonical shape.)
- **Workspace handoff** via `ae memo` for shared multi-agent context (`ae memo add --topic <topic> "<fact>"`).
- **Durable decisions** as ADRs in `docs/adr/` (or repo-visible equivalents). Code, plans, and decisions all live as repo files — that's the agent's memory per `shared/AGENTS.md`.

**Optional (tool-specific mirror, not primary):**
- `~/.claude/memory/` — Claude-only, not visible to Codex/OpenCode/Gemini, not versioned. Use only when (a) you're solo-on-Claude *and* (b) you want auto-memory's surfacing across unrelated sessions. Do not put anything load-bearing here that another tool would need to read.

**Recommended:**
- **`ae` multi-agent workspace** — use the session's full-path `spawn <name> --using <profile>` helper (for example `spawn reviewer --using gpt56sol-review`, if that profile is configured); served providers must differ. Use session `ask` / `review` helpers or the `collab` skill for auditable handoffs. See the cross-model review section below for how this satisfies the contract.
- **`zoom-out` skill** periodically — step back, look at the work in aggregate, check you're still on the plan. Especially after each phase merges.
- **Scheduled / unattended runs** via `/loop` (built-in to Claude Code) with an explicit max-iteration bound. Apply Ralph-loop discipline (`KNOWLEDGE.md` §17): mechanical work only, machine-verifiable completion criterion, hard iteration ceiling.

**Watch for:**
- Drift — the plan from one session may no longer match what's actually built later. Re-run `grill-with-docs` against the current state.
- Hidden state — anything load-bearing that lives in `~/.claude/memory/` and another tool needs to read. Promote to `.local/` or repo file.
- Unsupervised offensive operations — never. Defensive scanning/fixing only (`KNOWLEDGE.md` §8).

---

## Cross-model review (decoupled from bucket)

`shared/AGENTS.md` requires that significant changes be reviewed by **a
different AI architecture** — not just by another pane, another pass, or a
specialized skill running on the same model. Workflow keeps that invariant
strict and separates "review depth" from "cross-model satisfied."

### When to trigger

Run cross-model review if **either**:

- **(a) Hard to undo cheaply** — touches `shared/AGENTS.md`, `KNOWLEDGE.md`, `install.conf.yaml`, `claude/settings.json`, data contracts, public APIs, deps with transitive scope, license/attribution-sensitive content, anything that changes other agents' behavior.
- **(b) Agent made a decision** rather than mechanically derived it — *"I chose X over Y because…"* in the diff or commit message signals judgment, not derivation.

One trigger fires = one cross-model pass. Both fire on an L task = two passes (plan-level + diff-level).

### What satisfies the cross-model requirement (model diversity)

Only review by a **different model provider** than the producer counts. Classify the served model, not the harness: Anthropic, OpenAI, xAI, Google, or another verified provider. OpenCode and other mutable profiles must declare their upstream provider/model before they can gate work.

- **`ae review`** signoff from an agent serving a different provider — same-provider review does not count.
- **`collab` skill signoff** from a different-provider agent in the round.
- **Prior read-only CLI review outside ae** by a different provider on the same change.

### What does NOT satisfy cross-model (but is still valuable as "review depth")

These add review depth but stay on the same model — useful, but do not waive the cross-model requirement:

- **`/ultrareview`** — multi-pass review does not establish provider diversity. Follow with cross-provider review if the trigger fired and diversity is still unmet.
- **`security-review` / `gha-security-review` / Trail of Bits `fp-check`** — adds security-specific depth, same model.
- **`code-review` skill** — structured adversarial review, same model.

If you've used these, you've raised the quality bar — but you have not yet met the contract for substantial changes. Cross-model is the diversity check, these are the depth checks. Both matter, neither substitutes for the other.

### Invocation paths in this repo

Load the **`cross-model-review` skill** for routing, prompts, and artifact conventions. Inside ae, use the session's full-path `review`/`ask` helper and an eligible provider seat; never launch a reviewer CLI or internal subagent. Verify the served provider first and record it in the verdict (`gate: <provider>/<profile> PASS`).

Outside ae, reviewers use explicit read-only forms:

```bash
# Codex interactive review / analysis
codex -s read-only -a never
# Codex one-shot diff review
codex review --uncommitted -c sandbox_mode="read-only" -c approval_policy="never"
# Claude: no Bash or inherited MCP servers; give it a prepared diff artifact
claude --restricted --strict-mcp-config --disallowedTools Edit,Write,NotebookEdit
grok --sandbox read-only
muse --disable-write --disable-shell
```

Pick the provider before the harness. These permission forms do not themselves prove provider diversity.

---

## Effort level cheat sheet

| Harness / served model | Vendor default effort | Verification |
|---|---|---|
| Claude Code / Fable 5.1, Opus 5 | `high` | 2.1.263, 2026-09-07 |
| Codex / GPT-6 Astra | `medium` | 0.153.4 model catalog, 2026-09-07 |
| Codex / GPT-5.6 Sol | `low` | 0.153.4 model catalog, 2026-09-07 |
| Codex / GPT-5.6 Luna, Terra | `medium` | 0.153.4 model catalog, 2026-09-07 |
| Grok / Grok 4.6 | `high` | 1.0.13, 2026-09-07 |

**Clemens' defaults:** judgment seats (lead/colead and interactive use) use `xhigh`; builders/workers start at the vendor default and change that default only on measured outcome. Keep one effort per Astra thread: effort flips bust the prefix cache. Choose a new thread when a measured change calls for different effort.

For trivial mechanical work (typos, formatting, version bumps), any seat may choose `low`/`medium` per task; worker default changes still need measured outcomes, and Astra effort is chosen only at thread start. Claude `max` is session-only for the single hardest L phase; only `CLAUDE_CODE_EFFORT_LEVEL` persists it.

---

## Universal principles (every bucket)

1. **Verify your work** — Cherny's universal rule. If the agent can't run a check, declare the verification gap explicitly. No silent assumptions.
2. **Articulate before solving** — Hashimoto's "reproduce your own work" + Ronacher's "judgment, not abdication"; baked into the `diagnose` skill loop. If you can't state the problem in one sentence, you're not ready to fix it. Reproduce → describe → then act.
3. **Caveman-lite output** — `shared/AGENTS.md` rule #4. Drift back to verbose = drift back to slop.
4. **Source-tier your justifications** — `KNOWLEDGE.md` §3. Tier A/B drives, C/D suggests.
5. **Effort follows seat policy** — judgment defaults to `xhigh`; worker default changes need measured outcomes. Apply the trivial-work exception above, not a blanket task-bucket override.
6. **Don't abdicate judgment** — Ronacher. The agent does the typing, you do the thinking. Read every diff at S/M, every phase at L.
7. **Generated code is debt until validated** — Anthropic Trends Report. Test coverage caps real throughput.
8. **Stop at done** — once the requested outcome is verified and required findings are resolved, stop. One provider-diverse review per required gate, then one focused recheck of BLOCKER/IMPORTANT fixes; no new full pass after a clean verdict. No speculative edge cases or polish past diminishing returns. Required = BLOCKER/IMPORTANT per the severity contract; NIT stays apply-if-quick.

---

## Anti-patterns

**Triage:**
- Over-triaging to L because "this might be complex" — kills throughput
- Under-triaging to S because "I know this" when uncertainty is actually high — bypasses the plan that would have saved you
- Triaging by file count or estimated time — both are downstream, not input

**Process:**
- Forcing every worker to `xhigh` without measured quality gains
- Switching Astra effort mid-thread and losing the prefix cache
- Skipping the plan at L because "I get it now" — if you got it, the one-sentence done test would have made it M
- "Let me just finish this one more thing" mid-phase at L — abandoning the gates that made it L
- Spawning subagents on S work — overhead exceeds work
- Loading every skill into a subagent — preload cost compounds (see `skill-reducer`)

**Review:**
- Skipping cross-model on dual-trigger tasks because "this one's fine"
- Treating cross-model as a rubber stamp — "LGTM, ship it" without reading findings
- Running duplicate cross-model review when a different-provider pass already happened on the same change (`ae review` / `collab` signoff from a different provider, or a prior read-only CLI pass outside ae). Note: `/ultrareview` and same-model review skills add depth but do *not* satisfy the cross-model requirement — see the Cross-Model Review section.

**Long-running:**
- Unsupervised autonomous loops without max-iteration bounds
- Letting `~/.claude/memory/` calcify with stale exploration history
- Resuming a session without reading the session-state file you wrote
- Drift: running session 5 against the plan from session 1 without re-grilling

---

## Skill cross-reference

When the bucket says "use this," reach for these:

| Bucket / case | Skills |
|---|---|
| Any bug-shaped task | `diagnose` |
| M with non-trivial diff | `code-review` after implementation |
| L planning | `scope`, then `grill-with-docs` for plan validation |
| L → break into shareable issues | `to-issues` |
| L touching system structure | `arch-docs`, optionally `adr` |
| Architecture drift / should we refactor? | `refactor-audit` first (evidence + routing); then `improve-codebase-architecture` if structural work warranted; `zoom-out` for in-session reflection |
| Periodic reflection in long-running | `zoom-out` |
| Multi-agent collab + signoffs | `collab` |
| Security review | `security-review`, `gha-security-review` for workflows |
| Heavy skill files inflating subagent cost | `skill-reducer` |
| Output verbosity drift | `caveman` (`/caveman lite` / `full` / `ultra`) |

---

## Where this fits

- **`shared/AGENTS.md`** — the contract, rendered into every configured tool's global instruction file. Rules to never break (security, secrets, git commit hygiene, cross-model collaboration mandate). Those installed files are **generated**: editing one is pointless, the next `./install` overwrites it. Edit this file.
- **`KNOWLEDGE.md`** — the field knowledge. September 2026 refresh: models, mechanisms, source tiers, practitioner consensus.
- **`WORKFLOW.md`** (this file) — operating doctrine. How to actually approach a task: triage, bucket, execute.

If these three diverge, `shared/AGENTS.md` wins (it's the contract).

---

*Last updated: 2026-09-07 (vendor defaults, seat effort policy, read-only provider-diverse reviews, review cadence). Update as the workflow evolves.*
*This doc was iteratively grilled via the `grill-with-docs` skill, then cross-model reviewed by codex:coworker via `ae review` per its own dual-trigger rule (touches shared agent behavior + embeds judgment calls). Findings applied before commit.*
