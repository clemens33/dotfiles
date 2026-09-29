# Capture mode: record his ideas

Trigger: the human drops an idea mid-work. Phrases include "idea:",
"spark", "note this", "park this".

## Procedure

1. Record at once (rules below).
2. Give a one-line take. Name a flaw if there is one.
3. Continue the current work unless he asks to act now.

## Record rules

- ONE idea-record owner per session. In ae that is the session's lead
  seat; any other agent SENDS the idea to the lead, who writes it.
  Outside ae it is the single agent.
- Store: ae memo topic `ideas` (one checkpoint record holding the
  running list), or `.local/ideas.md` outside ae.
- Gate FIRST: re-reading the checkpoint is a fresh state read. Run the
  source + route classification (`references/privacy.md`) before
  opening it. If this source (session or repo) is EXCLUDED: do not read
  or rewrite the record — tell the human plainly the idea remains
  uncaptured pending classification, and keep his words in the
  conversation so nothing is lost.
- Serialize every update from the LATEST checkpoint: re-read the record,
  append, write back. A rewrite must carry every earlier item forward.
  Verify the item count before and after — a count drop means a lost
  item; stop and recover.
- Each idea has:
  - a stable ID (e.g. `I-20260929-1`)
  - the ORIGINAL capture time, never rewritten
  - his words, shortened
  - status: acted on / in progress / parked / not picked up / unknown
  - status evidence (commit, memo, message id)
- Capture happens only in the session the human is talking to. Never
  write another session's record.

## Reading ideas back (brief mode)

Promise only RECORDED ideas. If a session has no record, say "no idea
record here; ideas dropped before capture existed are not listed".
Status without evidence = `unknown`. Transcript scanning is out of scope
for v1.
