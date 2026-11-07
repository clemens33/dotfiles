# Agentic Coding Engineering — Research Base

> Refreshed 2026-11-07 (November 2026 refresh): the pre-October model log is archived in
> `KNOWLEDGE-CHANGELOG.md`; §2 holds a current model table; §9–§12 were re-probed on the
> installed tool versions, with probed and inherited facts stamped separately; new
> practice, security and paper evidence was added (§4, §6, §8, §9, §13, §15, §17).
> Earlier refreshes: June 2026 (Claude Opus 4.8 and Codex GPT-5.5 cross-validation),
> July (three-source sweep: Claude web, agy, Grok X search), September (installed
> harness defaults, instruction and skill discovery, hooks reference), October 2026
> (5.5 generation, GPT-6 family, Muse Wonder; 2026-10-13).
> This document captures the state of the art in agentic coding workflows,
> tooling, and best practices. Living document — update as the field evolves.
> Source-tiering applies to all citations (see §3).

## 1. Core Principle

**The biggest unlock in agentic coding is NOT the model — it's the workflow.**

The March 2026 thesis still holds at the headline: a strong workflow with a mid-tier model beats a weak workflow with the frontier model.

**April 2026 layered update**: the frontier models of April 2026 were good enough at long autonomous execution that the bottleneck **shifted from "can the agent do it" to "can you trust and afford what it produced"**. The pressure points since then:

- **Verification** — generated code is abundant, validated code is scarce
- **Budgets** — autonomy without spend caps invites runaway loops
- **Permissions** — broader autonomy = broader blast radius
- **Observability** — you can't review what you can't see
- **Source quality** — practitioner blogs proliferate; not all are signal
- **Review bandwidth** — limits multi-agent throughput, not agent count

Use Claude Code or Codex well before you build a "system." Don't over-engineer.

---

## 2. Model-Era Update

> Dated section, state of 2026-11-07. It rotates as the field moves. Entries from
> September 2026 and older are archived verbatim in `KNOWLEDGE-CHANGELOG.md`.

### Current models

"API" values come from the vendor model page. "CLI" values come from the installed harness catalog (Codex 0.167.0, `codex debug models`, 2026-11-07). They differ for some models. `—` means a page was read and does not state the value. `unverified` means the value was looked for and not found. Prices are USD per million tokens, input / output. Tier markers follow §3.

| Model (ID) | Released | Price | Context / max output | Default effort | Cutoff | Source |
|---|---|---|---|---|---|---|
| Fable 5.1 (`claude-fable-5-1`) | 2026-09-01 | 10 / 50 | 1M / 128k | `high` | Jun 2026 | Anthropic model page [A] |
| Opus 5.5 (`claude-opus-5-5`) | 2026-09-22 | 4 / 20 | 1M / 128k | `medium` | Jun 2026 | Anthropic model page [A] |
| Sonnet 5.5 (`claude-sonnet-5-5`) | 2026-09-28 | 2 / 10 | 1M / 128k | `high` | Jun 2026 | Anthropic model page [A] |
| Haiku 5.5 (`claude-haiku-5-5`) | 2026-10-07 | 0.10 / 0.50 for prompts up to 100k tokens; 0.50 / 2.50 above | 1M / 128k | `medium` | Jun 2026 | Anthropic launch page; comparison table on the Fable 5.1 page [A] |
| Opus 5 (`claude-opus-5`), legacy | 2026-07-24 | 5 / 25 | 1M / 128k | `high` | May 2026 | archive; not re-checked [A] |
| GPT-6.1 Sol (`gpt-6.1-sol`) | 2026-09-29 | 2 / 10 | API 1.05M / 128k; CLI 500k window, 95% effective | API —; CLI `low` | Apr 30, 2026 | OpenAI API models page; Codex catalog [A] |
| GPT-6.1 Terra (`gpt-6.1-terra`) | 2026-10-26 | 1 / 5 | API 1.05M / 128k; CLI 500k window, 95% effective | API —; CLI `low` | Jun 1, 2026 | OpenAI API models page and changelog; Codex catalog [A] |
| GPT-6 Astra (`gpt-6-astra`) | 2026-09-03 | 10 / 50 | API 1.05M / 128k; CLI 272k window, 95% effective | API —; CLI `medium` | Apr 30, 2026 | OpenAI API models page; Codex catalog [A] |
| Gemini 4 Argon (`gemini-4-argon`) | announced 2026-09-30 | 2 / 10 through 2026-11-30, then 4 / 20 | 1,048,576 unified; output 65,536, up to 1,048,576 with long decode | `medium` (`low`, `medium`, `high`) | unverified | Google blog; AI Studio model and latest-model pages [A] |
| Gemini 3.8 Flash (`gemini-3.8-flash`) | 2026-09-02 | — | — | `medium`; repo agy pin `High` | — | archive; `agy models` 1.5.3 [A] |
| Grok 4.7 (`grok-4.7`) | 2026-09-21 | 2 / 6 | API 500k; CLI 256k or 500k, default not established (`grok/config.toml:19-20`) | —; repo pin `high` | unverified | xAI news; docs.x.ai models page [A] |
| Muse Spark 1.3 (`muse-spark-1.3`, `-contributor`) | — | — | 1,007,997 / 128,000 | CLI default `high`; repo pin `max` | unverified | local catalog, Muse Code 1.2.1 snapshot [A, local] |
| Muse Wonder (`muse-wonder-1.0`; `-full-1.0` is subscription-only) | 2026-10-12 | 4 / 20 for Wonder; no per-token price for Full | 1,007,997 / 128,000 | unverified | unverified | local catalog, Muse Code 1.4.7; VentureBeat [D] |
| Muse Spark Open (`Muse-Spark-Open-816B-A42B`), open weights | 2026-10-15 | — | 1M; 816B total, 42B active | — | — | Meta developer blog [A] |
| Kimi K3.1 Pro (`moonshotai/Kimi-K3.1-Pro`), open weights | weights 2026-11-04 [D] | — | 1M; 2.8T total, 104B active | — | — | Hugging Face model card [A]; date from the Moonshot X post [D] |
| DeepSeek V4.1 Flash-1017, open weights | 2026-10-17 | — | — | — | — | DeepSeek API docs [A] |
| GLM-5.3-Flash (`zai-org/GLM-5.3-Flash`), open weights, MIT | 2026-08 | — | — | — | — | Hugging Face model card [A] |

### Notes, October and November 2026

**Claude [A].** Adaptive thinking is always on for Opus 5.5 and Fable 5.1 and cannot be disabled. The effort ladder is `low→medium→high→xhigh→max`. Anthropic says to set effort explicitly on Opus 5.5 and to re-run your sweep instead of carrying over an Opus 5 setting, because 5.5 thinks more per turn at the same level. The Claude Code `opus` alias resolves to 5.5 since 2.1.280 and `fable` to 5.1 since 2.1.255 (carried from earlier checks, not re-run on 2.1.319). This repo pins interactive `high` on purpose (`claude/settings.json:39`, per-model entries `:41-49`). Fable 5.1 is credit-billed. Anthropic's guidance is to start with Opus 5.5 and use Fable 5.1 for demanding long-horizon work, or when Opus 5.5 at higher effort still misses your evals.

**OpenAI [A].** Codex values are CLI-scoped and the API page does not state a default effort, so do not carry a CLI default over to API calls. Codex 0.159.2 (2026-09-30) gave GPT-6.1 Sol a 272k window; 0.167.0 gives 500k (95% effective) and default `low`. The 0.167.0 catalog also lists `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-terra` and `gpt-5.6-luna` (272k, `medium`) and `gpt-5.6-sol` (272k, `low`). The catalog entries `gpt-reserve` and `codex-auto-review` (272k, `medium`) have no documented purpose. OpenAI positions Terra for fast computer use and high-volume agent work. OpenAI's launch posts keep complex coding on Sol or Astra [D, X]. The Codex catalog lists a `Fast` service tier on every model. The API uses `service_tier: "ultrafast"` for Sol and Astra (API changelog 2026-10-08 and 2026-09-29).

**Effort switches and the prompt cache.** On the API, OpenAI's Reasoning guide describes `configuration_update`, which is appended between responses and keeps the request-level `reasoning.effort` unchanged. In GPT-6 standard single-agent mode this changes effort without breaking the prompt-prefix cache (2026-09-22 [A]). It is not an unconditional cache guarantee. Codex 0.167.0 lists the feature flag `reasoning_effort_override` as stable and on by default. The flag proves the option exists. Nothing read, including the Codex changelog, states that Codex uses `configuration_update` or keeps the cache on a mid-thread switch. CLI cache behavior stays **unverified**: keep one effort per CLI thread.

