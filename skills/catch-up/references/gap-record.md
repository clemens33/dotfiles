# Gap record

Reuse the LOCATION and general format of `quiz-diff`'s gap record, but
this is not a diff.

## Storage

Append to `.local/comprehension/log.jsonl` (`.local/` is gitignored),
one JSON object per run:

```json
{"ts": "<ISO>", "skill": "catch-up",
 "branch_label": null, "base": null, "head": null, "diff_hash": null,
 "sessions": [{"session": "<name>", "cutoff": "<exact cutoff value>",
              "cutoff_source": "<last-run|human-input|24h-fallback>",
              "as_of": "<ISO>"}],
 "concepts": ["..."],
 "items": [{"construct": "...", "outcome": "correct|partial|incorrect|invalid",
            "challenged": false, "evidence": ["session:source"]}],
 "gaps": ["one-line descriptions of what was missed"]}
```

- Git fields (`branch_label`, `base`, `head`, `diff_hash`) are nullable.
  NEVER fabricate a SHA.
- Fingerprint = truthful source snapshot: sessions read, cutoff, as-of
  time. Skip hash-staleness checks when git fields are null.
- Store the gap (what his picture missed), not his raw answer text.

## Compatibility with quiz-diff

A quiz-diff reader that ignores unknown keys (`skill`, `sessions`) reads
catch-up entries as gap records with null git fields. quiz-diff entries
keep their git fingerprint and are unaffected. The two skills share one
log; the `skill` key tells them apart.
