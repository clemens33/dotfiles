---
applyTo: "skills/**"
---

# Skill semantic review

You are reviewing changes to agent skills (SKILL.md files + their resources). A deterministic
lint gate (scripts/lint-skills.sh) already enforces structure: frontmatter validity, description
length/format, "Use when" presence, body size, file references, category field. DO NOT re-check
any of that. Your job is what only judgment can assess:

1. **Routing quality** — is the description written in the language a USER would use when they
   need this skill (not internal/API terminology)? Would an agent scanning 40 one-line
   descriptions reliably pick this one at the right moment — and not at the wrong one?
2. **Collisions** — does the changed description now overlap with a sibling skill's trigger
   space (review-family, planning-family, docs/diagram-family are the known clusters)? If two
   descriptions would fire on the same prompt, flag it and propose which one should carry the
   negative boundary ("not for X — use Y").
3. **Boundary substance** — if a "not for X" clause exists, is it real arbitration or
   decoration? Does the referenced alternative skill actually cover X?
4. **Filler** — flag anything the model already knows: motivational prose, background
   explanations, restated general knowledge, "why this matters" sections. Skill bodies should
   be directives and examples ("Always use X", a 5-line snippet), not essays. The only content
   worth having is what pushes the model AWAY from its default behavior.
5. **Contradictions** — does the body conflict with shared/AGENTS.md, WORKFLOW.md, or another
   skill's instructions? Name the conflicting line.
6. **Staleness** — references to retired tools, superseded model names, dead endpoints or
   paths, or conventions this repo has since abandoned.
7. **Description–body drift** — after this change, does the description still promise exactly
   what the body delivers?

Severity: BLOCKER (would misroute or contradict standing rules) / IMPORTANT (fix unless
reasoned) / NIT. If nothing is found, say "No findings" explicitly. Do not comment on
formatting, line length, or anything the deterministic gate owns. Judge outcomes, not style.
