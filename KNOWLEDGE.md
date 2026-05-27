# Agentic Coding Engineering — Research Base

> Cross-validated across Claude (Opus 4.7) and Codex (GPT-5.5), April 2026.
> This document captures the state of the art in agentic coding workflows,
> tooling, and best practices. Living document — update as the field evolves.
> Source-tiering applies to all citations (see §3).

## 1. Core Principle

**The biggest unlock in agentic coding is NOT the model — it's the workflow.**

The March 2026 thesis still holds at the headline: a strong workflow with a mid-tier model beats a weak workflow with the frontier model.

**April 2026 layered update**: frontier models (Opus 4.7, GPT-5.5) are now good enough at long autonomous execution that the bottleneck **shifted from "can the agent do it" to "can you trust and afford what it produced"**. The new pressure points:

- **Verification** — generated code is abundant, validated code is scarce
- **Budgets** — autonomy without spend caps invites runaway loops
- **Permissions** — broader autonomy = broader blast radius
- **Observability** — you can't review what you can't see
- **Source quality** — practitioner blogs proliferate; not all are signal
- **Review bandwidth** — limits multi-agent throughput, not agent count

Use Claude Code or Codex well before you build a "system." Don't over-engineer.

---

## 2. April 2026 Model-Era Update

> Dated section. Rotates as the field moves. Older facts archive to the changelog,
> not this section.

### Claude Opus 4.7 (released 2026-04-16) [A]

- New `xhigh` effort level — sits between `high` and `max`. Default for Opus 4.7 in Claude Code; recommended for coding/agentic work.
- **Adaptive thinking is the only supported thinking mode**. Manual `thinking.type: "enabled"` with `budget_tokens` is rejected with 400. Code that ported from 4.6 needs migration.
- Interleaved thinking (between tool calls) is automatically enabled in adaptive mode.
- `/ultrareview` slash command — multi-pass review for bugs, edge cases, security, logic errors. 3 free runs for Pro/Max users at launch.
- **Task budgets** (public beta, header `task-budgets-2026-03-13`) — full-agent-loop advisory budget. Distinct from hard `max_tokens`. In Claude Code: `/config task_budget 50000`. Min 20k; recommended 50k–128k.
- 1M context window included on Max/Team/Enterprise; `[1m]` suffix on aliases.
- New tokenizer; token counts and prompt-cache breakpoints are not directly comparable to 4.6.
- Stricter instruction following, better tool recovery, higher-resolution vision.

### OpenAI GPT-5.5 (released 2026-04-23) [A]

- Available in ChatGPT (Plus, Pro, Business, Enterprise), Codex CLI, and the API.
- Codex CLI: 400K context window. API: 1M context.
- Stronger coding, computer-use (78.7% OSWorld-Verified), and professional/scientific workflows.
- Fast mode tradeoff: faster responses with cost-per-token implications — only when latency matters.
- Codex GPT-5.5 access is gated by **ChatGPT auth, not API-key auth** at launch. API-key users default to GPT-5.4.
- "Trusted Access for Cyber" — gated program for security professionals; OpenAI's analogue to Project Glasswing.

### GPT-5.5 Pro caveat [A]

OpenAI's official GPT-5.5 release tables **do not publish coding benchmarks for GPT-5.5 Pro**. Pro is positioned for harder, higher-accuracy work (math, deep research) with parallel test-time compute. **Do not assume Pro is better for coding.** Default to standard GPT-5.5 / Codex unless local evals justify Pro-tier spend ($30/$180 per Mtok vs $5/$30).

### DeepSeek V4 (released 2026-04-24) [A]

- DeepSeek-V4-Pro (1.6T params, 49B activated) and DeepSeek-V4-Flash (284B / 13B). 1M context.
- MIT license, open weights on Hugging Face.
- OpenAI- and Anthropic-compatible APIs; integrations with Claude Code, OpenClaw, OpenCode.
- First-party benchmark claims (parity with Opus 4.7 / GPT-5.5 on SWE-bench, ~10–13× cheaper) need local validation before routing production work.

### Claude Mythos Preview / Project Glasswing (announced 2026-04-07) [A]

See §8 (Security Posture).

---

## 3. Source Tiers

All citations should be classified. Only Tier A and B drive normative repo guidance.

