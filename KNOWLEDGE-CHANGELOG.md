# Knowledge changelog

Archive of dated model and tool history moved out of `KNOWLEDGE.md` §2. The live document keeps only the current model table and the latest notes.

- Source: `KNOWLEDGE.md` at commit 58c8d98 (October 2026 refresh, 2026-10-13), §2, from "September 2026 — GPT-6 Astra in Codex" through "Claude Mythos Preview / Project Glasswing". The entries below are verbatim.
- Archived on 2026-11-07 (November 2026 refresh).
- Section numbers (§N) and "see … above" pointers inside the entries refer to `KNOWLEDGE.md` as of 58c8d98, not to the live file. Strikethrough and "SUPERSEDED" notes are kept as written.
- Facts here are history, not guidance. For current values use the model table in `KNOWLEDGE.md` §2 and the vendor pages in §18.
- Newest entries are first, as in the source.

---

### September 2026 — GPT-6 Astra in Codex [A]

Codex 0.153.4's local model catalog gives `gpt-6-astra` a **272,000-token window**, **95% effective (258,400)**, and default effort **`medium`** (verified locally on 0.153.4, 2026-09-07). These are CLI limits; API-capacity claims do not enlarge the active CLI window. Clemens' judgment seats default to `xhigh`; builders/workers start at vendor default and change that default only on measured outcome. ~~Keep one effort per Astra thread because effort flips bust the prefix cache~~ **PARTLY SUPERSEDED 2026-09-22 — `configuration_update` effort switches preserve the GPT-6 prompt-prefix cache on the API [A]; the blanket one-effort rule was pre-GPT-6. Codex CLI adoption is unverified — keep one effort per CLI thread for now, see October 2026 above.** See `WORKFLOW.md` for the shared effort table.

### Early September 2026 — Fable 5.1 lands [A]

**Claude Fable 5.1 shipped 2026-09-01 [A]** — API ID `claude-fable-5-1`, same $10/$50 per Mtok credit tier as Fable 5 (cache read $0.25), 1M context / 128k output, **knowledge cutoff June 2026** — newest of any Claude. Adaptive thinking is always on and cannot be disabled. Effort ladder `low→medium→high→xhigh→max`; default `high` in the API and Claude Code, `medium` in claude.ai/Cowork. Anthropic says start at `high`; lower effort incl. `low` often exceeds the `xhigh`/`max` of previous models; launch page says similar-or-better than Fable 5 at lower cost, with `medium` roughly matching Fable 5; use `xhigh`/`max` only for the most capability-sensitive work, and higher effort can over-deliberate on routine work. Breaking API changes: forced `tool_choice` `any`/`tool` returns 400; preserved thinking binds thinking blocks to the producing model and conversation prefix, enforced for organisations created ≥ 2026-08-31. Claude Code `fable` alias resolves to 5.1 since v2.1.255; flagged biology falls back to Opus 5 and cyber to Opus 4.8; fast mode is unsupported and `/fast` switches the session to Opus 5. Fable 5.1 is credit-billed; `-p` bills without a consent prompt. Routing implication: Opus 5 stays the included default; use Fable 5.1 for long-horizon / hardest work or when Opus 5 at higher effort still falls short, matching Anthropic's positioning.

### Late July 2026 — Opus 5 lands [A]

**Claude Opus 5 shipped 2026-07-24 [A]** — new Opus flagship, ID `claude-opus-5`, $5/$25 per Mtok (unchanged from 4.8), 1M ctx native (no `[1m]` suffix needed; Max auto-upgrades), 128k output, **knowledge cutoff May 2026** — newest of any Claude until Fable 5.1's Jun 2026 (see Early September above), ahead of Fable 5's Jan 2026. Positioning: **~Fable 5 intelligence at half price** — within 0.5% of Fable 5 on CursorBench 3.2 at max effort, doubles Opus 4.8's Frontier-Bench v0.1 score at lower cost per task, beats Fable 5 on some coding/knowledge-work evals; clearly behind only on bio/cyber (Mythos 5 domain). **Default model on Claude Max, strongest on Pro — included in subscription**, while Fable 5 stays credit-gated at $10/$50. Effort ladder `low→xhigh→max`, **default `high`** on API and Claude Code (only 4.7 ever defaulted `xhigh`; an explicitly set level carries over on Opus 5). Fast mode: 2.5× speed at 2× base price. New betas: mid-conversation tool changes, automatic fallback routing. **No data-retention requirement** (vs Fable 5's 30-day rule); cyber classifiers intervene ~85% less than on Fable 5. Claude Code category-based fallback (requires v2.1.219+): Opus 5 cyber-flag → re-runs on Opus 4.8; biology-flag → refusal (no fallback). Opus 4.8 moves to the legacy table; Opus 4.1 retirement (2026-08-05) now migrates to Opus 5. Leaked ~07-09 as "Honeycomb EAP" in Cursor's model picker [C/D]. Routing implication: Opus 5 is the new default for frontier work on subscription; reach for Fable 5 (credits) only when the last 0.5–x% matters.

