# Refactor Audit — background

Relocated verbatim from `SKILL.md`. Read when justifying the audit method to a reviewer, or when checking a draft audit against the failure modes below. Nothing here changes the decision rule in `SKILL.md`.

## Anti-patterns that restate rules in SKILL.md

- **Cadence-without-signal busywork** — don't run the audit on a calendar if no signals fired; you'll either find nothing (waste) or invent something (worse).
- **Big-bang structural refactor** — if recommendation is L, slice it like any other L feature (`large-feature` Stage 2).
- **Treating tooling-gap signals as fired** — they're not measured yet. They count toward guardrail candidates, not toward the decision rule.
- **Inventing thresholds** — no universal "20% slower" / "10% coverage drop" — always compare against the repo's own baseline. If no baseline exists, record that explicitly.

## Practitioner references

- `KNOWLEDGE.md` §18 — practitioner refs for the SOTA voices cited (Hashimoto harness engineering, Sourcegraph/Amp completeness, Anthropic 2026 "generated code is debt").

## SOTA grounding

- **Hashimoto harness engineering** — every repeated soft signal becomes a guardrail (CI check, lint rule, or tool) or an accepted/documented exception. The audit is the bootstrap mechanism.
- **Sourcegraph/Amp completeness lens** — missed callers and cross-repo surprises are drift signals; grep is not enough on large codebases.
- **Anthropic 2026 Trends Report** — "generated code is debt until validated." Refactor is debt repayment; this audit prioritizes which debt to repay.
- **Pi/minimal-agent counter-take** — the durable solution is making drift observable via tooling, not a recurring process. Use this skill to bootstrap guardrails, then retire its scope as guardrails mature.
