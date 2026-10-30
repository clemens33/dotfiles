# Scope — plan template

Relocated verbatim from `SKILL.md` (Output format). Use it as the skeleton of the plan document; the complexity levels, phase rules and out-of-scope duty stay in `SKILL.md`.

```markdown
## Scope: <task title>

**Goal:** <one sentence — what "done" looks like>
**Complexity:** trivial | moderate | complex | needs-spike
**Estimated phases:** <N>

### Change surface

| Path | Action | Notes |
|------|--------|-------|
| `src/foo.py` | modify | add new endpoint |
| `tests/test_foo.py` | create | cover new endpoint |
| `db/migrations/003.sql` | create | add column |

### Risks & unknowns

- <risk 1: description + mitigation>
- <risk 2: description + mitigation>
- <unknown 1: what needs investigating + how>

### Rollout & operability

- **Rollout strategy:** big-bang | feature flag | gradual | canary
- **Rollback plan:** <how to revert if things go wrong>
- **Observability:** <logging, metrics, or alerts to add/modify>
- **Backward compatibility:** <API consumers, queued jobs, cached data affected?>

### Phases

#### Phase 1: <title>
- **Do:** <what to implement>
- **Files:** `path/a`, `path/b`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** none

#### Phase 2: <title>
- **Do:** <what to implement>
- **Files:** `path/c`, `path/d`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** Phase 1

#### Phase 3: <title>
- **Do:** <what to implement>
- **Files:** `path/e`
- **Complexity:** trivial | moderate | complex
- **Test gate:** <how to verify>
- **Depends on:** Phase 1, Phase 2

### Verification

- <end-to-end check 1>
- <end-to-end check 2>
- <manual smoke test description>

### Out of scope

- <thing explicitly NOT included>
- <follow-up work for later>
```