### Mid-July 2026 — tier shuffle + CLI landscape reshuffle [A]

**Fable 5 restored, then credit-gated [A]** — supersedes the June suspension note below: access was restored and included on Pro/Max/Team/premium-Enterprise (≤50% of weekly limit) through **2026-07-12** (extended from 07-07 after backlash). After that, Fable 5 moved to **prepaid usage credits at $10/$50 per Mtok** (top of Anthropic's list; $2k/day redemption cap; no grace period if credits aren't enabled). Anthropic states it returns to subscriptions "when capacity allows." ~~Opus 4.8 remains the included frontier~~ **SUPERSEDED — Opus 5 (07-24) is the included flagship, see Late July above**; Fable 5 is usable but metered. Claude Code's `switchModelsOnFlag` (settings.json boolean, default `true`) silently falls back Fable→Opus on safety-classifier flags — set `false` for an explicit pause-and-choose instead.

**GPT-5.6 shipped 2026-07-09 [A]** — no longer rumor. Three tiers: **Sol** (flagship, 372k ctx), **Terra** (½ Sol's credit cost), **Luna** (⅕). Effort ladder `low/medium/high/xhigh/max/ultra` — `ultra` auto-delegates to subagents, Pro/Business-only. The Codex 0.153.4 catalog defaults Sol to **`low`**, Terra and Luna to **`medium`** (verified locally, 2026-09-07). Benchmarks split by job: Sol leads Terminal-Bench 2.1 (88.8%) and AA Coding Agent Index (80), but trails on **SWE-bench Pro (64.6% vs Opus 4.8's 69.2%, Fable 5's ~80%)** [A/B]. **METR flagged Sol's detected reward-hacking rate as the highest of any public model it has assessed** — discount Sol's benchmark wins accordingly [B]. Rough parity heuristic (no calibrated cross-vendor effort mapping exists): Sol@high ≈ Opus 4.8@xhigh for agentic work; Sol@xhigh/max ≈ Fable-5 class, benchmark-dependent [B/D].

**Gemini CLI retired 2026-06-18 [A]** — confirmed sunset (free/Pro/Ultra tiers stopped serving; live calls fail with eligibility errors). Replacement: **Antigravity CLI (`agy`)** — Go binary, **closed-source so far** (a regression from Gemini CLI), multi-model in one terminal (Gemini 3.8/3.7/3.6 Flash / 3.1 Pro, Claude Sonnet/Opus 4.6, GPT-OSS 120B), Google-grounded search built in. Config in §12.

**xAI Grok Build CLI [A/C]** — `grok-4.6` model (500k ctx; `grok-build` is a rolling alias that tracks the current build — pin the versioned id for determinism). **Native X search tools** (`x_keyword_search`, `x_semantic_search`, trend research) — the only mainstream coding CLI that can query X content. Deep Claude-compat: reads `~/.claude/skills/`, `~/.claude/agents/`, `CLAUDE.md`, and `settings.json` permissions natively — zero re-wiring. Reported open-sourced ~2026-07-15 [D]. Config in §12.

**Loop engineering goes mainstream [B/C/D]** — "loop engineering" is being named the successor discipline to prompt engineering (ADTmag 2026-07-01 [D]; "Stop Hand-Holding Your Coding Agent" arXiv:2607.00038 [B]; "Harness Engineering for Agentic AI Coding Tools" exploratory study, AIware '26 [B]). The season's mental model is a 4-layer onion — *prompt → context → harness → loop* — with leverage moving outward. Corollary now widely reproduced: **harness choice swings benchmark scores as much as model choice** (Terminal-Bench harness bakeoffs; same-model cross-harness gaps of tens of points) [C/D]. Every major CLI now ships a native loop primitive: Claude Code `/goal` (v2.1.139, 2026-05-12) + `/loop`, Codex `/goal`, Grok `--check`. X-practitioner orthodoxy converged on §17's existing discipline: separate verifier ("never self-grade"), persist state to disk, isolate worktrees, external stop conditions — the wave validates it, no doctrine change needed.

**Framework maturation wave [A/D]** — Pydantic AI v2.0 (capability bundles), LlamaIndex Workflows 1.0 (event-driven agent pipelines), Mastra Goals/Gates/Verdicts, Microsoft Agent Framework BUILD-2026 additions (Agent Harness, CodeAct, Hosted Agents). LangChain's "State of Agent Engineering" reports 57% of surveyed orgs with agents in production [D].

**Kimi K3 launched 2026-07-16 [A/C/D]** — API live (Moonshot, OpenRouter; $3/$15 per Mtok, cached input $0.30); **weights promised by 07-27** (not yet downloadable), Modified-MIT expected. 2.8T MoE (16/896 experts active), 1M ctx, KDA linear-attention hybrid, native multimodal. Independent placement (Artificial Analysis): Intelligence Index 57 — **near Opus 4.8, behind Fable 5 and GPT-5.6 Sol**; #1 Frontend Code Arena and #1 on Vercel's Next.js agent evals (first open model to lead it). Vendor coding charts (Terminal-Bench 88.3 etc.) ran on Moonshot's own harness — treat per the 10–15% harness-swing rule. **"Drop into any harness" is overclaimed [C]**: OpenAI-compatible API works, but K3 expects *preserved thinking history*; third-party harnesses (Claude Code path is Moonshot-documented, OpenCode) report behavior fragmentation, ~3× latency, and heavy rate-limit burn. AA also measured **hallucination regression** (39%→51% on Omniscience). Self-hosting at 2.8T = multi-node H200/B200 class, not workstation. Verdict: real frontier-adjacent open model at ⅓ Sol's price, but wait for weights + independent SWE re-runs + harness fixes before routing work; re-check after 07-27.

### June 2026 — the frontier moved twice [A]

**Claude Opus 4.8 (2026-05-28) [A]** — same price as 4.7. Effort ladder `high` (default) → `xhigh` → `max`; `high` is the recommended default ("best overall balance"), `xhigh`/`max` are per-task opt-ups for hard work. ~4× less likely than 4.7 to let a flaw in its *own* code pass unremarked (the honesty/self-flagging gain). **Dynamic workflows** (research preview) — Claude writes a JavaScript orchestration script run in a background runtime; see §17.3. **Fast mode** (research preview, `speed: "fast"`) ~2.5× faster output at higher per-token cost — a speed/cost knob **separate from effort** in supported surfaces; **effort still controls reasoning depth**, so fast + xhigh can run together.

**Claude Fable 5 / Mythos 5 (2026-06-09) [A]** — a capability tier *above* the Opus class. Fable 5 = the GA, safeguarded Mythos-class model ("safe for general use"), with capability-gated **fallback to Opus 4.8** on cyber/bio-chem/distillation classifiers; Mythos 5 = limited (Project Glasswing / US-gov). **Announced GA 2026-06-09, then access disabled 2026-06-12 for all customers by US-government directive** (per Anthropic's own access notice; other Anthropic models unaffected). ~~Do not target Fable 5 / Mythos 5 until restored~~ **SUPERSEDED — see Mid-July 2026 above: restored, subscription-included through 07-12, usage-credits after.** **Superseded by Fable 5.1 (2026-09-01), see Early September above** — Fable 5 remains served (legacy table).

**GPT-5.6 = RUMOR [A/D]** — ~~not officially announced as of 2026-06-16~~ **SUPERSEDED — shipped 2026-07-09, see Mid-July 2026 above.** Codex's Goal mode (`/goal`) became GA / first-class in May (no longer experimental, available in CLI/app/IDE).

**Codex → automation substrate [A]** — Codex grew past "CLI pair-programmer": `/goal` (loops to objective-or-budget), app-server, non-interactive mode, GitHub Action, scheduled automations, browser/devtools mode. "Loop" moved out of the chat UI into programmable orchestration. Codex's own `/goal` GitHub issues are empirical warnings — both premature stop *and* runaway loop when blocked.

**Google → Antigravity [A]** — Google is unifying its tooling into Antigravity; some Gemini CLI / Code Assist consumer tiers sunset 2026-06-18. Gemini 3.6 Flash GA 2026-07-21 for agent mode; 3.7 Flash serving in agy and GitHub Copilot by 2026-08 (agy default 2026-08-24 to 2026-09-03); **Gemini 3.8 Flash GA 2026-09-02** with effort low/medium/high, Google default and recommendation **medium** (high maximizes reasoning/tool orchestration at more tokens and latency; ~3 pts on DeepSWE v1.1, 74 vs 71 [C]) — agy default `Gemini 3.8 Flash (High)` since 2026-09-03, a deliberate opt-up for the research seat rather than the vendor default. Antigravity is the platform to watch; Gemini CLI may be transitional.

**Benchmark methodology pivot [A/B]** — OpenAI deprecated SWE-bench Verified (saturated ~80%, six-way tie, contamination) in favour of **SWE-bench Pro** (use Scale's primary leaderboard, not aggregators) + contamination-resistant live benches (SWE-rebench, SWE-bench-Live). Treat **sub-3pp deltas as noise** (Anthropic infra-noise paper); METR time-horizons **>16h are unreliable** with current task suites. The productivity-uplift question is genuinely *unsettled* (METR has since qualified the earlier "~20% slowdown" framing on selection-bias grounds [B]).

**Long-horizon still degrades [B]** — short-horizon bench gains do NOT imply long-horizon capability. SWE-EVO / SlopCodeBench show multi-file, multi-session evolution remains weak and quality erodes monotonically over long runs. **Do not infer "thousands of agents overnight" autonomy from issue-fix benchmarks.** Pair any long loop with the §17.5 guardrails.

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