| Tier | Source class | Use |
|------|--------------|-----|
| **A** | Official vendor docs/releases, Linux Foundation announcements, model cards | Drives normative recommendations |
| **B** | Academic / peer-reviewed papers, first-party technical reports | Drives normative recommendations |
| **C** | Established practitioner essays, maintained reference repos | Cited as signals |
| **D** | Commercial blogs, benchmark aggregators, social media | Cited as signals only |

In this document: inline citations carry tier markers `[A]`, `[B]`, `[C]`, `[D]` where relevant. Treat unmarked claims as open for tier audit.

---

## 4. Verification-First Lifecycle

Generated code is abundant. **Validation is the bottleneck.** This shifts the operating model.

### Operating rules

1. **Significant tasks start with acceptance checks.** Define what "done" looks like before the agent generates.
2. **Agents must run or create executable verification where feasible** — tests, type checks, linters, smoke commands.
3. **If executable verification is not possible, the artifact must declare the verification gap explicitly.** No silent unverified output.
4. **Review artifacts preserve**: intent, diff, tests run, residual risk, source tier of claims relied upon.
5. **Review gates by change class**:
   - Trivial (typo, comment, formatting): inline self-check only
   - Single-file bug fix: agent self-test + human review
   - Feature / multi-file: `/ultrareview` (Claude Code) or Codex review + cross-model review
   - Architectural / security-relevant: cross-model review mandatory before merge

### Anti-patterns

- "It compiled, ship it" — compilation is necessary, not sufficient
- "I didn't run the tests because they're slow" — declare the gap; don't hide it
- Agent-generated tests for agent-generated code without human verification of test intent

---

## 5. Effort and Budget Routing

Higher effort is not free. Calibrate per task class.

### Effort routing

| Effort | Use for |
|--------|---------|
| `low` / no thinking | Shallow questions, recon (`grep`, `find`), formatting, tiny edits |
| `medium` | Normal questions, single-file edits, cost-sensitive workflows |
| `high` | Default for nontrivial work — bugs, refactors, design questions |
| `xhigh` (Opus 4.7) | Planning, hard bugs, architecture, security review, ambiguous migrations |
| `max` | Exceptional only. Session-scoped via Claude Code; persistent only via `CLAUDE_CODE_EFFORT_LEVEL` env var |

**Anti-pattern:** running `high` or `xhigh` for every interaction. Latency rises, token spend rises, quality plateaus or regresses (see brevity-constraint research [B]).

### Budget routing

- **Task budgets** (Opus 4.7 beta) — advisory full-loop budget. Set `/config task_budget 50000` for routine work, 100k–128k for long-running agentic loops. Below 20k, the model can't plan meaningfully.
- **`max_tokens`** — hard ceiling on a single response. Distinct from task budgets. At `xhigh` / `max` effort, watch for `stop_reason: "max_tokens"`.
- **GPT-5.5 Codex Fast / Priority** — only when latency materially matters; standard mode is the default.

### Cost-asymmetric orchestration

For multi-agent setups: capable orchestrator + cheap specialized workers. Reported 40–60% cost cuts vs all-frontier-model setups [D]. Verify locally.

---

## 6. Protocol / Infrastructure Governance

`AGENTS.md` and MCP have moved from convenience conventions to **governed infrastructure** under the Linux Foundation Agentic AI Foundation (AAIF, formed 2025-12-09) [A].

### AGENTS.md

- Remains the portable cross-tool repo contract.
- AAIF stewardship implies stability; backwards-compatible evolution is the norm.

### MCP servers — treat as dependencies, not plugins

When adding an MCP server to a project or user config, evaluate:

1. **Identity propagation** — does the server know which user/agent is calling? Is it logged?
2. **Allowlists** — what tools does it expose? Disable everything except what's needed.
3. **Credentials** — does it store secrets locally, or proxy to an auth service? Prefer credential proxies.
4. **Structured errors** — does it return machine-parseable errors, or stringly-typed prose?
5. **Timeouts** — does it have request timeouts? Default values?
6. **Audit logs** — can you reconstruct what the server did, after the fact?

If you can't answer all six, document the gap before installing.

### Anti-pattern

- Installing community MCP servers without scope review. The agent gets the union of all server capabilities; the user gets the union of all attack surfaces.

---

## 7. Architectural Tensions — Harness vs Minimal-Agent

The central architectural debate in agentic coding right now. Both camps have credible practitioners; neither has benchmark-validated dominance.

