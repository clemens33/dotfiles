# Skill evaluation lane

Small, dependency-free evaluation of the skill catalog: does a model route the
right skill(s) for a request, and do a few skill-guided tasks still produce a
checkable outcome? It compares the **committed catalog** (public `HEAD` plus
the overlay's own `HEAD`) with the **current worktree** without modifying
either tree, and records enough metadata to make a run reproducible.

Runner: `scripts/eval-skills.py` (Python 3 stdlib, runs on `/usr/bin/python3`
3.9 and newer). Self-test: `scripts/eval-skills-test.sh`.

## What it measures, what it does not

* `run` is a **catalog-prompt simulation**: the catalog text (`- name (kind):
  description`) is embedded in a prompt and the model answers with a JSON
  selection. Same model, same prompt template, both sides. This is an A/B of
  the catalog text only. It is **not** the harness's native routing: Claude
  Code, Codex, Grok and Antigravity each list skills differently, add their
  own bundled skills (Claude Code lists ~60 slash commands, 44 of them ours)
  and apply their own heuristics.
* `native-check` drives the real harness with the raw request and observes
  the `Skill` / subagent tool calls in `stream-json`. It sees the **installed**
  skills (worktree via symlinks), has no HEAD counterpart and is noisy at low
  effort. Treat it as **direction-only** evidence.
* `evals/skills/fake_model.py` is a keyword lookup. The self-test proves the
  pipeline with it (fixtures, git reads, argv safety, timeouts, parsers,
  verdicts, result files). It proves nothing about any model or catalog.
* A low-cost model at low effort (the pilot setting) is a proxy for how a
  weak router reads the descriptions, not for what Fable/Opus/Astra do.
* Verifiers check outcome properties (parses, portable, states the required
  fact). They do not reward following a skill's wording.

## Layout

```
evals/skills/
  README.md
  fake_model.py            deterministic fake model (self-test only)
  routing/prompt.md        routing prompt template ({catalog}, {prompt})
  routing/cases.json       19 routing cases (trigger + adjacent negatives + composition)
  tasks/prompt.md          task prompt template ({skill}, {skill_body}, {prompt})
  tasks/cases.json         3 task-outcome cases with deterministic verifiers
scripts/eval-skills.py     runner
scripts/eval-skills-test.sh self-test (fake model; prints its pass/fail count)
.local/eval-skills/        results (default; writing elsewhere needs --allow-outside-local)
```

## Commands

```bash
scripts/eval-skills.py check                     # fixtures resolve on both sides; PyYAML cross-check when importable
scripts/eval-skills.py catalog --side head       # the text a side shows (worktree | head)
scripts/eval-skills.py measure --codex-native    # description totals, prompt chars, live Codex skills block (+ HEAD replica)

# simulation, one side, one suite, model command after "--" (argv only, prompt on stdin)
scripts/eval-skills.py run --side head     --suite routing --output-mode claude-json -- <model argv>
scripts/eval-skills.py run --side worktree --suite routing --output-mode claude-json -- <model argv>
scripts/eval-skills.py run --side worktree --suite tasks   --output-mode claude-json -- <model argv>
scripts/eval-skills.py compare .local/eval-skills/<head-run> .local/eval-skills/<worktree-run> --md .local/eval-skills/compare.md

# native spot check (direction-only)
scripts/eval-skills.py native-check --case viz-adr-sequence -- claude -p --model haiku --effort low \
  --tools Skill --max-turns 1 --strict-mcp-config --no-session-persistence --output-format stream-json --verbose
```

Low-cost model commands that keep the harness out of the way. Run them with
`--model-cwd <empty dir>`: even with a replaced system prompt, `claude -p`
loads the working directory's CLAUDE.md and per-project auto-memory (only
`--bare` skips those, and `--bare` needs `ANTHROPIC_API_KEY`); an empty cwd
keeps repo instructions and memory out of the prompt, global config still
loads. The cwd is recorded and part of the compare equivalence check.

