# Collab — templates

Relocated verbatim from `SKILL.md`. Read when writing or reviewing a round artifact. The artifact taxonomy, rules, decision log and completion gate stay in `SKILL.md`.

### Position template (`<agent>.md`)

```md
# Position
Artifact type: position

## Proposed Decisions

1. ...
2. ...
3. ...

## Open Questions

1. ...
2. ...
```

### Research note template (`<agent>_<topic>.md`)

```md
# <Topic> Analysis (<Agent>)
Artifact type: research-note

## Findings

...

## Implications for Design

...
```

### Review template (`*_review.md`)

```md
# Review
Artifact type: review

Reviewed file: rounds/rN/<other>.md

Observed:
- rounds/rN/<other>.md @ <sha or timestamp>

1) Point 1: agree/disagree + rationale
2) Point 2: agree/disagree + rationale
3) Point 3: agree/disagree + rationale

Open items:
- ...
```

### Signoff template (`signoff_*.md`)

```md
# Signoff
Artifact type: signoff

Observed:
- rounds/rN/merged.md @ <sha or timestamp>

Consistency check:
- [ ] All referenced files exist
- [ ] PLAN.md reflects latest merge
- [ ] DECISIONS.md has no gaps
- [ ] No dangling unresolved items

Coverage:
- Review point 1 -> addressed in section X
- Review point 2 -> dropped via D-003
- Review point 3 -> escalated via D-004

Status: APPROVED
```