### Harness-heavy camp

Skills, agents, MCP servers, hooks, permissions, subagents. Claude Code, Codex, OpenCode, Gemini CLI all default to this. Anthropic's Opus 4.7 leans further into it (`/ultrareview`, task budgets, agent teams).

**Strengths**: observability, tool restriction, declarative governance, repeatable workflows, project-specific knowledge encoded in skills.

**Weaknesses**: harness baggage costs context; overhead grows with surface; complexity invites drift between agents.

### Minimal-agent camp

Small tool surface (read/write/edit/bash), short system prompts (<1k tokens), no MCP, no skills, no subagents. Pi (`badlogic/pi-mono` [C]) is the canonical implementation; powers OpenClaw [C].

**Argument**: frontier models are RL-trained as agents and already know what bash and files are. Adding tools adds tokens without adding capability. Models extend themselves by writing scripts when needed.

**Practitioner signals (Tier C)**:

- Mario Zechner (libGDX, Pi author) — talk: "Building pi in a World of Slop" [C]
- Armin Ronacher (Flask) — recent posts on Pi, agent psychosis, language design for agents [C]

**Caveats**: claims like "MCP wastes 7–9% of context" [C] are single-source measurements; OpenClaw star counts are social proof, not benchmark proof. Treat as architectural counterweight, not as proof minimal beats harness.

### Practical guidance

- Don't pick a side without context. Project-specific tribal knowledge (custom field IDs, namespace patterns, internal API conventions) is real value that skills encode and a minimal agent must re-derive each session.
- For greenfield personal coding, minimal-agent setups are credible.
- For multi-tool / team / domain-specific work, harness-heavy is currently better-tooled.
- The "right" answer is workload-specific. Do not assume one camp is universally correct.

---

## 8. Security Posture — Mythos / Glasswing

Anthropic's Claude Mythos Preview (announced 2026-04-07) [A] and OpenAI's "Trusted Access for Cyber" change the security landscape:

- **Public frontier ≠ actual frontier.** Vendors now openly hold back capability behind gated programs. The model you can buy is no longer the most capable model.
- **Defensive cyber capability and misuse capability rise together.** Mythos autonomously found thousands of zero-days across major OSes/browsers and exploited a 17-year-old FreeBSD NFS RCE [A].
- **Project Glasswing partners** (~12: AWS, Apple, Cisco, CrowdStrike, JPMorganChase, Linux Foundation, Microsoft, NVIDIA, Palo Alto Networks, etc.) get gated access for defensive security work [A].

### Repo guidance for AI agents in this repo

1. **No autonomous offensive security work.** Defensive scanning, fixing, triage only — and only with explicit scope.
2. **High-impact security actions require human authorization.** Audit log everything.
3. **Separate defensive scanning from exploit development.** They're different capability classes; don't conflate them in agent permissions.
4. **Treat MCP servers with security-relevant capability (network egress, credential access) as security-review dependencies.** See §6.

### Industry context — the maintainer / researcher reality (April 2026)

Vendor announcements show the offense+defense capability arc; practitioner reports show the operational shift on the ground. Cite together, not one without the other:

