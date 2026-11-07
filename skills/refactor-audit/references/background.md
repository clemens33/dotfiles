# Refactor Audit — background

Read when justifying the audit method to a reviewer. Nothing here changes the decision rule in `SKILL.md`.

## Practitioner references

- `KNOWLEDGE.md` §18 — practitioner refs for the SOTA voices cited (Hashimoto harness engineering, Sourcegraph/Amp completeness, Anthropic 2026 "generated code is debt").

## SOTA grounding

- **Hashimoto harness engineering** — every repeated soft signal becomes a guardrail (CI check, lint rule, or tool) or an accepted/documented exception. The audit is the bootstrap mechanism.
- **Sourcegraph/Amp completeness lens** — missed callers and cross-repo surprises are drift signals; grep is not enough on large codebases.
- **Anthropic 2026 Trends Report** — "generated code is debt until validated." Refactor is debt repayment; this audit prioritizes which debt to repay.
- **Pi/minimal-agent counter-take** — the durable solution is making drift observable via tooling, not a recurring process. Use this skill to bootstrap guardrails, then retire its scope as guardrails mature.