```bash
# Claude Code: no tools, no settings, no MCP, replaced system prompt; JSON envelope carries usage + cost
claude -p --model haiku --effort low --tools "" --setting-sources "" --strict-mcp-config \
  --no-session-persistence --output-format json \
  --system-prompt "You are a precise skill router inside a coding agent. Follow the user's message exactly; reply with the requested JSON only."
# Codex (--output-mode codex-jsonl); note Codex still injects its own installed-skills block
codex exec -m gpt-5.6-luna -c model_reasoning_effort=low -s read-only --skip-git-repo-check --ephemeral --json -
```

Flags: `--case ID` / `--lane NAME` / `--limit N` select cases; `--timeout S`
per call (default 120); `--save-prompts` / `--save-replies` keep the exact
texts; `--dry-run` writes prompts and calls nothing; `--strict` exits 1 on
any fail/error (for CI-style use); `--no-overlay` ignores `dotfiles-mic`;
`--overlay-ref` picks another overlay ref for the head side (default: the
overlay's own `HEAD`; the public gitlink is recorded alongside).

## Fixture schemas

Routing case:

```json
{"id": "viz-adr-sequence", "lane": "diagram",
 "prompt": "Add a sequence diagram ... to docs/adr/0007-auth-tokens.md so it renders on GitHub.",
 "expect": ["viz"], "allow": ["adr"], "forbid": ["drawio-diagrams-enhanced"], "note": "..."}
```

* `expect`: every item must be selected; a nested list means any one of them.
* `allow`: optional companions (correct multi-skill composition).
* `forbid`: must not be selected.
* Any selection outside `expect` + `allow` is a stray load and fails the case.
* Write cases from user intent, with adjacent negatives for each pair, so
  they stay fair to any wording of the descriptions.

Task case:

```json
{"id": "mcp-scaffold-stdio-ping", "lane": "mcp", "skill": "mcp-server",
 "include": ["reference/*.md", "scripts/*.py"],
 "prompt": "Write the complete minimal server module ...",
 "verify": {"extract": "fence:python", "parse": "python",
            "must": ["FastMCP\\(", "def ping\\b"], "must_not": ["transport\\s*=\\s*[\"']http"]}}
```

* The skill body (and `include` files, capped by `--include-cap`) is read from
  the side under test, so HEAD and worktree can differ in content.
* `extract`: `all` or `fence:<lang>`; `parse`: `python` (ast); `must` /
  `must_not`: regexes (`re.M|re.S`, `flags: "i"` adds case-insensitivity).

## Results

Each run writes `.local/eval-skills/<utc-stamp>-<side>-<suite>/`:

* `meta.json`: run id, refs (public HEAD, overlay HEAD, public gitlink, dirty
  catalog paths per tree), catalog summary and sha256, fixture sha256, model
  argv / label / provider / harness / version, output mode, timeout, python,
  platform, totals (pass/fail/error, elapsed, tokens, cost when exposed).
* `results.jsonl`: one record per case: status (`ok`, `malformed`,
  `timeout`, `exit:N`, `error`), verdict, reasons, selection, prompt sha256,
  elapsed, usage, cost, models used, stderr tail.
* `summary.md`: the table, with the simulation caveat.

`compare` joins two runs by case id and classifies `REGRESSION` (pass then
fail), `FIXED`, `SAME`, `ERROR`, `MISSING`, plus per-lane pass counts and the
budget numbers of both catalogs. It is **INVALID** (exit 2, no verdict
table without `--allow-mismatch`) unless both runs share suite, fixture and
template hashes, model label, provider, harness and harness version, output
mode and argv, all of them known: pass `--model-label` / `--provider` on
`run` when they cannot be inferred. Where the harness exposes the served
model (`claude -p` JSON `modelUsage`), the served-model sets must match too:
a requested alias can fall back to another model, and argv cannot show that.
Without that data the report carries an "equivalence gap" line. Sides are
expected to differ.

## Pilot protocol

1. `scripts/eval-skills.py check` and `scripts/eval-skills-test.sh` green.
2. `measure --codex-native --json <path>` before and after the catalog edits
   (record, do not copy earlier numbers).
3. Same low-cost model and prompt on both sides, at most 20x2 routing
   selections; task suite 3x2. Keep `--save-replies` for the record.
4. `compare` head vs worktree; read every REGRESSION, then every FIXED.
5. Three `native-check` spot checks; report as direction-only.
6. Decide from the measurements. There is no universal catalog-size gate.
