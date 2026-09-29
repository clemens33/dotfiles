# Brief mode reference

## Cutoff (three different things, never mix them)

- **Last catch-up in this session:** preferred cutoff. The skill records
  its own run time: in ae, memo topic `catch-up` (current session only —
  in mode `all`, never write a source session's marker); outside ae,
  `.local/catch-up/last-run`.
- **Last human input:** use only if evidenced (harness or ae evidence).
- **Last commit:** git authorship does NOT prove human input, since
  agents commit under his name. Never use it as evidence of his presence.

Per session: state which cutoff was used and its source. If none can be
evidenced, use 24 h and SAY SO.

Still-open decisions and ideas are always shown, whatever their age. A
new spark must not hide older unseen work.

## Finding waiting items (Needs you)

Sources: agent `ask`/`review` requests awaiting his reply, explicit
"waiting-user" states, open questions in memos and `.local/` notes, PR
review requests, things ready for him to try. Label each item DECIDE,
TEST, or ANSWER. Order most blocking first. When in doubt whether
something waits on HIM vs an agent, include it and say who you think
must act.

Each item is self-contained: one plain sentence on what it is about,
the options, what each option changes, the recommendation, where to
answer (session + agent). He answers hours later with no thread memory —
never "see above", never depend on an earlier message.

## While you were away

One entry per topic with change since the cutoff: one-sentence picture,
what changed (clock time), state, who works on it — session and agent
named on every item. For each thing HE asked for, state done or
not-done (with evidence), so he never has to ask "was this built?".
The "picture block" for consequential changes: what changed, one
observable effect, main failure risk, how he would notice, when to step
in. Unchanged topics collapse to one line each.

## Unattended now

Agents running without him. For each: the evidenced current activity
and the next irreversible step it is authorized to take (push, merge,
delete, send, deploy), if any. Read the brief or plan for authorization;
no invented worst cases. Include spawned workers nobody retired and
stuck/blocked agents.

## Check your picture

Default ZERO or ONE question, on the single most consequential change
(matches the contract rule "at most one optional prediction question").
More than one only when he explicitly asks for a deeper quiz.

- The question must test TRANSFER: predict an effect NOT stated above,
  never repeat an answer the brief just revealed.
- Non-blocking: he may skip it, nothing waits on it.
- If he answers: check against evidence, including whether the agents'
  picture is the wrong one.
- Record the gap per `gap-record.md`: store what his picture missed,
  not his raw answer text.
