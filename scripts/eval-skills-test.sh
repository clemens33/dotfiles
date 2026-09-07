#!/usr/bin/env bash
# Deterministic self-test for scripts/eval-skills.py using evals/skills/fake_model.py.
# Proves the pipeline (fixtures, catalog reading from HEAD and worktree, argv safety,
# timeouts, malformed-output rejection, output parsers, verdicts, result files,
# compare, native-check parsing). It proves nothing about any real model.
# Usage: scripts/eval-skills-test.sh   (exit 0 when all checks pass)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPT_DIR/eval-skills.py"
FAKE="$REPO_ROOT/evals/skills/fake_model.py"
PY="${PYTHON:-python3}"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
OUT="$TMPROOT/out"
PASS=0
FAIL=0

check() { # check <desc> <expected_exit> <actual_exit> <output> [<must_contain>]
  local desc="$1" expected="$2" actual="$3" output="$4" pattern="${5:-}"
  if [[ "$actual" -ne "$expected" ]]; then
    echo "FAIL: $desc (exit $actual, expected $expected)"; echo "${output//$'\n'/$'\n'    }"; FAIL=$((FAIL + 1)); return
  fi
  if [[ -n "$pattern" ]] && ! grep -q -- "$pattern" <<<"$output"; then
    echo "FAIL: $desc (output missing pattern: $pattern)"; echo "${output//$'\n'/$'\n'    }"; FAIL=$((FAIL + 1)); return
  fi
  echo "PASS: $desc"; PASS=$((PASS + 1))
}