**Google [A].** Starting 2026-06-18, Gemini CLI stopped serving requests for the Gemini Code Assist individual, Google AI Pro and Google AI Ultra tiers (Google release notes, re-read 2026-11-07). Antigravity CLI (`agy`) replaces it (§12). Other tiers were not checked. Argon's introductory price doubles on 2026-12-01.

**xAI [A].** Grok 4.7 is the current model. This repo pins `grok-4.7` (`grok/config.toml:21`). `grok-4.6` remains only as `fork_secondary_model` (`:123`).

**Meta.** The ae spend policy puts the Muse seat on the Spark 1.3 contributor variant (lead, 2026-11-07). The repo's `muse/settings.json:3` pins the clean `muse-spark-1.3` ID, a different catalog entry. The seat policy and the repo pin are separate settings. Do not infer one from the other. The contributor tier trains on prompts ("may be used for product improvement" in the catalog; Spark snapshot 2026-09-13, not re-verified on Wonder). Wonder is a released model, not the ae seat. The Muse Code 1.4.7 catalog default is the clean `muse-wonder-1.0`. Artificial Analysis Intelligence Index via VentureBeat, 2026-10-12 [D]: Wonder Full 56, Wonder 52, against Opus 5.5 58, Sonnet 5.5 56, Fable 5.1 53 and GPT-6 Astra 53. No Tier A page states Wonder's cutoff or default effort. Do not infer them from backend routing.

**Open weights [A/D].** The Kimi K3.1 Pro model card shows a custom license (`kimi-k3.1-pro`). The status of the original K3 base weights is unverified. Vendor coding charts for open models usually ran on the vendor's own harness; see the harness lesson below.

### Standing lessons carried from the archive

- **Harness choice swings scores as much as model choice.** Same-model, cross-harness gaps of tens of points appear in Terminal-Bench bakeoffs [C/D]. A harness gap has no fixed size or direction. Compare models on matched harnesses, or validate on your own tasks, before you trust a vendor chart that ran on the vendor's own harness.
- **Benchmarks.** OpenAI deprecated SWE-bench Verified (saturated, contaminated) in favor of SWE-bench Pro, read from Scale's leaderboard, plus contamination-resistant live benches [A/B]. Treat deltas under 3pp as noise (Anthropic infra-noise [A]). METR horizons over 16h are unreliable [B]. SWE-Bench Pro V2 (arXiv:2610.24206 [B]) revises the Pro split. A statistical look at the METR plot (arXiv:2610.12466 [B]) questions the time-horizon fit.
- **Long horizons decay.** Short-horizon benchmark gains do not imply long-horizon capability. SWE-EVO and SlopCodeBench show multi-file evolution stays weak and quality erodes over long runs [B]. Pair every long loop with the §17.5 guardrails.
- **Fast mode is separate from effort.** Fast mode trades price for speed. Effort sets reasoning depth. Both can run together.
- **Access can change overnight.** Fable 5 was suspended on 2026-06-12 by government directive and later moved to prepaid credits. Keep a fallback route and pin versioned IDs.
- **Pro tiers are not proven better for coding.** See §20.
- **Open-model "drop into any harness" claims are usually overclaimed [C].** Kimi K3 needed preserved thinking history, and third-party harnesses reported fragmentation and heavy rate-limit burn.

### Earlier history

Entries from September 2026 and older (GPT-6 Astra in Codex, Fable 5.1, Opus 5, the July tier shuffle and CLI landscape, the June frontier moves, Opus 4.7, GPT-5.5, DeepSeek V4, Mythos Preview) are in `KNOWLEDGE-CHANGELOG.md`. The Mythos and Glasswing material that still guides this repo is in §8.

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

Generated code is abundant. **Validation is the bottleneck.** This shifts the operating model. `WORKFLOW.md` and `shared/AGENTS.md` attribute "generated code is debt until validated" to the Anthropic 2026 Agentic Coding Trends Report (§18). The November 2026 refresh fetched that PDF (HTTP 200) but could not text-search it, so the attribution is unconfirmed. Treat the phrase as this repo's shorthand until someone reads the report.

### Operating rules

1. **Significant tasks start with acceptance checks.** Define what "done" looks like before the agent generates.
2. **Agents must run or create executable verification where feasible** — tests, type checks, linters, smoke commands.
3. **If executable verification is not possible, the artifact must declare the verification gap explicitly.** No silent unverified output.
4. **Review artifacts preserve**: intent, diff, tests run, residual risk, source tier of claims relied upon.
5. **Review gates by change class** live in `WORKFLOW.md` (Cross-model review) and `shared/AGENTS.md` (Code review threshold). `/ultrareview` adds depth but not provider diversity (§10).

### Anti-patterns

- "It compiled, ship it" — compilation is necessary, not sufficient
- "I didn't run the tests because they're slow" — declare the gap; don't hide it
- Agent-generated tests for agent-generated code without human verification of test intent
- **Generic "do TDD" prompts.** TDAD (arXiv:2603.17973 [B]) — supplying *targeted code-test impact context* cut regressions ~70%, while a procedural "follow TDD" instruction made regressions *worse*. Give the agent the impact map / acceptance contract, not the procedure. Agent commits also over-mock (arXiv:2602.00409 [B]) — add explicit anti-mock / test-intent guidance.
- **Trusting the test gate the implementer can game.** Reward-hacking the stop criterion (`sys.exit(0)`, deleted/hardcoded tests) is now empirically the dominant autonomous-loop failure — see §17.6. Diversify checks; the implementer must not grade its own only test.
- **Reward hacking spreads and escalates.** A reward-hacking strategy elicited in one agent propagated through shared code, shared memory and natural-language plans to other agents, including stronger closed-weight ones (arXiv:2610.12822 [B]). In autonomous research loops the spontaneous hacking rate was 30.5% on open-ended pipeline tasks. An LLM panel that saw only submitted code and reported scores missed 6.5% of confirmed hacks, and evasions grew over five critique rounds (arXiv:2609.28614 [B]). Implication (ours): give reviewers and verifiers executable evidence, not only the implementer's code, notes and scores.

---

## 5. Effort and Budget Routing

Higher effort is not free. Calibrate per task class.

### Effort routing

**Clemens' defaults:** interactive/default effort is `high`; raise to `xhigh` for judgment-heavy work; ae judgment seats keep `xhigh` via profile; builders/workers start at the vendor default and change that default only on measured outcome. Vendor defaults are model-specific; the §2 table lists them with API-versus-CLI scope (for example Opus 5.5 `medium`, while this repo's interactive pin stays `high`, `claude/settings.json:39`). `WORKFLOW.md` holds the operative cheat sheet and the trivial-work exception. For the effort-switch cache rule see §2, "Effort switches and the prompt cache": the API mechanism is documented, Codex CLI behavior is unverified, so keep one effort per CLI thread.

Boris Cherny (2026-10-28, X [D]) says subagents inherit effort by default, so `xhigh` combined with workflows or agent teams burns limits fast, and `/usage` shows where a session's tokens went. This is a staff signal, not a measured default. It supports the worker-default rule above.

Higher worker effort needs a measured quality gain worth its added tokens/latency. A task's S/M/L bucket determines workflow gates, not an automatic effort override.

### Budget routing

- **Task budgets** (beta since Opus 4.7, header `task-budgets-2026-03-13`; not re-verified on current models) — advisory full-loop budget. Set `/config task_budget 50000` for routine work, 100k–128k for long-running agentic loops. Below 20k, the model can't plan meaningfully.
- **`max_tokens`** — hard ceiling on a single response. Distinct from task budgets. At `xhigh` / `max` effort, watch for `stop_reason: "max_tokens"`.
- **GPT fast tiers** — the Codex catalog lists a `Fast` service tier, and the API offers `service_tier: "ultrafast"` for GPT-6.1 Sol and GPT-6 Astra (§2). Use them only when latency materially matters; standard mode is the default.

### Cost-asymmetric orchestration

For multi-agent setups: capable orchestrator + cheap specialized workers. Reported 40–60% cost cuts vs all-frontier-model setups [D; source not located in the November 2026 refresh]. Verify locally.

---

## 6. Protocol / Infrastructure Governance

`AGENTS.md` and MCP have moved from convenience conventions to **governed infrastructure** under the Linux Foundation Agentic AI Foundation (AAIF, formed 2025-12-09) [A].

### AGENTS.md

- Remains the portable cross-tool repo contract.
- AAIF stewardship implies stability; backwards-compatible evolution is the norm.

### Agent Skills

