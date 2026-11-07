# Large feature — provenance

Moved from `SKILL.md`: the source-tier legend, the per-stage evidence tags, the quotes behind Stages 2 and 3, what is novel here, the cross-references and the sources. None of it changes a rule in `SKILL.md`. Read it when justifying the playbook or checking a stage against its source.

## Tag keys

Stage tags (how well supported a stage is, as of May 2026):

- 🅐 documented practitioner pattern — explicit in named sources
- 🅛 local repo doctrine — formalized in `shared/AGENTS.md` / `WORKFLOW.md` / `KNOWLEDGE.md`
- 🅡 research-backed adjacent — research supports the concept; the specific shape is interpretation
- 🅔 experimental synthesis — extrapolation from neighboring patterns, not yet documented

Source tags in the list below: [A] official vendor, [B] academic, [C] practitioner, [L] local repo doctrine.

## Stage tags

| Stage | Tags |
|---|---|
| 0 Sharpen via `grill-with-docs` | 🅐 🅛 |
| 1 Plan + critique (preflight 🅐) | 🅐 🅛 |
| 2 Tracer-bullet slices | 🅐 (strongly supported; Pocock `to-issues`, archived in `skills-retired/`, is the canonical shape) |
| 3 Red-green-refactor, strict isolation | 🅐 🅡 🅛 (TDD core strongly supported; targeted test selection 🅡; spec-first 🅛; micro-refactor 🅐) |
| 4 Trigger-based drift checks | 🅡 🅛 (concept supported; a fixed cadence is opinion, so it is not hard-coded) |
| 5 Final integration | 🅐 🅛 |
| 6 Architecture refactor as separate cadence | 🅛 |
| Context & handoff | 🅛 |
| Codebase intelligence | 🅡 |
| Harness engineering | 🅐 |
| Security / dependency / license gate | 🅛 |

## Quotes behind the rules

- Stage 2, ai-hero.dev: *"AI wants to produce complete solutions all at once… Force the agent to think small, build end-to-end, get feedback, and move forward with confidence."*
- Stage 3, Tweag agentic-coding-handbook: *"Each phase runs in complete isolation: the test writer focuses purely on test design, the implementer sees only the failing test, and the refactorer evaluates clean implementation code. This isolation is the only way to get genuine test-first development from an LLM."*
- Targeted test selection: TDAD (arxiv:2603.17973) finds that naming the specific impacted tests beats a generic "run tests". Its result depends on an explicit dependency map or impact-analysis tool, which this repo does not have; a manually guessed impact set is weaker.
- Preflight: Willison's first-do-no-harm pattern (run the existing validation commands before any change). Plan/execution split: Hashimoto.
- Greenfield without a spec: upstream Pocock also offers `to-prd`, `to-issues` and `prd-to-plan` / `plan-from-prd`. `to-prd` and `to-issues` are archived in `skills-retired/`; the others were never vendored.

## What is novel here versus published practice

- 🅛 Spec-first cross-model authoring (Stage 3) — was 🅔 experimental; now local doctrine (`shared/AGENTS.md`, default M/L).
- 🅛 Architecture-deepening refactor as a separate cadence, with an explicit micro-refactor allowance inside TDD (Stage 6 + Stage 3) — local doctrine that resolves the apparent contradiction between "refactor inside features" and "separate architectural work".
- 🅛 Per-slice acceptance contract template — combines Pocock `to-issues`, Hashimoto harness engineering and Willison test-first into one artifact per slice.

Everything else is a documented practitioner pattern or research-backed adjacent work.

## Cross-references

- `WORKFLOW.md` — the operating doctrine; this playbook is its optional deep path for L features
- `KNOWLEDGE.md` §18 (References / Practitioner references) — cited voices
- `shared/AGENTS.md` — the cross-model contract that Stages 1 and 5 enforce
- `skills/tdd/` — the TDD loop (Stage 3 core); `skills/grill-with-docs/` — Stage 0; `skills/scope/` — Stage 1 plan
- `skills/security-review/`, `skills/gha-security-review/` — security gate
- `skills/diagnose/` — bug-shaped tasks; use this playbook's structure if a bug needs L-scale work

## Sources

- Matt Pocock — `tdd` skill (vendored); `to-issues`, `to-prd` (archived in `skills-retired/`); `tracer-bullets`, `prd-to-plan`, `plan-from-prd` upstream-only [C]
- ai-hero.dev — "Tracer Bullets: Keeping AI Slop Under Control" [C]
- Simon Willison — Agentic Engineering Patterns / Red-Green TDD [C]
- Tweag — Agentic Coding Handbook, TDD workflow — https://tweag.github.io/agentic-coding-handbook/WORKFLOW_TDD/ [C]
- arxiv:2603.17973 — "TDAD: Test-Driven Agentic Development — Reducing Code Regressions in AI Coding Agents via Graph-Based Impact Analysis" [B]
- arxiv:2604.26615 — "TDD Governance for Multi-Agent Code Generation via Prompt Engineering" [B]
- Hora et al. — "Are Coding Agents Generating Over-Mocked Tests?" [B]
- Mitchell Hashimoto — My AI Adoption Journey (harness engineering) [C]
- Addy Osmani — Long-running agents (handoff patterns) [C]
- Boris Cherny — "Always give Claude a way to verify its work" [A]
- Armin Ronacher — judgment-not-abdication; manual QA / taste pass [C]
- Anthropic 2026 Agentic Coding Trends Report [A]
- `shared/AGENTS.md` Cross-Model Collaboration section [L]
- `WORKFLOW.md` L bucket + Long-running mode [L]