latest_run() { ls -1d "$1"/*-"$2" 2>/dev/null | sort | tail -1; }

field() { # field <run_dir> <case_id> <json key>  -> prints the value
  "$PY" - "$1/results.jsonl" "$2" "$3" <<'PYX'
import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r["id"] == sys.argv[2]:
        v = r.get(sys.argv[3])
        print(json.dumps(v) if not isinstance(v, str) else v)
PYX
}

meta_total() { "$PY" -c "import json,sys; print(json.load(open(sys.argv[1]+'/meta.json'))['totals'][sys.argv[2]])" "$1" "$2"; }

# ---------------------------------------------------------------------------
# fixture validity + interpreter compatibility
# ---------------------------------------------------------------------------
OUT_TXT="$("$PY" "$RUNNER" check 2>&1)"; CODE=$?
check "check validates real fixtures against head and worktree catalogs" 0 "$CODE" "$OUT_TXT" "check: OK"
if [[ -x /usr/bin/python3 ]]; then
  OUT_TXT="$(/usr/bin/python3 "$RUNNER" check 2>&1)"; CODE=$?
  check "check also runs on /usr/bin/python3 ($(/usr/bin/python3 -c 'import platform;print(platform.python_version())'))" 0 "$CODE" "$OUT_TXT" "check: OK"
  if /usr/bin/python3 -c 'import yaml' 2>/dev/null; then
    check "PyYAML cross-check executed with 0 mismatches" 0 "$CODE" "$OUT_TXT" "frontmatters checked, 0 mismatches"
  fi
fi
OUT_TXT="$("$PY" "$RUNNER" catalog --side head 2>/dev/null)"; CODE=$?
check "catalog --side head reads skills from git HEAD" 0 "$CODE" "$OUT_TXT" "^- viz (skill): "
OUT_TXT="$("$PY" "$RUNNER" catalog --side worktree 2>/dev/null)"; CODE=$?
check "catalog --side worktree reads skills from disk" 0 "$CODE" "$OUT_TXT" "^- manage-skills (skill): "
OUT_TXT="$("$PY" "$RUNNER" measure 2>&1)"; CODE=$?
check "measure prints head/worktree budget table" 0 "$CODE" "$OUT_TXT" "codex rendered chars"

# ---------------------------------------------------------------------------
# verdict logic on a private fixture (argv-injection prompt included)
# ---------------------------------------------------------------------------
FIX="$TMPROOT/fixture"; mkdir -p "$FIX"
cp "$REPO_ROOT/evals/skills/routing/prompt.md" "$FIX/prompt.md"
INJ="\$(touch \"$TMPROOT/pwned\") \`id\` it's ; rm -rf --nope"
"$PY" - "$FIX/cases.json" "$INJ" <<'PYX'
import json, sys
inj = sys.argv[2]
cases = [
  {"id": "v-pass", "lane": "a", "prompt": "Add a Mermaid diagram to docs/x.md", "expect": ["viz"], "allow": [], "forbid": []},
  {"id": "v-composition", "lane": "a", "prompt": "Write an ADR with a Mermaid diagram", "expect": ["adr", "viz"], "allow": [], "forbid": []},
  {"id": "v-missing", "lane": "b", "prompt": "Create a .drawio org chart", "expect": ["viz"], "allow": ["drawio-diagrams-enhanced"], "forbid": []},
  {"id": "v-forbidden", "lane": "b", "prompt": "FAKE_FORBIDDEN local test is failing", "expect": ["diagnose"], "allow": [], "forbid": ["grafana-agent"]},
  {"id": "v-stray", "lane": "b", "prompt": "FAKE_STRAY add a Mermaid diagram to docs/x.md", "expect": ["viz"], "allow": [], "forbid": []},
  {"id": "v-anyof", "lane": "c", "prompt": "Check the grafana dashboards and loki logs", "expect": [["grafana-explore", "grafana-agent"]], "allow": [], "forbid": []},
  {"id": "v-negative", "lane": "c", "prompt": "Rename a function across the repo", "expect": [], "allow": [], "forbid": ["viz"]},
  {"id": "v-injection", "lane": "c", "prompt": "Rename a function " + inj, "expect": [], "allow": [], "forbid": []},
]
json.dump({"version": 1, "suite": "routing", "prompt_template": "prompt.md", "cases": cases}, open(sys.argv[1], "w"), indent=1)
PYX

export EVAL_FAKE_DUMP="$TMPROOT/dump.txt"
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --out "$OUT" --allow-outside-local --timeout 20 -- "$PY" "$FAKE" 2>&1)"; CODE=$?
unset EVAL_FAKE_DUMP
check "run completes with fake model (exit 0 despite case failures)" 0 "$CODE" "$OUT_TXT" "3 pass / 3 fail / 0 error\|5 pass / 3 fail / 0 error"
RUN1="$(latest_run "$OUT" worktree-routing)"
check "verdict pass on exact expected selection" 0 0 "$(field "$RUN1" v-pass verdict)" "^pass$"
check "verdict pass on multi-skill composition" 0 0 "$(field "$RUN1" v-composition verdict)" "^pass$"
check "verdict fail with reason 'missing'" 0 0 "$(field "$RUN1" v-missing reasons)" "missing: viz"
check "verdict fail with reason 'forbidden'" 0 0 "$(field "$RUN1" v-forbidden reasons)" "forbidden: grafana-agent"
check "verdict fail with reason 'stray'" 0 0 "$(field "$RUN1" v-stray reasons)" "stray: caveman"
check "any-of expectation satisfied by one alternative" 0 0 "$(field "$RUN1" v-anyof verdict)" "^pass$"
check "empty selection passes a negative case" 0 0 "$(field "$RUN1" v-negative verdict)" "^pass$"
check "prompt with shell metacharacters reaches the model verbatim via stdin" 0 0 "$(cat "$TMPROOT/dump.txt")" 'touch "'"$TMPROOT"'/pwned") `id` it'"'"'s ; rm -rf --nope'
if [[ -e "$TMPROOT/pwned" ]]; then echo "FAIL: shell injection executed (pwned file exists)"; FAIL=$((FAIL + 1)); else echo "PASS: no shell is involved (injection marker absent)"; PASS=$((PASS + 1)); fi
check "meta.json records refs, catalog hash, fixture hash, model, provider" 0 0 "$(cat "$RUN1/meta.json")" '"provider": "fake"'
check "meta.json records public HEAD sha" 0 0 "$(cat "$RUN1/meta.json")" "\"public_head\": \"$(git -C "$REPO_ROOT" rev-parse HEAD)\""
check "summary.md carries the simulation caveat" 0 0 "$(cat "$RUN1/summary.md")" "not the harness's native routing"

# ---------------------------------------------------------------------------
# adapter failure modes
# ---------------------------------------------------------------------------
OUT_TXT="$(EVAL_FAKE_MODE=malformed "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local --strict -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "malformed reply is rejected (status malformed) and --strict exits 1" 1 "$CODE" "$OUT_TXT" "malformed"
OUT_TXT="$(EVAL_FAKE_MODE=empty "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local --strict -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "empty reply is rejected" 1 "$CODE" "$OUT_TXT" "empty reply"
START=$SECONDS
OUT_TXT="$(EVAL_FAKE_MODE=hang "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local --timeout 1 --strict -- "$PY" "$FAKE" 2>&1)"; CODE=$?
ELAPSED=$((SECONDS - START))
check "hanging model command times out (--timeout 1)" 1 "$CODE" "$OUT_TXT" "timeout"
if [[ "$ELAPSED" -le 8 ]]; then echo "PASS: timeout enforced promptly (${ELAPSED}s)"; PASS=$((PASS + 1)); else echo "FAIL: timeout took ${ELAPSED}s"; FAIL=$((FAIL + 1)); fi
OUT_TXT="$(EVAL_FAKE_MODE=exit3 "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local --strict -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "non-zero model exit is recorded as exit:3" 1 "$CODE" "$OUT_TXT" "exit:3"
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local -- "$TMPROOT/does-not-exist" 2>&1)"; CODE=$?
check "missing executable is an error record, not a crash" 0 "$CODE" "$OUT_TXT" "0 pass / 0 fail / 1 error"
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --out "$TMPROOT/outside" -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "results outside .local/ are refused by default" 1 "$CODE" "$OUT_TXT" "refusing to write results outside"
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case nope --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "unknown case id is a usage error" 1 "$CODE" "$OUT_TXT" "unknown case id"

# ---------------------------------------------------------------------------
# --model-cwd: the model command runs from the given directory (harness isolation)
# ---------------------------------------------------------------------------
mkdir -p "$TMPROOT/empty-cwd"
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-negative --model-cwd "$TMPROOT/empty-cwd" --out "$OUT" --allow-outside-local -- bash -c 'pwd -P > "$1"; echo "{\"select\": []}"' _ "$TMPROOT/cwd.txt" 2>&1)"; CODE=$?
check "--model-cwd runs the model command from that directory" 0 "$CODE" "$OUT_TXT" "1 pass / 0 fail / 0 error"
check "model saw the requested cwd" 0 0 "$(cat "$TMPROOT/cwd.txt")" "^$(cd "$TMPROOT/empty-cwd" && pwd -P)$"
RUNW="$(latest_run "$OUT" worktree-routing)"
check "meta.json records the model cwd" 0 0 "$(cat "$RUNW/meta.json")" '"cwd": "'
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-negative --model-cwd "$TMPROOT/does-not-exist" --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "--model-cwd must exist" 1 "$CODE" "$OUT_TXT" "is not a directory"

# ---------------------------------------------------------------------------
# harness output parsers (tokens recorded when exposed)
# ---------------------------------------------------------------------------
OUT_TXT="$(EVAL_FAKE_MODE=claude-json "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --output-mode claude-json --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "claude-json envelope parsed, verdict pass" 0 "$CODE" "$OUT_TXT" "1 pass / 0 fail / 0 error"
RUNJ="$(latest_run "$OUT" worktree-routing)"
check "claude-json usage tokens recorded in totals" 0 0 "$(meta_total "$RUNJ" tokens_in)" "^1234$"
check "claude-json cost recorded" 0 0 "$(meta_total "$RUNJ" cost_usd)" "^0.000123$"
OUT_TXT="$(EVAL_FAKE_MODE=codex-jsonl "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --output-mode codex-jsonl --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "codex-jsonl events parsed, verdict pass" 0 "$CODE" "$OUT_TXT" "1 pass / 0 fail / 0 error"
RUNC="$(latest_run "$OUT" worktree-routing)"
check "codex-jsonl usage tokens recorded in totals" 0 0 "$(meta_total "$RUNC" tokens_out)" "^21$"
OUT_TXT="$(EVAL_FAKE_MODE=route "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --output-mode claude-json --out "$OUT" --allow-outside-local --strict -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "plain text where claude-json was promised is rejected as malformed" 1 "$CODE" "$OUT_TXT" "malformed"

# ---------------------------------------------------------------------------
# task-outcome fixtures on both sides (HEAD bundle includes reference files)
# ---------------------------------------------------------------------------
OUT_TXT="$("$PY" "$RUNNER" run --side head --suite tasks --dry-run --out "$OUT" --allow-outside-local 2>&1)"; CODE=$?
check "tasks dry-run on HEAD writes prompts without a model" 0 "$CODE" "$OUT_TXT" "dry-run mcp-scaffold-stdio-ping"
RUNT="$(latest_run "$OUT" head-tasks)"
check "HEAD task prompt embeds the skill's reference files from git" 0 0 "$(cat "$RUNT/prompts/mcp-scaffold-stdio-ping.txt")" '<file path="reference/scaffolding.md">'
OUT_TXT="$("$PY" "$RUNNER" run --side worktree --suite tasks --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "tasks suite passes with fake model (python parses, facts present, portable bash)" 0 "$CODE" "$OUT_TXT" "3 pass / 0 fail / 0 error"
OUT_TXT="$(EVAL_FAKE_MODE=bad-python "$PY" "$RUNNER" run --side worktree --suite tasks --case mcp-scaffold-stdio-ping --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "unparseable python scaffold fails the MCP task" 0 "$CODE" "$OUT_TXT" "python does not parse"
OUT_TXT="$(EVAL_FAKE_MODE=gnu-date "$PY" "$RUNNER" run --side worktree --suite tasks --case grafana-loki-portable-window --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "GNU-only date -d fails the portability task" 0 "$CODE" "$OUT_TXT" "must-not-hit: /date -d/"

# ---------------------------------------------------------------------------
# compare: equivalence gate, then regression / fixed / same
# ---------------------------------------------------------------------------
"$PY" - "$FIX/cases.json" "$FIX/cases-b.json" <<'PYX'
import json, sys
d = json.load(open(sys.argv[1]))
for c in d["cases"]:
    if c["id"] == "v-pass": c["expect"] = ["drawio-diagrams-enhanced"]      # will now fail -> REGRESSION
    if c["id"] == "v-missing": c["expect"] = ["drawio-diagrams-enhanced"]   # will now pass -> FIXED
json.dump(d, open(sys.argv[2], "w"))
PYX
CMP="$OUT/cmp"
"$PY" "$RUNNER" run --side head --suite routing --cases "$FIX/cases.json" --model-label fake-model-1 --out "$CMP/a" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
"$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --model-label fake-model-1 --out "$CMP/b" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
"$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases-b.json" --model-label fake-model-1 --out "$CMP/c" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
"$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --out "$CMP/d" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
"$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --model-label fake-model-1 --out "$CMP/e" --allow-outside-local -- "$PY" "$FAKE" --extra-flag >/dev/null 2>&1
A="$(latest_run "$CMP/a" head-routing)"; B="$(latest_run "$CMP/b" worktree-routing)"
C="$(latest_run "$CMP/c" worktree-routing)"; D="$(latest_run "$CMP/d" worktree-routing)"; E="$(latest_run "$CMP/e" worktree-routing)"
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$B" --md "$CMP/compare.md" --allow-outside-local 2>&1)"; CODE=$?
check "compare of a like-for-like head/worktree pair is VALID and exits 0" 0 "$CODE" "$OUT_TXT" "comparison: \*\*VALID\*\*"
check "like-for-like pair classifies all cases SAME" 0 0 "$OUT_TXT" "changes: SAME 8"
check "compare writes the markdown report" 0 0 "$(cat "$CMP/compare.md")" "changes: "
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$C" 2>&1)"; CODE=$?
check "compare with a different fixture is INVALID and exits 2" 2 "$CODE" "$OUT_TXT" "fixture sha256 differs"
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$D" 2>&1)"; CODE=$?
check "compare with an unknown model label is INVALID (cannot prove equivalence)" 2 "$CODE" "$OUT_TXT" "model label unknown"
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$E" 2>&1)"; CODE=$?
check "compare with different argv is INVALID" 2 "$CODE" "$OUT_TXT" "argv differs"
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$C" --allow-mismatch 2>&1)"; CODE=$?
check "--allow-mismatch renders the INVALID comparison and exits 0" 0 "$CODE" "$OUT_TXT" "INVALID\*\* — not like-for-like (shown anyway"
check "compare classifies REGRESSION" 0 0 "$OUT_TXT" "| v-pass | a | pass | fail | REGRESSION |"
check "compare classifies FIXED" 0 0 "$OUT_TXT" "| v-missing | b | fail | pass | FIXED |"

# served-model equivalence: identical argv, different modelUsage -> INVALID
EVAL_FAKE_MODE=claude-json "$PY" "$RUNNER" run --side head --suite routing --cases "$FIX/cases.json" --case v-pass --model-label fake-model-1 --output-mode claude-json --out "$CMP/m1" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
EVAL_FAKE_MODE=claude-json "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --model-label fake-model-1 --output-mode claude-json --out "$CMP/m2" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
EVAL_FAKE_MODE=claude-json EVAL_FAKE_MODEL_ID=fake-model-fallback "$PY" "$RUNNER" run --side worktree --suite routing --cases "$FIX/cases.json" --case v-pass --model-label fake-model-1 --output-mode claude-json --out "$CMP/m3" --allow-outside-local -- "$PY" "$FAKE" >/dev/null 2>&1
M1="$(latest_run "$CMP/m1" head-routing)"; M2="$(latest_run "$CMP/m2" worktree-routing)"; M3="$(latest_run "$CMP/m3" worktree-routing)"
OUT_TXT="$("$PY" "$RUNNER" compare "$M1" "$M2" 2>&1)"; CODE=$?
check "same served model set (modelUsage) keeps the comparison VALID" 0 "$CODE" "$OUT_TXT" "served models (modelUsage) | fake-model-1 | fake-model-1 |"
OUT_TXT="$("$PY" "$RUNNER" compare "$M1" "$M3" 2>&1)"; CODE=$?
check "different served model with identical argv is INVALID (alias fallback detected)" 2 "$CODE" "$OUT_TXT" "served models differ"
OUT_TXT="$("$PY" "$RUNNER" compare "$A" "$B" 2>&1)"; CODE=$?
check "text-mode runs report a served-model equivalence gap but stay VALID" 0 "$CODE" "$OUT_TXT" "equivalence gap: baseline: served model unverified"

# ---------------------------------------------------------------------------
# measure --json honours the .local guard
# ---------------------------------------------------------------------------
OUT_TXT="$("$PY" "$RUNNER" measure --json "$TMPROOT/measure.json" 2>&1)"; CODE=$?
check "measure --json outside .local/ is refused by default" 1 "$CODE" "$OUT_TXT" "refusing to write results outside"
OUT_TXT="$("$PY" "$RUNNER" measure --json "$TMPROOT/measure.json" --allow-outside-local 2>&1)"; CODE=$?
check "measure --json writes with --allow-outside-local" 0 "$CODE" "$OUT_TXT" "codex rendered chars"
check "measure json carries both sides" 0 0 "$(cat "$TMPROOT/measure.json")" '"worktree"'

# ---------------------------------------------------------------------------
# native-check parser (stream-json Skill tool_use -> selection)
# ---------------------------------------------------------------------------
OUT_TXT="$(EVAL_FAKE_MODE=claude-stream "$PY" "$RUNNER" native-check --cases "$FIX/cases.json" --case v-pass --case v-negative --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "native-check parses Skill tool calls from stream-json" 0 "$CODE" "$OUT_TXT" "2 pass / 0 fail / 0 error (direction-only)"
RUNN="$(latest_run "$OUT" native-routing)"
check "native-check records observed selection" 0 0 "$(field "$RUNN" v-pass selection)" '\["viz"\]'
check "native-check marks evidence direction-only" 0 0 "$(cat "$RUNN/meta.json")" '"evidence": "direction-only'
OUT_TXT="$(EVAL_FAKE_MODE=route "$PY" "$RUNNER" native-check --cases "$FIX/cases.json" --case v-pass --out "$OUT" --allow-outside-local -- "$PY" "$FAKE" 2>&1)"; CODE=$?
check "native-check without stream events is recorded as malformed, not pass" 0 "$CODE" "$OUT_TXT" "0 pass / 0 fail / 1 error"

echo
echo "eval-skills-test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