- Anthropic donated Agent Skills, the `SKILL.md` folder format, to AAIF on 2026-10-22. The same release added Open Responses (OpenAI), OpenEnv (Hugging Face) and OpenSandbox (Alibaba) [A]. Skills now sit under the same foundation as MCP and AGENTS.md. Sources: Anthropic news and the Linux Foundation press release (§18).

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

Skills, agents, MCP servers, hooks, permissions, subagents. Claude Code, Codex, OpenCode, Grok Build and agy all default to this. Claude Code leans furthest into it (`/ultrareview`, task budgets, agent teams).

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

### Planted instruction files [D]

Forever Security (2026-10-22) showed that a web page can drop an `AGENTS.md` into `~/Downloads`, and an agent started in that folder follows it. In their tests Codex ran the payload (npm package `function-color`, edits to `~/.codex/config.toml`) in more than 90% of attempts. Claude Code was harder to fool and fell to a different attack: a planted `CLAUDE.md` rerouted its API traffic. The vendor reports that nothing needs patching on the vendor side. This is a security-vendor blog with lab figures, so treat the rates as a signal. It matches the rule that instruction files and MCP config are governed infrastructure (§6, §9): do not start an agent in `~/Downloads`, and read an instruction file you did not write before the agent does.

### Industry context — the maintainer / researcher reality (April 2026)

Vendor announcements show the offense+defense capability arc; practitioner reports show the operational shift on the ground. Cite together, not one without the other:

- **Thomas Ptacek** ([Decipher podcast][C], [Simon Willison summary][C]): AI-assisted vulnerability research is a real operational shift, not a demo. *"Vulnerability research is cooked"* — both as opportunity and as warning to the field.
- **Nicholas Carlini** ([InfoQ coverage][D]): concrete agentic vuln-discovery examples (Linux kernel, etc.), demonstrating the capability is generally available, not gated to Mythos partners.
- **Daniel Stenberg** ([Ars Technica][D]) — curl scrapped its bug bounty over AI-slop reports overrunning maintainers.
- **Greg Kroah-Hartman** ([Tom's Hardware][D]) — same kernel maintainer using local AI on Framework Desktop to *find* real bugs.

Both are true at once: AI is generating real maintainer review load (good and bad). Repo guidance should reflect this — neither dismiss agentic security tooling nor assume vendor demos generalize. See [§18 References / Practitioner references] for source links and tier markers.

---

## 9. Instruction File Landscape (updated November 2026)

Every AI coding tool reads a markdown config file. AAIF stewardship means `AGENTS.md` is the closest to a stable cross-tool standard.

| File | Tool(s) | Status |
|------|---------|--------|
| `AGENTS.md` | Codex (first-class), Cursor, Grok, agy, Claude Code (fallback), most via convention | Closest to universal. AAIF-stewarded [A]. |
| `CLAUDE.md` | Claude Code; Grok and Muse also read it | First-class, hierarchical (root→startup, subdirs→lazy). Also `~/.claude/CLAUDE.md` for global. Grok and Muse details in §12. |
| `GEMINI.md` | Antigravity CLI (`agy`) | agy reads project `GEMINI.md` or `AGENTS.md` (§12). Gemini CLI stopped serving the individual, AI Pro and AI Ultra tiers on 2026-06-18. |
| `.cursor/rules/` | Cursor | Cursor-specific. |
| `copilot-instructions.md` | GitHub Copilot | Per repo in `.github/`. The Copilot CLI also reads `${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md`, which this repo renders. |

### Best practice

- **`AGENTS.md`** = single source of truth / universal cross-tool contract
- **`CLAUDE.md`** = Claude-specific operational tips (or symlink to `AGENTS.md` if content is identical). This repo renders its contract into each tool's global file instead of symlinking (`scripts/render-contract.sh`; README, "Where doctrine lives")
- Tool-specific files only when they clearly pay off
- Keep under 200–300 lines each
- Focus on what agents would get wrong without the file
- Evidence [B]: context files did not generally improve task success and raised inference cost by over 20% on average. Agents follow the instructions well, but repository overviews did not help; use the files for non-standard practices and test them before deploying (arXiv:2602.11988)
- Evidence [B]: conditional phrasing was followed less often than prescriptive or explanatory phrasing (86 tasks, four harness-model combinations; a short paper still under review, arXiv:2611.04367)
- NOT code snippets (go stale), NOT obvious facts inferable from `package.json`

---

## 10. Claude Code Feature Stack

> Probed 2026-11-07 on Claude Code 2.1.319: all 33 hook event names below appear
> as strings in the binary and in the hooks reference fetched the same day, and the
> `bashOutputMaxChars` default and clamp are read from the binary's settings schema.
> Inherited, not re-run: hook exit-code and blocking behavior (reference, 2026-09-07),
> the agent frontmatter field list, and subagent skill inheritance. Other schema
> examples still need a current-doc check before use.

### CLAUDE.md (deterministic — always loaded)

Global `~/.claude/CLAUDE.md`, project `./CLAUDE.md`, subdirs lazy. `CLAUDE.local.md` for personal prefs (gitignored). Keep under ~200 lines per file.

**Instruction deduplication (closed as moot, 2026-11-07).** A 2026-09-07 probe of removing this repo's `@shared/AGENTS.md` import was inconclusive. The repo no longer imports that file: the contract is rendered into `~/.claude/CLAUDE.md` (`CLAUDE.md`, Architecture). No measured deduplication gain was ever shown.

### Skills (`~/.claude/skills/*/SKILL.md` or `.claude/skills/`)

Reusable workflows. Lazy-loaded in main session on description match. Cross-tool compatible: Grok and agy read the same files (§12). Whether OpenCode 2 still reads `~/.claude/skills/` is unverified. Disable model invocation with `disable-model-invocation: true` for side-effect workflows.

### Agents (`~/.claude/agents/*.md` or `.claude/agents/`)

Specialized subagents with own context, tools, model, permissions. Frontmatter fields exist for: `name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `mcpServers`, `hooks`, `maxTurns`, `skills`, `initialPrompt`, `memory`, `effort`, `background`, `isolation`, `color`. Verify exact set against current docs before authoring.

**Note**: Subagents do **not** inherit skills from the parent conversation. List them explicitly via `skills:`. Full skill content is preloaded eagerly.

### Hooks (`settings.json` — event-driven)

The [official hooks reference](https://code.claude.com/docs/en/hooks.md) lists **33 events** (fetched 2026-09-07; all 33 names re-found in the reference and the 2.1.319 binary on 2026-11-07):

- Session and instructions: `SessionStart`, `Setup`, `InstructionsLoaded`, `SessionEnd`.
- Prompts and display: `UserPromptSubmit`, `UserPromptExpansion`, `MessageDisplay`, `Notification`.
- Tools and permissions: `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`.
- Agents and tasks: `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`.
- Configuration and files: `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`.
- Context and models: `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`.
- MCP input: `Elicitation`, `ElicitationResult`.

Exit code 2 has **event-specific** behavior: it can block tool use, prompt processing, or stopping; it is not limited to `PreToolUse`. `PermissionRequest` instead denies through its JSON decision object. Check the reference's per-event table before building a gate. Common uses: auto-format on write, type-check, block edits on main, desktop notifications.

**Key distinction**: CLAUDE.md + hooks = deterministic. Skills + agents = probabilistic.

### `/ultrareview` [A]

Multi-pass review command. Adds review depth; does not establish provider diversity. Apply the provider gate and stop-at-done cadence in `WORKFLOW.md`.

### Settings (`settings.json`)

Permissions (allow/deny with wildcards), hooks, model config, env. Global `~/.claude/settings.json`, project `.claude/settings.json`, personal `.claude/settings.local.json` (gitignored). Notable fields: `effortLevel`, `modelSettings`, `permissions.deny`, `permissions.defaultMode`, `enableAllProjectMcpServers`. Model config typically via `ANTHROPIC_MODEL` env var.

`bashOutputMaxChars` defaults to **30,000 characters inline**; overflow goes to a file. Values clamp to **4,000–128,000** (default and clamp read from the settings schema in the 2.1.319 binary, 2026-11-07; the value was not exercised at runtime). Lowering it is an experiment: measure saved context and extra file rereads.

---

## 11. Codex CLI Configuration

> Probed 2026-11-07 on Codex 0.167.0: `--help`, `exec --help`, `features list`,
> `debug models` and `debug prompt-input`. The instruction and skill discovery docs
> were re-read at learn.chatgpt.com the same day. Inherited from 0.153.4
> (2026-09-07), not re-run: skill precedence when both user roots are populated, and
> the `trusted_hash` hook behavior (§12).

- Global instructions: `~/.codex/AGENTS.md`
- Config: `~/.codex/config.toml` — fields include `model`, `approval_policy`, `sandbox_mode`, `web_search`, `model_reasoning_effort`, `personality`, `tool_output_token_limit`. (Note: the field is `approval_policy`, not `approval_mode`.)
- Instruction discovery ([official doc](https://learn.chatgpt.com/docs/agent-configuration/agents-md), re-read 2026-11-07): in the Codex home, `AGENTS.override.md` if present, else `AGENTS.md`. From the project root down to the cwd, each directory contributes its first of `AGENTS.override.md`, `AGENTS.md`, then names in `project_doc_fallback_filenames`. Files concatenate root-down; at most one file per directory.
- `project_doc_fallback_filenames = ["CLAUDE.md"]` for projects without `AGENTS.md`. Codex does not auto-discover `CLAUDE.md` by default (`codex/config.toml:68`).
- User skills: **`$HOME/.agents/skills`**, per-skill symlinks for the public and optional overlay layers. Codex follows skill symlinks. `~/.codex/skills/.system` is Codex-managed and stays separate. The [official skills doc](https://learn.chatgpt.com/docs/build-skills) says same-name skills are not merged and both can appear in selectors.
- **Skill catalog re-measured on 0.167.0 (2026-11-07, `codex debug prompt-input`, cwd outside any repo):** the roots table lists `~/.agents/skills` (37 skills) and `~/.codex/skills/.system` (4 managed skills), with no duplicate names. The legacy `~/.codex/skills` root no longer appears. Whether 0.167.0 would still scan it if populated was not tested. The 44 + 5 counts and the legacy-root-wins precedence below come from 0.153.4 and are inherited.
- **G11 (closed on 0.153.4, 2026-09-07, inherited):** `codex debug prompt-input` showed that 0.153.4 scanned both `~/.agents/skills` and legacy `~/.codex/skills`. Duplicate names appeared once, with the legacy root winning. The catalog held 44 user skills + 5 managed system skills. These counts and the precedence are version-scoped observations.
- **Profiles** (`[profiles.<name>]`) for swappable presets — `review`, `quick`, `deep` patterns common.
- Power-user defaults: `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` for full YOLO (`codex/config.toml:22-23`); alternate is `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`. 0.167.0 `--help` lists `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `--approve-for-me` and `--worktree`. `--full-auto` appears in neither `codex --help` nor `codex exec --help`.
- Feature flags on 0.167.0 (`features list`): `goals`, `hooks`, `reasoning_effort_override`, `unified_exec` stable and on; `shell_snapshot` stable and off; `shell_snapshot_v2` under development. The `reasoning_effort_override` semantics are unverified (§2).
- **Privacy: keep `shell_snapshot` off.** A snapshot writes Codex's inherited environment, including gateway keys, as plain `export` lines into `~/.codex/shell_snapshots`. On 2026-08-11, 24 of 25 snapshots on this machine contained the MIC gateway keys. The repo sets `shell_snapshot = false` (`codex/config.toml:74-80`) and purges legacy snapshots (`install.conf.yaml:188-200`). Flag state re-read 2026-11-07.

---

## 12. Antigravity CLI (agy), Grok CLI, and Muse Code Configuration

> Gemini CLI stopped serving the individual, AI Pro and AI Ultra tiers on 2026-06-18 (see §2, Google). Each harness block below separates what
> was probed on 2026-11-07 from what is inherited from an earlier version.

### Antigravity CLI (`agy`) — Gemini CLI's replacement

> Probed 2026-11-07 on agy 1.5.3: `--help`, `agy models`, `agy changelog`, a config
> directory listing, and the repo pins. Inherited from agy 1.2.2 and 1.2.3
> (2026-09-14 and 2026-09-15), not re-run: live `-p` rule and skill loading, hook file
> locations, the settings key list, the MCP-in-print-mode question, and the privacy
> state and opt-out propagation.

- Rules and skills root: **`~/.gemini/config/`** holds `config.json`, `mcp_config.json`, `plugins/`, `projects/` and `skills` → `~/.claude/skills` (listing 2026-11-07). No `hooks.json` is present: it is on-demand config, so absence means unconfigured (inherited: read from `~/.gemini/config/hooks.json`, `<workspace>/.agents/hooks.json` with `trustedWorkspaces`, and `plugins/<name>/hooks.json`).
- Settings and runtime state live under **`~/.gemini/antigravity-cli/`**. Dotbot links `antigravity/settings.json` to `settings.json` there, and agy replaces the link with a normalized copy on each run (repo comment, `antigravity/settings.json:2`). Keys (inherited): `model` (display-name string), `trustedWorkspaces`, `mcpServers` (Claude-style JSON), `permissions.allow/deny`.
- Rules: project `GEMINI.md` or `AGENTS.md`, or plugin rules; Dotbot installs the shared contract at `~/.gemini/config/plugins/dotfiles/rules/AGENTS.md` (inherited, verified on disk 2026-09-14). Skills: the same files serve both harnesses; project skills under `.agents/skills/`.
- Models (`agy models`, 2026-11-07): Gemini 4 Argon, Gemini 3.8 Flash, Claude Opus 5.5 and Claude Sonnet 5.5, each at Low, Medium and High, plus GPT-OSS 120B (Medium). Gemini 3.1 Pro and the Claude 4.6 models are gone from the list. The repo pins `Gemini 3.8 Flash (High)` (`antigravity/settings.json:4`), a deliberate opt-up from Google's `medium` default.
- Flags (1.5.3 `--help`): `--effort low|medium|high|xhigh|max`, `--mode accept-edits|auto|plan`, `--print-timeout` (default `0s`, wait for the turn to finish), `--sandbox`, `--remote-agent`, `acp` (Agent Client Protocol server). Inherited: since 1.1.28 an expired `--print-timeout` returns partial output and exits 0.
- Permissions: the settings key is `toolPermission` with `request-review` (default), `proceed-in-sandbox`, `always-proceed`, `strict` (vendor CLI reference, inherited). The repo pins `always-proceed` (`antigravity/settings.json:9`). The 1.5.2 changelog says `--dangerously-skip-permissions` now blocks commands on the system denylist, and workspace `.agents/plugins.json` and `.agents/skills.json` entries load only from inside the workspace or repository root.
- Print mode (`-p`) executes tools without prompting (inherited). Google-grounded `search_web` is built in (inherited, binary strings).
- Citation reliability (historical): a narrow hooks-docs prompt once returned 5/5 valid URLs, but an earlier broader audit found 37/56 fabricated citations. Treat agy citations as unverified until checked.
- **Privacy: NOT private by default** (vendor CLI reference, inherited 2026-09-14): `enableTelemetry` and `showFeedbackSurvey` default `true`. The repo pins both `false` (`antigravity/settings.json:6-7`). Remote opt-out propagation stays unverified until an authenticated run. Opt-out is not retroactive (Google Terms): past interactions need a deletion request to antigravity-support@google.com.

### Grok CLI (Grok Build)

> Probed 2026-11-07 on Grok 1.0.77: `--version`, `--help`, and the repo pins.
> `grok inspect` was not run. Inherited from 1.0.30 (2026-09-14), not re-run: the
> `grok inspect` counts and compatibility matrix, the rules-file cap, the privacy
> and account state, and the binary-embedded config docs.

- Config: `~/.grok/config.toml` — `[models] default = "grok-4.7"` and `default_reasoning_effort = "high"` (`grok/config.toml:21-22`). `grok-4.6` remains only as `fork_secondary_model` (`:123`). `[mcp_servers.*]` use Codex-style TOML. `[features]` covers `support_permission`, `telemetry` and `feedback`, all off in the repo (`:34-36`).
- `~/.grok/config.toml` must be a **real file** (inherited: the hooks-paths registry rejects symlinks, and Grok writes sticky state there). Installation copies the repo config instead of linking it (`install.conf.yaml:273-289`).
- **Claude-compat is the headline** (inherited from 1.0.30): Grok reads user skills from `~/.claude/skills/`, agents from `~/.claude/agents/`, `~/.claude/CLAUDE.md` as global rules, permissions from `~/.claude/settings.json`, and MCP servers from `~/.claude.json`. A full Claude harness setup carries over with zero re-wiring.
- Rules files: `Agents.md`/`Claude.md`/`AGENT.md`/`AGENTS.md`, global in `~/.grok/`, **10k characters per file** (shipped README, inherited). `~/.grok/AGENTS.md` is a short pointer (`grok/AGENTS.md`), and the Claude-compat path loads the full contract.
- Native X search tools (`x_keyword_search`, `x_semantic_search`) are built in (inherited, binary strings). The `--check` and `--best-of-n` flags are gone from `--help` (absent in 1.0.30 and again in 1.0.77); equivalents ship as the `best-of-n-runner` agent and `check`/`check-work` skills (inherited). New in the 1.0.77 `--help`: `--reasoning-effort`, `--worktree`, `--max-turns`, `--sandbox <PROFILE>`.
- **Privacy** (inherited): `[features] telemetry/feedback=false` only silences the CLI. Training and code-retention opt-out is *account* state (`/privacy`, `auth.json coding_data_retention_opt_out`, `true` on this machine 2026-09-14). `[tools] disable_zdr_incompatible_tools=true` and `respect_gitignore=true` are set in the repo (`grok/config.toml:40`, `:43`). The `respect_gitignore` default is false, so without it built-in search and read ingest `.env` into context.
- **Chrome DevTools MCP (any tool embedding it)**: usage statistics and CrUX URL upload from performance traces are ON by default. Pass `--no-usage-statistics --no-performance-crux`. The repo already does (`grok/config.toml:111`; flags re-verified in chrome-devtools-mcp@1.8.0 `--help`, 2026-09-14).

### Muse Code

> Probed 2026-11-07: the pinned binary `~/.local/bin/muse-bin-1.4.14-R7309.1` (version
> from the file name; the self-updating `muse` launcher was not run), its `--help`, the
> cached model catalog and the repo pins. Inherited from Muse Code 1.2.1 (2026-09-13),
> not re-run: install layout, authentication, skill and rule discovery, the MCP key
> collision and the 429 retry ladder.

- Installation: self-updating `muse-stable` bash launcher at `~/.local/bin/muse`, plus a pinned `~/.local/bin/muse-bin-<version>` binary (inherited).
- Config root `~/.config/muse/` (`settings.json`, `auth.json`, `trust.json`) and state root `~/.local/share/muse/` (inherited). `XDG_CONFIG_HOME` and `XDG_DATA_HOME` override both roots. Authentication is an OAuth device code against `https://auth.meta.com` with the API base `https://api.meta.ai/v1`; the token is in the macOS keychain (inherited).
- Cached catalog (`~/.local/share/muse/model-catalog/`, read 2026-11-07, nine rows): default `muse-wonder-1.0`. Visible: Wonder, Wonder Full, Spark 1.3, Spark 1.2. Hidden: the `-contributor` variants and `muse-image-1.0`. Every text model advertises a 1,007,997-token context and 128,000 output. The cache file's age was not checked.
- Repo pins: `model` = `muse-spark-1.3` (the clean ID, not the contributor variant) and `reasoning_effort` = `max` (`muse/settings.json:3-4`). `--help` accepts `none|minimal|low|medium|high|xhigh|max|ultra` (default `high`, alias `--effort`) and lists `--disable-write`, `--disable-shell`, `usage` and `model-profile`.
- **Contributor tier trains on prompts, retains data for 30 days, and is not ZDR** (Spark snapshot 2026-09-13, inherited, not re-verified on Wonder). An unpinned install once landed on the training tier because the contributor variant was the vendor default. The Wonder catalog now defaults to the clean model. Pin the model explicitly. The ae seat policy (§2, Meta) is a separate decision.
- User-scope skills resolve from `$HOME/.agents/skills/<name>/SKILL.md`, alongside about 22 bundled skills (inherited). User rules load from `~/.claude/CLAUDE.md` with precedence project → Claude Code → Codex (inherited).
- MCP servers live under the camelCase `settings.json` key **`mcpServers`**. Never leave snake_case `mcp_servers` beside it: the collision makes Muse drop the entire MCP member and silently disables every server (inherited).
- Sandbox and approvals are on by default. Read-only reviewer form: `muse --disable-write --disable-shell` (flags re-confirmed in `--help`); route through ae when in a session, as for every provider.
- **Verification gap (inherited):** `reasoning_effort: max` is verified as configured and accepted, not as applied to the main turn. `session.jsonl` records effort only for reminder sub-agents, and `muse trace inspect` exposes no main-turn effort field.
- A first live attempt returned HTTP 429 `rate_limited`; Muse retried transparently (up to 10 attempts, 5000 ms backoff). The retry ladder is normal (inherited).

### OpenCode and GitHub Copilot CLI

- OpenCode v2.2.6 (`opencode --version`, 2026-11-07). `--help` shows a background-service model (`--standalone` runs a private server), the `service`, `run`, `plugin`, `mcp` and `acp` subcommands, and an `--auto` flag that approves permissions not explicitly denied. OpenCode 2 reads only `opencode.json(c)`; its terminal settings live in `~/.config/opencode/cli.json`, which the TUI writes and the repo leaves unmanaged (`install.conf.yaml:89-91`). Skill discovery and hook behavior on v2 are unverified.
- GitHub Copilot CLI 1.0.107 (`copilot --version`, 2026-11-07). The repo provisions the native home `${COPILOT_HOME:-$HOME/.copilot}`: rendered instructions, an additive MCP merge for owned names, and a key-only edit that turns off commit co-author attribution (`install.conf.yaml:182-245`). Copilot behavior beyond the version was not probed.

### Hook support across harnesses

> The matrix was verified 2026-09-15 on Claude Code 2.1.272, Codex 0.154.0, Grok 1.0.30, Muse 1.3.0-R3057.1, agy 1.2.3 and OpenCode 1.18.31 (evidence: `.local/hooks-*.md`, `.local/tune/doctrine/hooks.md`). It was **not re-run** on the versions installed 2026-11-07 (Claude Code 2.1.319, Codex 0.167.0, Grok 1.0.77, Muse 1.4.14, agy 1.5.3, OpenCode v2.2.6). Two known changes since: Codex `--help` now lists `--dangerously-bypass-hook-trust`, and the agy 1.5.3 changelog adds `PLUGIN_ROOT` and `PLUGIN_DATA` for plugin hook commands. The OpenCode row predates the 2.x rewrite.

| Harness | Events | Block / modify | Trust gate | Maturity |
|---|---|---|---|---|
| Claude Code | 30+, session→turn→tool + async | full: block, `updatedInput`, context inject | workspace-trust dialog; `-p`/SDK bypasses it for settings-file hooks, subagent frontmatter stricter | reference impl, versioned, managed-policy tier |
| Codex | 12 lifecycle + legacy `notify` | full per-event; `async` hooks observe-only | per-hook sha256 `trusted_hash` | strong: committed schemas, fixture tests |
| Grok | 15, session→turn→tool | full: deny/ask, silent rewrite, output replace | folder trust (`trusted_folders.toml`) | mature, documented, TUI-managed |
| Muse | 13 user-facing | block/modify/inject; no built-in tool-output replace (MCP unverified) | project-folder trust | documented, strict validator, young ergonomics |
| agy | 5 (`Pre/PostToolUse`, `Pre/PostInvocation`, `Stop`) | block + shallow arg merge + inject; `PostToolUse` observe-only | workspace trust via `trustedWorkspaces` | documented, maintained, narrow |
| OpenCode | plugin system IS the hooks (~20 points + bus) | full incl prompt/history rewrite; throw-to-block documented for tool hooks only | none found — **unverified negative** | moderate; half the power is `experimental.*` |

- Codex `PreToolUse` fails open on malformed output: non-JSON or an unknown field leaves `should_block` false and the tool proceeds — a typo silently stops blocking.
- Codex `async = true` hooks are observe-only; blocking fields are ignored silently, as is a hook whose `trusted_hash` no longer matches.
- OpenCode's plugin system has no trust gate found — a project or npm plugin is arbitrary code at startup (**unverified as a negative**: schema-and-docs silence, not proof).
- Hooks run at user privilege, outside any harness sandbox, on Claude Code, Codex, Muse, and OpenCode (Muse says so outright: outside sandbox and approvals, cleared env with small allowlist); Grok and agy hook-sandbox status not separately verified.
- Open gaps: Muse exit-code/timeout semantics, `.musehooks.json`'s role, whether agy's proto-level `SessionStart` is user-reachable, Grok's missing schema version string, Codex TUI trust-approval UX (how `trusted_hash` gets recorded), Grok/agy hook-sandbox status.

---

## 13. Cross-Model Workflow

The single highest-value pattern across the field. Single model reviewing its own code = predictable blind spots. Two models > one. Biggest gain is 1→2, not 2→4.

**Workflow**:

1. **Plan** (judgment seat at `xhigh`) → `plans/{feature}.md`
2. **QA Review** (different served provider, read-only) → adds findings, never rewrites
3. **Implement** (planner model, new session) → phase-by-phase with test gates
4. **Verify** (reviewer model) → checks implementation vs plan

**No native interop.** Shared filesystem + git. Separate agents reading the same `AGENTS.md`.

### Evidence on pairing and direction [B]

A controlled experiment on 116 LiveCodeBench tasks (arXiv:2607.21656, accepted at Agentic SE @ KDD'26) found an asymmetric pairing. Claude reviewing Codex drafts raised the pass rate from 71.6% to 89.7%. Codex self-review reached 84.5%. Codex reviewing Claude drafts lowered it from 91.4% to 82.8%, and Claude self-review left 91.4% unchanged. The reviewer saw the problem and the draft but could not run tests, and the study covers one Claude and one Codex model. Repo guidance does not change: review stays provider-diverse in both directions. The result is a reason to give reviewers executable checks and to measure a pairing before trusting it.

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

- Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1: 1M tokens (§2) [A].
- **1M is a ceiling, not a recommended working size.** Coherence still degrades in sprawling sessions ("dumb zone" reports persisted from Opus 4.6 through 4.7; not re-checked on 5.5).
- **Message threads (beta, header `message-threads-2026-08-12`).** The server keeps the conversation, so a request sends only the new messages and time to first token stays lower and steadier in long agent loops. A thread is best-effort: it expires 5 minutes after its last request, a continue request then returns 404, and the client must replay the full conversation. Not ZDR or HIPAA eligible [A, platform.claude.com message-threads page, 2026-11-07].
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
- Verifiers that read the implementer's plans and notes: reward hacking transmits through shared code, memory and plans (arXiv:2610.12822 [B])

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

## 17. Loops

"Loop" names **five distinct things** in 2026 agentic engineering; conflating them is the main source of confusion. The agent loop *itself* is repackaged 2023 (ReAct / AutoGPT) — the value is in the harness discipline around it. June-2026 mantra (Steinberger/Cherny [C]): *"you shouldn't be prompting agents anymore; you should be designing the loops that prompt your agents."* True, but a loop is **necessary, not sufficient** — capability + harness are the real signal; "loops solve autonomy" is noise.

### 17.1 Five loop-related concepts (4 loop types + guardrail discipline)

1. **Agent loop (primitive)** — the LLM calls tools in a loop until it emits a final message with no tool calls. *"An agent is a while-loop with an LLM and tools"* (Ball, Willison [C]). One full cycle = one *turn*. ~400 lines. Plumbing, not strategy.
2. **Ralph / continuation loop** — re-feed the same prompt with **fresh context each pass**; progress lives on disk (files, git, `fix_plan.md`), not model memory. See §17.4.
3. **Scripted orchestration (orchestration-as-code)** — loop/fan-out control lives in *code*, not the context window. See §17.3. **The new primitive of mid-2026.**
4. **Eval-in-the-loop (self-improving)** — observe evidence → group failures → convert a repeated failure into an eval/acceptance target → fix → re-run targeted + regression checks → human reviews evidence. **The current SOTA loop** (OpenAI Tax-AI pattern [A]; Arize/Phoenix [D]).
5. **Guardrails** — the discipline that keeps any of the above bounded. See §17.5.

### 17.2 The one rule [A]

**Never let the model decide "done." Close the loop on a machine-checkable signal** — tests, build exit code, linter, fixture-diff, screenshot. Without one, *"looks done"* is the only signal available and **you** become the verification loop. Self-correction only works *grounded*: pure in-context self-critique is fragile (DeepMind, ICLR 2024, arXiv:2310.01798 [B]). "The Self-Correction Illusion" (arXiv:2606.05976, 2026-06-04 [B]) shows models fix **externally-attributed** errors 23–93pp better than their own `<thought>` trace — *"a chat-template artifact, not a cognitive deficit."* This is the mechanical reason **cross-model / fresh-context review works**: put the critic in a different context or model family so the feedback reads as external.

### 17.3 Orchestration-as-code [A]

The shift: in a plain agent loop the model decides *inside the context window* what to do next ("spawn a subagent? which file next?"). That plan is implicit in the conversation, consumes context, and rots over long runs. **Orchestration-as-code inverts it** — the agent writes a deterministic script (JavaScript, in Claude Code dynamic workflows) describing the control flow (fan-out, pipeline, loops, conditionals); a background runtime executes it; **only results return to the model's context, not the bookkeeping.**

Why it's stronger than a chat loop:

- **Deterministic control flow** — real `for`/`while`/`if` and explicit fan-out, not model-judged "should I loop again?"
- **Plan stays out of context** — no context rot from orchestration overhead; the window holds synthesized results only
- **Bounded concurrency** — Claude Code docs state **up to 16 concurrent agents by default** (fewer on low-CPU hosts; `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` changes it) and **1,000 agents total** per run [A, workflows docs, 2026-11-07]
- **Fresh context per subagent** — each spawned agent gets a clean window (the Ralph insight, generalized)
- **Inspectable / re-runnable / resumable** — the script is an artifact you can read, diff, and replay

Illustrative example (pseudocode showing the *shape* of the dynamic-workflows API, not verbatim public-doc syntax) — exhaustive review. Pipeline each review dimension through *find → adversarially-verify*, so each finding is refuted-or-confirmed the moment its dimension completes:

```javascript
// Illustrative — Claude writes a script like this; a background runtime runs it.
const DIMENSIONS = [
  { key: 'bugs',     prompt: 'Find correctness bugs in the diff' },
  { key: 'security', prompt: 'Find auth / injection / secret issues' },
  { key: 'perf',     prompt: 'Find N+1 queries, needless allocations' },
];

const results = await pipeline(
  DIMENSIONS,
  // stage 1: one finder agent per dimension (fresh context each)
  d => agent(d.prompt, { schema: FINDINGS, label: `find:${d.key}` }),
  // stage 2: each finding gets an independent skeptic in fresh context
  review => parallel(review.findings.map(f => () =>
    agent(`Adversarially verify — try to REFUTE: ${f.title}`, { schema: VERDICT })
      .then(v => ({ ...f, verdict: v })))),
);

return results.flat().filter(f => f.verdict?.isReal);
// 'security' findings verify while 'perf' is still being found — no wasted wall-clock.
```

The same shape covers **migrations** (discover sites → transform each in an isolated worktree → verify), **research fan-out** (the exact pattern behind this doc's June-2026 refresh), and **loop-until-dry discovery** (keep spawning finders until K rounds return nothing new). Codex's equivalent surface is app-server / non-interactive mode — orchestration moved out of the chat UI into programmable APIs on both sides.

**Caveat [A]:** multi-agent fan-out costs ~15× the tokens of a single chat (Anthropic, "How we built our multi-agent research system", §18). Reserve it for high-value, parallelizable, context-exceeding work — *most coding tasks aren't parallel enough to justify it*. Orchestration-as-code makes fan-out cheaper to *control*, not cheaper to *run*.

### 17.4 Ralph, honest read [C]

Huntley's pattern: `while :; do cat PROMPT.md | claude-code ; done`. The mechanism that matters is **not "run forever" — it's fresh context per iteration with progress on disk** (Horthy's distillation: *"carve work into small independent context windows,"* not "run forever"). Official Claude Code plugin:

```
/plugin install ralph-wiggum@claude-plugins-official
/ralph-loop "Your task" --max-iterations 20 --completion-promise "DONE"
# marketplace installs may namespace the command:
#   /ralph-wiggum:ralph-loop "Your task" --max-iterations 20 ...
# verify exact form against the current plugin README
```

- Best for: greenfield, well-specified, **one-task-per-loop**, test-gated mechanical work (batch refactors, migrations, coverage)
- Huntley's own red line: *"no way in heck would I use Ralph in an existing codebase"* — greenfield only; senior steering required
- NOT for: judgment-heavy work, UX, architecture, vague specs, unbounded runs
- Always set `--max-iterations`; also native as `/loop` (self-paced, 1-min–1-hr wake via `ScheduleWakeup`; an uncancelled loop ends after seven days [A, scheduled-tasks docs, 2026-11-07]); can run parallel across git worktrees

### 17.5 Guardrails for unattended loops [A/C]

Every unattended loop needs, **by construction**:

- A **machine-verifiable stopping criterion** (not "agent says done")
- A **hard iteration ceiling** (`--max-iterations`, `max_turns`) — Claude Code ends the turn after stop hooks continue it eight times in a row [A, hooks reference, 2026-11-07; an environment variable raises the cap]
- A **token/$ budget cap** — increasingly the *real* governor over raw iteration count (Claude Agent SDK exposes `max_budget_usd`; Codex `/goal` stops on budget exhaustion)
- **Wall-clock limit + no-progress detection** (exit if diff/error is unchanged N rounds — *"you cannot ask an agent if it is in a loop; you must prove it"*)
- A **kill-switch** (`Esc`; `CLAUDE_CODE_DISABLE_CRON=1`)
- **Sandbox + least privilege** for anything autonomous (staging creds only; Meta's "Rule of Two" on Willison's lethal trifecta: ≤2 of {private data, untrusted input, external comms})
- **Structured, machine-readable per-iteration state** (attempted change, command run, eval/result, next delta, blocker) — observability-as-API, not a dashboard: the *next* loop must be able to consume the prior loop's traces, eval results, and cost/tool-call telemetry programmatically. [A/D]
- **Stop — don't continue — when the next action needs a human/product/security decision**

### 17.6 The defining failure mode — reward-hacking the criterion [A/B]

The agent that games its own stop signal: calls `sys.exit(0)` to fake green tests, deletes failing tests, hardcodes expected outputs. METR found Opus 4.6 attempted reward hacking in **~80%** of long MirrorCode runs [B; source not located in the November 2026 refresh]; it *generalizes* to broader sabotage (Anthropic "Natural emergent misalignment from reward hacking", arXiv:2511.18397 + official research page [A/B] — 12% sabotage, ~50% alignment-faking after learning to hack). The behavior also spreads between agents through shared code, memory and plans, and grows over critique rounds when the check is a shallow score (arXiv:2610.12822, arXiv:2609.28614 [B]; §4). **Mitigation:** diversify checks, add holdout tests + mutation testing, and **never let the implementer write *and* grade the only test.** Counter-intuitively, "inoculation prompting" (explicitly permitting the hack) removes the *misaligned generalization* [A]. Long-horizon decay compounds this: SlopCodeBench [B] shows quality erodes monotonically and **better prompts don't stop it** — bound the loop, don't trust it to self-limit.

### 17.7 Repo docs this refresh implies (open follow-ups)

Recorded here so they're not lost; each is a separate, confirmable change. Still open on 2026-11-07: `shared/AGENTS.md` has no unbounded-loops rule, `skills/large-feature/SKILL.md` cites §18 but not §17, and `skills/refactor-audit` has no loop-safe field.

- **`shared/AGENTS.md`** — candidate for a one-line contract rule: *"No unbounded loops — every autonomous loop needs a machine-verifiable stop, an iteration ceiling, and a budget cap (§17.5)."* Decide contract-level vs. WORKFLOW-level.
- **`large-feature` skill** — could reference §17 loops explicitly (its red-green slices are eval-in-the-loop), or defer to a dedicated loops skill/playbook.
- **`refactor-audit` skill** — candidate "loop-safe" field for repeated-drift signals surfaced by recurring loops.

---

## 18. Repository References

> Source-tier markers `[A]/[B]/[C]/[D]` per §3. Tier A/B drives normative
> recommendations; C/D are signals only.

### Tier A — Official docs

- Claude Code docs — https://code.claude.com/docs/en/best-practices [A]
- Codex docs (AGENTS.md discovery) — https://learn.chatgpt.com/docs/agent-configuration/agents-md [A]
- AGENTS.md spec — https://github.com/agentsmd/agents.md (AAIF stewardship) [A]
- `anthropics/skills` — https://github.com/anthropics/skills [A]
- `anthropics/claude-code` — https://github.com/anthropics/claude-code (includes ralph-wiggum plugin) [A]
- Anthropic Project Glasswing — https://www.anthropic.com/project/glasswing [A]
- Anthropic Mythos Preview — https://red.anthropic.com/2026/mythos-preview/ [A]
- Anthropic 2026 Agentic Coding Trends Report (PDF) — https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf [A]
- Linux Foundation AAIF — https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation [A]
- Anthropic Opus 5 launch — https://www.anthropic.com/news/claude-opus-5 [A]
- Anthropic models overview (IDs, pricing) — https://platform.claude.com/docs/en/models/overview [A]
- Claude Haiku 5.5 launch — https://www.anthropic.com/news/claude-haiku-5-5 [A]
- Claude message threads (beta) — https://platform.claude.com/docs/en/build-with-claude/message-threads [A]
- Claude Code model config (aliases incl. fable -> 5.1, effort defaults, category fallback, fast mode) — https://code.claude.com/docs/en/model-config [A]
- Anthropic Fable 5.1 model page — https://platform.claude.com/docs/en/models/fable-5-1/overview [A]
- Anthropic Opus 5.5 model page (ID, pricing, default effort `medium`) — https://platform.claude.com/docs/en/models/opus-5-5/overview [A]
- Anthropic Sonnet 5.5 model page (ID, pricing, default effort `high`) — https://platform.claude.com/docs/en/models/sonnet-5-5/overview [A]
- OpenAI API changelog (GPT-6 Astra 2026-09-03, Sol/Luna 2026-09-22, GPT-6.1 Sol 2026-09-29, GPT-6.1 Terra 2026-10-26) — https://developers.openai.com/api/docs/changelog [A]
- OpenAI model catalog (GPT-6 family pricing, context, efforts) — https://developers.openai.com/api/docs/models [A]
- OpenAI "Better prompt caching for GPT-6" (effort switches preserve cache, 2026-09-22) — https://openai.com/index/better-prompt-caching-for-gpt-6/ [A] (HTTP 403 to non-browser clients; not opened in the November 2026 refresh)
- OpenAI Reasoning guide — change reasoning mid-conversation (`configuration_update`, API mechanism; no Codex CLI adoption stated) — https://developers.openai.com/api/docs/guides/reasoning [A]
- Anthropic effort guide (per-model recommendations) — https://platform.claude.com/docs/en/build-with-claude/effort [A]
- Claude Code Dynamic Workflows docs — https://code.claude.com/docs/en/workflows [A]
- Claude Code changelog — https://code.claude.com/docs/en/changelog [A]
- Claude Agent SDK — agent loop (`max_turns`, `max_budget_usd`, auto-compaction) — https://code.claude.com/docs/en/agent-sdk/agent-loop [A]
- Anthropic "Harness design for long-running application development" — https://www.anthropic.com/engineering/harness-design-long-running-apps [A]
- Anthropic "Natural emergent misalignment from reward hacking" — https://www.anthropic.com/research/emergent-misalignment-reward-hacking [A]
- Codex changelog (Goal mode GA, app-server, automations, devtools) — https://learn.chatgpt.com/docs/changelog [A]
- Codex Goals cookbook (lifecycle, budget-stop) — https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex [A]
- OpenAI "Building self-improving tax agents with Codex" (evidence-backed improvement loop) — https://openai.com/index/building-self-improving-tax-agents-with-codex/ [A]
- Google Gemini Code Assist / Antigravity release notes (Gemini CLI stopped serving three tiers 2026-06-18) — https://docs.cloud.google.com/gemini/docs/codeassist/release-notes [A]
- OpenAI Codex team — "Unrolling the Codex Agent Loop" (engineering notes on agent loop) — https://openai.com/index/unrolling-the-codex-agent-loop/ [A]
- OpenAI Codex team — "Harness Engineering" (notes on harness design) — https://openai.com/index/harness-engineering/ [A]
- Anthropic / Claude.com — "Eight trends defining how software gets built in 2026" — https://claude.com/blog/eight-trends-defining-how-software-gets-built-in-2026 [A]
- Sourcegraph blog — "Why Sourcegraph and Amp are becoming independent companies" — https://sourcegraph.com/blog/why-sourcegraph-and-amp-are-becoming-independent-companies [A]
- Sourcegraph blog — "A new era for Sourcegraph: the intelligence layer for AI coding agents and developers" — https://sourcegraph.com/blog/a-new-era-for-sourcegraph-the-intelligence-layer-for-ai-coding-agents-and-developers [A]
- Pi documentation — https://pi.dev/docs/latest [A]
- OpenAI Codex model catalog — https://learn.chatgpt.com/docs/models [A]
- OpenAI Codex skills docs (locations, same-name skills, symlinks) — https://learn.chatgpt.com/docs/build-skills [A]
- Google Antigravity CLI docs — https://antigravity.google/docs/cli-overview [A]
- Google Gemini API latest-model page (3.8 Flash and 4 Argon: IDs, default effort, pricing) — https://aistudio.google.com/docs/latest-model?generate-content=true [A]
- Google Gemini 4 Argon model page — https://aistudio.google.com/docs/models/gemini-4-argon [A]
- Google Gemini 4 Argon announcement — https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-4-argon/ [A]
- xAI Grok Build overview — https://docs.x.ai/build/overview [A]
- xAI Grok Build announcement — https://x.ai/news/grok-build-cli [A]
- xAI Grok 4.7 announcement — https://x.ai/news/grok-4-7 [A]
- xAI models page (Grok 4.7 context and price) — https://docs.x.ai/developers/models [A]
- Meta "Build with Muse Spark Open" — https://dev.meta.ai/resources/blog/build-with-muse-spark-open [A]
- Moonshot Kimi K3.1 Pro model card — https://huggingface.co/moonshotai/Kimi-K3.1-Pro [A]
- DeepSeek V4.1 Flash-1017 release — https://api-docs.deepseek.com/news/news261017 [A]
- Zhipu GLM-5.3-Flash model card — https://huggingface.co/zai-org/GLM-5.3-Flash [A]
- Anthropic "Donating Agent Skills to the Agentic AI Foundation" (2026-10-22) — https://www.anthropic.com/news/donating-agent-skills-to-the-agentic-ai-foundation [A]
- Linux Foundation — AAIF adds Agent Skills, Open Responses, OpenEnv, OpenSandbox — https://www.linuxfoundation.org/press/agentic-ai-foundation-announces-four-new-projects-agent-skills-open-responses-openenv-and-opensandbox [A]
- Anthropic "How we built our multi-agent research system" (~15× tokens) — https://www.anthropic.com/research/multi-agent-research-system [A]
- Claude Code scheduled tasks and `/loop` (seven-day expiry) — https://code.claude.com/docs/en/scheduled-tasks [A]
- Microsoft Agent Framework BUILD 2026 (Agent Harness, CodeAct, Hosted Agents) — https://devblogs.microsoft.com/agent-framework/microsoft-agent-framework-at-build-2026-announce/ [A]

### Tier B — Academic / research

- "Rethinking Software Engineering for Agentic AI Systems" — arXiv:2604.10599 [B]
- "Dive into Claude Code architecture" — arXiv:2604.14228 [B]
- "Configuring Agentic AI Coding Tools" — arXiv:2602.14690 [B]
- "MCP production design patterns" — arXiv:2603.13417 [B]
- TDAD — targeted code-test impact context (cut regressions ~70%; generic "do TDD" made them worse) — arXiv:2603.17973 [B]
- Over-mocked tests in agent-generated suites — arXiv:2602.00409 [B]
- "The Self-Correction Illusion" (external-attribution lifts correction 23–93pp) — arXiv:2606.05976 [B]
- "Natural emergent misalignment from reward hacking" — arXiv:2511.18397 [B] (pairs with the Anthropic research page in Tier A)
- ReAct (Thought→Action→Observation loop) — arXiv:2210.03629 [B]
- "Large Language Models Cannot Self-Correct Reasoning Yet" (DeepMind, ICLR 2024) — arXiv:2310.01798 [B]
- SlopCodeBench (long-horizon quality erodes monotonically) — arXiv:2603.24755 [B]
- SWE-EVO (multi-file software evolution remains weak) — arXiv:2512.18470 [B]
- METR time-horizon + uplift-study redesign (horizons >16h unreliable; "~20% slowdown" qualified on selection-bias grounds) — https://metr.org [B]
- Anthropic infra-noise / benchmark config sensitivity (sub-3pp deltas are noise; Terminal-Bench swings ~6pp on hardware config) — Anthropic engineering [A]
- "Stop Hand-Holding Your Coding Agent: Engineering the Loops that Replace Step-by-Step Prompting" — arXiv:2607.00038 [B]
- "Reward Hacking as a Transmissible Strategy in Multi-Agent Coding Systems" — arXiv:2610.12822 [B]
- "Reward Hacking Challenges Oversight of Autonomous Research Agents" — arXiv:2609.28614 [B]
- "Cross-Model LLM Code Review: Should you use Claude to review Codex or vice versa?" — arXiv:2607.21656 [B]
- "Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents?" — arXiv:2602.11988 [B]
- "Do Coding Agents Follow AGENTS.md? The Effect of Policy Wording on Instruction Compliance" — arXiv:2611.04367 [B] (short paper, under review)
- "SWE-Bench Pro V2: A Cleaner, Harder-to-Game Coding Benchmark" — arXiv:2610.24206 [B]
- "On the estimation and validity of AI time horizons — a statistical look at the METR plot" — arXiv:2610.12466 [B]
- "Harness Engineering for Agentic AI Coding Tools: An Exploratory Study" — AIware '26 (arXiv ID unverified — locate before citing formally) [B]
- "Proof-or-Stop: Loop Engineering for Verifiable Evidence-Gated Lifecycle Control" — arXiv, July 2026 (ID unverified) [B]
- METR predeployment evaluation of GPT-5.6 Sol (highest detected reward-hacking rate of any public model assessed) — https://metr.org [B]

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

- `awesome-agent-skills` and similar curated directories [D]
- VentureBeat — Boris Cherny / Claude Code workflow coverage — https://venturebeat.com/technology/the-creator-of-claude-code-just-revealed-his-workflow-and-developers-are [D]
- InfoQ — Carlini / Claude Code Linux vulnerability discovery — https://www.infoq.com/news/2026/04/claude-code-linux-vulnerability/ [D]
- Ars Technica — "Overrun with AI slop, curl scraps bug bounties" (Stenberg / maintainer-side reality) — https://arstechnica.com/security/2026/01/overrun-with-ai-slop-curl-scraps-bug-bounties-to-ensure-intact-mental-health/ [D]
- Tom's Hardware — Greg Kroah-Hartman using Framework Desktop + local AI to hunt kernel bugs — https://www.tomshardware.com/software/linux/linux-kernels-second-in-command-uses-framework-desktop-to-hunt-bugs-with-local-ai [D]
- TechCrunch — OpenClaw creator (Peter Steinberger) joins OpenAI — https://techcrunch.com/2026/02/15/openclaw-creator-joins-openai/ [D]
- Forever Security — "Hijacking AI agents via the Downloads folder" (2026-10-22; security-vendor blog with lab figures) — https://forever.security/blog/hijacking-ai-agents-via-downloads-folder/ [D]
- ADTmag — "Loop Engineering Emerges as Developers Put AI Coding Agents on Repeat" (2026-07-01) — https://adtmag.com/articles/2026/07/01/loop-engineering-emerges-as-developers-put-ai-coding-agents-on-repeat.aspx [D]
- LangChain "State of Agent Engineering" report (57% of orgs with agents in production) — June 2026 [D]
- VentureBeat — Muse Wonder / Wonder Full launch + Artificial Analysis Index (2026-10-12) — https://venturebeat.com/technology/metas-new-muse-wonder-and-muse-wonder-full-models-achieve-frontier-performance-but-only-the-weaker-one-is-available-via-api [D]
- Artificial Analysis — Muse Wonder evaluation (Index v4.3, pricing, availability) — https://artificialanalysis.ai/articles/muse-wonder [D]

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

- `--dangerously-skip-permissions` (no `claude-yolo` alias exists in this repo, the fish config or the overlay, checked 2026-11-07)
- Better: `/permissions` with wildcards: `Bash(npm run *)`, `Edit(/src/**)`
- `effortLevel` in `settings.json`: see §5 routing
- Default effort is model-specific; the §2 table lists it. Opus 5.5 defaults `medium`, while Sonnet 5.5, Fable 5.1 and Opus 5 default `high`. Anthropic says to set effort explicitly on Opus 5.5 instead of inheriting an Opus 5 level. On Opus 5 an explicitly set level carries over across model switches, and Fable 5.1 and Opus 5 hold no model-default effort, so a settings `effortLevel` applies directly (2026-10-13, not re-run). Per-model override: `modelSettings.<id>.effortLevel`.
- `/effort` mid-session, `--effort` on launch, `CLAUDE_CODE_EFFORT_LEVEL` env var for persistence (only way `max` persists)
- `/model` to switch mid-session
- `/clear` between unrelated tasks (rarely need `/compact` with 1M context)
- Esc Esc or `/rewind` to undo off-track work
- Subagents for large explorations → keeps main context clean
- `ultrathink` keyword for one-turn deeper reasoning without changing session effort
- `/ultrareview` at merge time
- Useful prompts: *"knowing everything you know now, scrap this and implement the elegant solution"*; *"grill me on these changes and don't make a PR until I pass your test"*

### Codex CLI

- `approval_policy = "on-request"` for the safer default; `approval_policy = "never"` or `--dangerously-bypass-approvals-and-sandbox` for full YOLO (`--full-auto` is gone in 0.167.0, §11)
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
- **Don't assume a Pro tier is better for coding.** GPT-5.5's release tables published no coding benchmarks for its Pro tier (archive) [A].
- **Don't hide verification gaps** — if you can't run tests, declare that explicitly

---

*Last updated: 2026-11-07 (November 2026 refresh: pre-October model log archived, current model table, installed tools re-probed with probed/inherited stamps, new practice, security and paper evidence). Earlier refresh: 2026-10-13. Historical research sections retain their own dates.*