- **Thomas Ptacek** ([Decipher podcast][C], [Simon Willison summary][C]): AI-assisted vulnerability research is a real operational shift, not a demo. *"Vulnerability research is cooked"* — both as opportunity and as warning to the field.
- **Nicholas Carlini** ([InfoQ coverage][D]): concrete agentic vuln-discovery examples (Linux kernel, etc.), demonstrating the capability is generally available, not gated to Mythos partners.
- **Daniel Stenberg** ([Ars Technica][D]) — curl scrapped its bug bounty over AI-slop reports overrunning maintainers.
- **Greg Kroah-Hartman** ([Tom's Hardware][D]) — same kernel maintainer using local AI on Framework Desktop to *find* real bugs.

Both are true at once: AI is generating real maintainer review load (good and bad). Repo guidance should reflect this — neither dismiss agentic security tooling nor assume vendor demos generalize. See [§18 References / Practitioner references] for source links and tier markers.

---

## 9. Instruction File Landscape (April 2026)

Every AI coding tool reads a markdown config file. AAIF stewardship means `AGENTS.md` is the closest to a stable cross-tool standard.

| File | Tool(s) | Status |
|------|---------|--------|
| `AGENTS.md` | Codex (first-class), Cursor, Claude Code (fallback), most via convention | Closest to universal. AAIF-stewarded [A]. |
| `CLAUDE.md` | Claude Code | First-class, hierarchical (root→startup, subdirs→lazy). Also `~/.claude/CLAUDE.md` for global. |
| `GEMINI.md` | Gemini CLI | Hierarchical discovery similar to Codex. |
| `.cursor/rules/` | Cursor | Cursor-specific. |
| `copilot-instructions.md` | GitHub Copilot | In `.github/`. |

### Best practice

- **`AGENTS.md`** = single source of truth / universal cross-tool contract
- **`CLAUDE.md`** = Claude-specific operational tips (or symlink to `AGENTS.md` if content is identical)
- Tool-specific files only when they clearly pay off
- Keep under 200–300 lines each
- Focus on what agents would get wrong without the file
- NOT code snippets (go stale), NOT obvious facts inferable from `package.json`

---

## 10. Claude Code Feature Stack

> Schema fields below were correct as of 2026-04 docs. Verify against current
> docs (`code.claude.com/docs`) before relying on exact field names — feature
> surfaces evolve quickly.

### CLAUDE.md (deterministic — always loaded)

Global `~/.claude/CLAUDE.md`, project `./CLAUDE.md`, subdirs lazy. `CLAUDE.local.md` for personal prefs (gitignored). Keep under ~200 lines per file.

### Skills (`~/.claude/skills/*/SKILL.md` or `.claude/skills/`)

Reusable workflows. Lazy-loaded in main session on description match. Cross-tool compatible (also read by OpenCode at `~/.claude/skills/`). Disable model invocation with `disable-model-invocation: true` for side-effect workflows.

### Agents (`~/.claude/agents/*.md` or `.claude/agents/`)

Specialized subagents with own context, tools, model, permissions. Frontmatter fields exist for: `name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `mcpServers`, `hooks`, `maxTurns`, `skills`, `initialPrompt`, `memory`, `effort`, `background`, `isolation`, `color`. Verify exact set against current docs before authoring.

**Note**: Subagents do **not** inherit skills from the parent conversation. List them explicitly via `skills:`. Full skill content is preloaded eagerly.

### Hooks (`settings.json` — deterministic, always fire)

Events include `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `UserPromptSubmit`, `SubagentStart/Stop`, `SessionStart/End`. Exit code 2 = block (PreToolUse only). Common: auto-format on write, type-check, block edits on main, desktop notifications.

**Key distinction**: CLAUDE.md + hooks = deterministic. Skills + agents = probabilistic.

### `/ultrareview` (Opus 4.7, 2026-04) [A]

Multi-pass review command. Surfaces logic errors and state-management bugs that single-pass review misses. 3 free runs at launch for Pro/Max.

### Settings (`settings.json`)

Permissions (allow/deny with wildcards), hooks, model config, env. Global `~/.claude/settings.json`, project `.claude/settings.json`, personal `.claude/settings.local.json` (gitignored). Notable fields: `effortLevel`, `permissions.deny`, `permissions.defaultMode`, `enableAllProjectMcpServers`. Model config typically via `ANTHROPIC_MODEL` env var.

### Reference layout

```
~/.claude/
├── CLAUDE.md              # Global personal preferences
├── settings.json          # Global permissions, hooks
├── agents/                # Global agents
├── skills/                # Global skills
└── plugins/               # Installed plugins

project/
├── AGENTS.md              # Universal cross-tool contract
├── CLAUDE.md              # Claude-specific additions
├── .claude/
│   ├── settings.json      # Project hooks & permissions
│   ├── settings.local.json # Personal overrides (gitignored)
│   ├── agents/            # Project agents
│   ├── skills/            # Project skills
│   └── .mcp.json          # MCP server config
```

---

## 11. Codex CLI Configuration

> Audit local `~/.codex/config.toml` and current docs for current field names
> before changing — Codex configuration evolves quickly.

- Global instructions: `~/.codex/AGENTS.md`
- Config: `~/.codex/config.toml` — fields include `model`, `approval_policy`, `sandbox_mode`, `web_search`, `model_reasoning_effort`, `personality`, `tool_output_token_limit`. (Note: the field is `approval_policy`, not `approval_mode`.)
- Walks from project root to cwd, loading `AGENTS.md` at each level.
- `project_doc_fallback_filenames = ["CLAUDE.md"]` for projects without `AGENTS.md`.
- Does NOT read `CLAUDE.md` natively — only via fallback config.
- **Profiles** (`[profiles.<name>]`) for swappable presets — `review`, `quick`, `deep` patterns common.
- Power-user defaults: `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` for full YOLO; alternate is `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`.

### GPT-5.5 access caveat [A]

GPT-5.5 in Codex requires ChatGPT auth, not API-key auth, at launch. API-key users default to GPT-5.4. Verify your auth path before pinning.

---

## 12. Gemini CLI Configuration

- Global: `~/.gemini/GEMINI.md`
- Project: `GEMINI.md` at workspace root
- Subdirectory files discovered dynamically
- Subagents supported — `.gemini/agents/*.md` (project) or `~/.gemini/agents/` (user)
- Tool wildcards: `*`, `mcp_*`, `mcp_<server>_*`
- Extensions: `gemini extensions install <repo-url>`

---

## 13. Cross-Model Workflow

The single highest-value pattern across the field. Single model reviewing its own code = predictable blind spots. Two models > one. Biggest gain is 1→2, not 2→4.

**Workflow**:

1. **Plan** (one model, e.g., Claude Opus 4.7 with `/effort xhigh`) → `plans/{feature}.md`
2. **QA Review** (other model, e.g., Codex GPT-5.5) → adds findings, never rewrites
3. **Implement** (planner model, new session) → phase-by-phase with test gates
4. **Verify** (reviewer model) → checks implementation vs plan

**No native interop.** Shared filesystem + git. Separate agents reading the same `AGENTS.md`.

### P2 watchlist — "complementary models" claim

Single-source report [D] that GPT-5.5 executes plans best when Opus 4.7 wrote them. Interesting but not stable enough to enshrine as guidance. Watch for replication; current repo guidance remains symmetric cross-model review.

---

## 14. Session Management & tmux

### Tools

- `rusty-art/claude-tmux` — per-workspace sessions, auto-resume, `--list-all` [C]
- `MaxGhenis/tmux-claude-code` — search session transcripts by keyword [C]
- `timvw/tmux-assistant-resurrect` — persist/restore Claude+Codex+OpenCode across tmux restarts [C]
- `nielsgroen/claude-tmux` — TUI for managing multiple sessions with live preview [C]

### Claude Code native

- `--resume` / `--continue` reload history
- `/resume` to pick previous session
- `/rename` important sessions
- tmux keeps process alive (no resume needed on reattach)

---

## 15. Context Window

- Opus 4.7, Opus 4.6, and Sonnet 4.6: 1M tokens [A].
- **1M is a ceiling, not a recommended working size.** Coherence still degrades in sprawling sessions ("dumb zone" reports persist on Opus 4.7 as on 4.6).
- Manual `/compact at 50%` advice is firmly obsolete.
- `/clear` when switching to a genuinely different task.
- File-system memory should be **append-only, scoped, and periodically pruned**. Capture decisions, invariants, and handoffs — not transcripts or vague preferences.

---

## 16. Multi-Agent Patterns

### Good multi-agent

- Repo recon in parallel
- Test generation + implementation in separate branches
- Independent subsystems in separate worktrees
- Reviewer agent separate from writer (fresh context = no self-bias)

### Bad multi-agent

- Two agents editing same files
- Two agents on one mutable branch
- Complex coordinator before clean instructions/tests exist
- Multi-agent for ordinary bugfixes

### April 2026 update — review bandwidth as the bottleneck

The scaling limit is no longer "how many agents can I spawn" — it's "how fast can a human review what they produce." Practical implications:

- Plan agent ownership boundaries before spawning.
- Avoid shared files across parallel agents.
- Rule drift between agents causes inconsistent output; canonicalize via `AGENTS.md`.
- Use **agent-aware pre-merge review** — automated checks specifically for whether the agent's output respects repo conventions.

### Three reference patterns

1. **Subagents** — one orchestrator spawns children. Simplest. Use the Task tool / `Agent`.
2. **Agent Teams** — subagents + shared task list, peer messaging, file locks. Still maturing.
3. **Ralph Loop** — hard context reset each iteration; memory through git history.

### Specialized review fan-out

Parallel correctness / quality / security / architecture reviewers; synthesize into prioritized summary. Pairs naturally with `/ultrareview`.

---

## 17. Ralph Wiggum Loop

Official Claude Code plugin. Stop hook intercepts exit, re-feeds prompt until completion.

```
/plugin install ralph-wiggum@claude-plugins-official
/ralph-loop "Your task" --max-iterations 20 --completion-promise "DONE"
```

- Best for: batch refactors, migrations, test coverage — mechanical, machine-verifiable work
- NOT for: judgment-heavy work, UX, architecture
- Always set `--max-iterations`
- Also available natively as `/loop` (runs up to 3 days)
- Can run parallel Ralph loops across git worktrees

---

## 18. Repository References

> Source-tier markers `[A]/[B]/[C]/[D]` per §3. Tier A/B drives normative
> recommendations; C/D are signals only.

### Tier A — Official docs

- Claude Code docs — https://code.claude.com/docs/en/best-practices [A]
- Codex docs — https://developers.openai.com/codex/guides/agents-md [A]
- AGENTS.md spec — https://github.com/agentsmd/agents.md (AAIF stewardship) [A]
- `anthropics/skills` — https://github.com/anthropics/skills [A]
- `anthropics/claude-code` — https://github.com/anthropics/claude-code (includes ralph-wiggum plugin) [A]
- Anthropic Opus 4.7 — https://www.anthropic.com/news/claude-opus-4-7 [A]
- Anthropic Project Glasswing — https://www.anthropic.com/project/glasswing [A]
- Anthropic Mythos Preview — https://red.anthropic.com/2026/mythos-preview/ [A]
- Anthropic 2026 Agentic Coding Trends Report (PDF) — https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf [A]
- OpenAI GPT-5.5 — https://openai.com/index/introducing-gpt-5-5/ [A]
- DeepSeek V4 release — https://api-docs.deepseek.com/news/news260424 [A]
- Linux Foundation AAIF — https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation [A]
- OpenAI Codex team — "Unrolling the Codex Agent Loop" (engineering notes on agent loop) — https://openai.com/index/unrolling-the-codex-agent-loop/ [A]
- OpenAI Codex team — "Harness Engineering" (notes on harness design) — https://openai.com/index/harness-engineering/ [A]
- Anthropic / Claude.com — "Eight trends defining how software gets built in 2026" — https://claude.com/blog/eight-trends-defining-how-software-gets-built-in-2026 [A]
- Sourcegraph blog — "Why Sourcegraph and Amp are becoming independent companies" — https://sourcegraph.com/blog/why-sourcegraph-and-amp-are-becoming-independent-companies [A]
- Sourcegraph blog — "A new era for Sourcegraph: the intelligence layer for AI coding agents and developers" — https://sourcegraph.com/blog/a-new-era-for-sourcegraph-the-intelligence-layer-for-ai-coding-agents-and-developers [A]
- Pi documentation — https://pi.dev/docs/latest [A]

### Tier B — Academic / research

- "Rethinking Software Engineering for Agentic AI Systems" — arXiv:2604.10599 [B]
- "Dive into Claude Code architecture" — arXiv:2604.14228 [B]
- "Configuring Agentic AI Coding Tools" — arXiv:2602.14690 [B]
- "MCP production design patterns" — arXiv:2603.13417 [B]

### Tier C — Practitioner essays / repos

- **Pi-mono** (Mario Zechner, libGDX) — https://github.com/badlogic/pi-mono [C]
- **OpenClaw** — https://shittycodingagent.ai/ [C]
- **Mario Zechner — "Building pi in a World of Slop"** (talk) — https://www.youtube.com/watch?v=RjfbvDXpFls [C]
- **Mario Zechner — "What I learned building an opinionated and minimal coding agent"** — https://mariozechner.at/posts/2025-11-30-pi-coding-agent/ [C]
- **Armin Ronacher** (Flask, Jinja2) — https://lucumr.pocoo.org/ — minimal-agent camp signal; recent posts: "A Language For Agents" (2026-02), "Pi: The Minimal Agent Within OpenClaw" (2026-01), "Agent Psychosis" (2026-01), "Absurd In Production" (2026-04). [C]
- `shanraisshan/claude-code-best-practice` — reference implementation for skills/agents/hooks/cross-model. [C]
- `obra/superpowers` — agentic framework in Anthropic marketplace. [C]
- `trailofbits/claude-code-config` — security-pro reference: bypass-permissions + opinionated CLAUDE.md + hooks as "structured prompt injection at opportune times" + dropkit. [C]
- `philoserf/claude-code-setup` — clean ~/.claude/ reference. [C]
- `citypaul/.dotfiles` — agentic dotfiles structure. [C]
- `oh-my-pi` — Pi extended with LSP, browser, subagents. [C]
- **Simon Willison** — "Agentic Engineering Patterns" (validation loops, red/green TDD, cheap code, skilled operators) — https://simonwillison.net/2026/Feb/23/agentic-engineering-patterns/ [C]
- **Simon Willison** — coverage of Wilson Lin's "Scaling long-running autonomous coding" — https://simonwillison.net/2026/Jan/19/scaling-long-running-autonomous-coding/ [C]
- **Simon Willison** — coverage of Thomas Ptacek "Vulnerability research is cooked" — https://simonwillison.net/2026/Apr/3/vulnerability-research-is-cooked/ [C]
- **Armin Ronacher** — talks "AI Engineer" and "Leaning In To Find Out" (judgment, psychology, codebase structure, not abdicating to agents) — https://mitsuhiko.github.io/talks/ai-engineer-talk/ , https://mitsuhiko.github.io/talks/leaning-in-to-find-out/ [C]
- **Mitchell Hashimoto** (HashiCorp) — "My AI Adoption Journey" (pragmatic adoption, end-of-day agents, outsource slam dunks, harness engineering) — https://mitchellh.com/writing/my-ai-adoption-journey [C]
- **Addy Osmani** — "Long-running agents" (handoff, initializer agents, session state, production workflow design) — https://addyosmani.com/blog/long-running-agents/ [C]
- **DHH** (Basecamp / 37signals) — "Promoting AI agents" (supervised production collaboration, not pure vibe coding) — https://world.hey.com/dhh/promoting-ai-agents-3ee04945 [C]
- **Cagin Cecen** — "State of agentic coding (March 2026)" practitioner landscape snapshot — https://www.cagin.dev/writings/state-of-agentic-coding-march-2026 [C]
- **Steve Yegge** — Software Engineering Daily podcast on Gas Town / multi-agent mental models — https://softwareengineeringdaily.com/2026/02/12/gas-town-beads-and-the-rise-of-agentic-development-with-steve-yegge/ — *useful framing, but speculative and rhetorically hot; treat as watch-but-caveat* [C]
- **Decipher podcast** — "The Era of AI-led Vulnerability Research" with Tom Ptacek — https://podcasts.apple.com/us/podcast/the-era-of-ai-led-vulnerability-research-with-tom-ptacek/id1443911339?i=1000761109354 [C]

### Tier D — Commercial / aggregator

Cite as signals only. Audit periodically.

- BenchLM, MindStudio, Verdent, byteiota, TokenMix, Kilo blog posts on Opus 4.7 / GPT-5.5 [D]
- `awesome-agent-skills` and similar curated directories [D]
- VentureBeat — Boris Cherny / Claude Code workflow coverage — https://venturebeat.com/technology/the-creator-of-claude-code-just-revealed-his-workflow-and-developers-are [D]
- InfoQ — Carlini / Claude Code Linux vulnerability discovery — https://www.infoq.com/news/2026/04/claude-code-linux-vulnerability/ [D]
- Ars Technica — "Overrun with AI slop, curl scraps bug bounties" (Stenberg / maintainer-side reality) — https://arstechnica.com/security/2026/01/overrun-with-ai-slop-curl-scraps-bug-bounties-to-ensure-intact-mental-health/ [D]
- Tom's Hardware — Greg Kroah-Hartman using Framework Desktop + local AI to hunt kernel bugs — https://www.tomshardware.com/software/linux/linux-kernels-second-in-command-uses-framework-desktop-to-hunt-bugs-with-local-ai [D]
- TechCrunch — OpenClaw creator (Peter Steinberger) joins OpenAI — https://techcrunch.com/2026/02/15/openclaw-creator-joins-openai/ [D]

### Practitioner references

Core canon (highest-signal, recurring across multiple analyses):

- **Boris Cherny** (creator of Claude Code) — terminal-agent baseline and workflow mechanics; "always give Claude a way to verify its work." Caveat his strong "coding is solved" framing.
- **Andrej Karpathy** — coined "vibe coding" (2025); "agentic engineering" (2026).
- **Simon Willison** — public synthesis of agentic engineering patterns: validation loops, red/green TDD, cheap code, skilled operators. Aggregates and links to most other sources in this list.
- **Armin Ronacher** (Flask, Jinja2) — judgment, psychology, codebase structure, not abdicating to agents. Minimal-agent camp signal.
- **Mitchell Hashimoto** (HashiCorp founder) — pragmatic adoption journey: reproduce your own work, end-of-day agents, outsource slam dunks, harness engineering.
- **Addy Osmani** — production workflow patterns for long-running agents: handoff, initializer agents, session state.
- **Mario Zechner** (libGDX, Pi author) — minimal-harness camp: small core, visible context, extensibility, less hidden machinery.
- **Michael Bolin** and the OpenAI Codex team — first-party engineering notes on agent loop and harness design (see Tier A links).
- **Quinn Slack / Beyang Liu** (Sourcegraph / Amp) — large-codebase context, code intelligence, agent transparency.
- **Thomas Ptacek** — AI-assisted vulnerability research as a real operational shift, not a demo.
- **Nicholas Carlini** — concrete agentic vuln-discovery examples (Linux kernel, etc.).
- **Daniel Stenberg** (curl) and **Greg Kroah-Hartman** (Linux kernel) — maintainer-side reality: AI bug reports moved from slop noise to real review load. Important counter-balance to vendor narratives.

Watch but caveat (useful framing, less foundational):

- **DHH** (Basecamp / 37signals) — real company/product adoption; supervised production collaboration, not pure vibe coding. Industry context, not doctrine.
- **Steve Yegge** — multi-agent / Gas Town mental models. Useful framing, speculative and rhetorically hot.
- **Wilson Lin** — long-running autonomous coding swarm experiments. Provocative but needs brutal verification on real workloads.
- **Peter Steinberger** (OpenClaw, now at OpenAI) — important for personal agents beyond coding, but treat hype claims and security implications carefully.
- **Cagin Cecen** — practitioner landscape snapshots / tool selection. Useful periodic state-of-the-world reads.

---

## 19. Power User Settings

### Claude Code

- `--dangerously-skip-permissions` or alias `claude-yolo`
- Better: `/permissions` with wildcards: `Bash(npm run *)`, `Edit(/src/**)`
- `effortLevel` in `settings.json`: see §5 routing
- `xhigh` is the default on Opus 4.7; explicitly setting `high` *reduces* default thinking
- `/effort` mid-session, `--effort` on launch, `CLAUDE_CODE_EFFORT_LEVEL` env var for persistence (only way `max` persists)
- `/model` to switch mid-session
- `/clear` between unrelated tasks (rarely need `/compact` with 1M context)
- Esc Esc or `/rewind` to undo off-track work
- Subagents for large explorations → keeps main context clean
- `ultrathink` keyword for one-turn deeper reasoning without changing session effort
- `/ultrareview` at merge time
- Useful prompts: *"knowing everything you know now, scrap this and implement the elegant solution"*; *"grill me on these changes and don't make a PR until I pass your test"*

### Codex CLI

- `--full-auto` / `approval_policy = "on-request"` for safer default; `approval_policy = "never"` for full YOLO
- Strong for: review, second opinion, plan QA, bounded execution
- `codex resume <session-id>` for continuity
- Profiles for repeatable presets

---

## 20. Anti-Patterns

- No giant agent swarm — most tasks don't need orchestration
- No heavy conductor framework until pain justifies it
- No overinvestment in loop mechanics before instructions + tests are solid
- Don't rely only on chat — rules belong in files
- **Don't treat Tier C/D sources as authoritative** — the "X said Y" in a blog is signal, not fact
- Don't put code snippets in CLAUDE.md — they go stale; reference files instead
- Don't make CLAUDE.md a dumping ground — every line competes for attention
- Don't use multi-agent for ordinary bugfixes
- Don't run `xhigh`/`max` effort everywhere — it costs more without proportional quality gain
- Don't install MCP servers without §6 dependency-style review
- **Don't assume Pro = better** for any model. GPT-5.5 Pro is not proven better for coding [A].
- **Don't hide verification gaps** — if you can't run tests, declare that explicitly

---

*Last updated: 2026-05-04. Update this file as the field evolves.*
