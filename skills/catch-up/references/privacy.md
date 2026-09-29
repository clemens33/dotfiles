# Privacy: classify before every fresh read

Two things are classified BEFORE any state is read: the SOURCE (a
session, or a repo outside ae) and the ROUTE (where the running model
is hosted). Both need POSITIVE evidence. Absence of a warning sign
proves nothing.

**No blanket exemption for the current session.** The source and route
checks run before EVERY fresh state read: memos, events, notes, git
history of the current session and repo included. A fresh worker, a seat
whose route changed, or a model that never loaded those memos does not
already hold them.

- The only exempt material is what is ALREADY present in the current
  conversation. Summarising that adds no exposure.
- When the current session is excluded by the table, the output says so:
  "limited coverage: this session is classified `<x>`, this seat's route
  is `<y>`; only what is already in this conversation is summarised".

## Source classification

Each session is `personal`, `work`, or `mixed`.

- The only accepted evidence is an explicit entry the HUMAN made in a
  local policy file outside every repo: `~/.config/catch-up/policy.toml`,
  table `[sessions]`.
- A path outside `~/projects/mic/` does NOT prove `personal`. Session
  `dotfiles` itself holds a private overlay and mixed work notes.
- `mixed` is treated as `work`.
- No entry = `unknown`.

## Route classification

Each route is `work-ok`, `personal-only`, or `unknown`. A route is
bound to the EXACT profile command string — never to a broad label.

1. Read `profile.<slot>` for this seat from the session `meta`.
2. Read that profile's exact command from `[profiles]` in
   `~/.ae/config` (only `[profiles]` rows — nothing else in that file).
3. Look up the EXACT command string as the key in table `[routes]` of
   the policy file. Exact match classifies; anything else is `unknown`.

- A model name in a pane header alone does NOT prove where it is hosted.
- A changed command is a NEW route: if the seat's current command
  differs by even one character from the classified string, the lookup
  misses and the route is `unknown`. Fail closed — never fuzzy-match,
  never fall back to a label. The human classifies the new string.
- No evidence or no entry = `unknown`.

The gate reads themselves (own seat's profile slot, `[profiles]` rows,
policy file, git-toplevel realpath outside ae) are permitted before
classification — they ARE the gate. Everything else (memos, events,
notes, git history) is fresh state.

## Decision table

| Source | Route | Action |
|---|---|---|
| `personal` | any | read |
| `work` or `mixed` | `work-ok` | read |
| `work` or `mixed` | `personal-only` or `unknown` | EXCLUDE |
| `unknown` | any | EXCLUDE; never inspect content to decide |

## Outside ae (no session)

- The repo is classified by table `[repos]`, separate from `[sessions]`.
  Key = canonical absolute git toplevel (`git rev-parse --show-toplevel`,
  resolved with realpath). Value = human-written `personal`, `work`,
  or `mixed` (`mixed` treated as `work`). No entry = `unknown`.
- Outside ae the route is ALWAYS `unknown`: v1 has no positive non-ae
  route evidence.
- The existing decision table applies with repo as source: a `personal`
  repo reads; a `work`/`mixed`/`unknown` repo is EXCLUDED with the plain
  line "run inside an ae session, or this repo stays excluded".
- If this repo has no entry, ask ONCE for THIS repo path only — never a
  sweep of other paths.
- Already-in-conversation material stays exempt.

## Behaviour

- Excluded sessions are listed in the header by NAME only, with the
  reason.
- If the policy file is missing or has unclassified sessions: list their
  names, then ask the human ONCE, as one numbered list, to classify
  them. Write the file only from his answer. Never guess an entry.
  Until he answers, read nothing fresh.
- Summaries inherit the sensitivity of their sources. A sample or digest
  of a `work` session is `work`.
- Never print secrets, tokens, chat ids, or credentials-file contents.
  Never read `auth.json` or credentials files. From `~/.ae/config` read
  only `[profiles]` rows.

## Policy file template

Create `~/.config/catch-up/policy.toml` ONLY from the human's answers.
Example names only — never real session names in this repo:

```toml
# Written only from the human's answers. Never guessed.
[sessions]
# example-web = "personal"   # side project, safe anywhere
# example-job = "work"       # employer work
# example-both = "mixed"     # treated as work

[routes]
# Key = the EXACT ae profile command string, as classified by the
# human. Broad labels are forbidden: a changed command is a new route
# and fails closed to unknown until classified. Example shape only:
# "example-agent --model alpha" = "work-ok"      # employer-approved
# "example-agent --model beta"  = "personal-only" # never sees work

[repos]
# Key = canonical absolute git toplevel (realpath), human-written.
# Outside ae the route is always unknown, so only personal repos read.
# "C:/Users/example/sideproj" = "personal"
# "/Users/example/work-proj"  = "work"
```
