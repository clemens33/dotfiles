#!/usr/bin/env bash
# Fixture-based tests for lint-skills.sh. Builds its own tempdir of
# fixtures, runs the script under test against them, and checks exit
# codes + output. No fixtures are committed to the repo.
set -uo pipefail  # no -e: we need to capture non-zero exits from the script under test

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-skills.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

# check <description> <expected_exit> <actual_exit> <output> [<must_contain_pattern>]
check() {
  local desc="$1" expected="$2" actual="$3" output="$4" pattern="${5:-}"
  if [[ "$actual" -ne "$expected" ]]; then
    echo "FAIL: $desc (exit $actual, expected $expected)"
    echo "${output//$'\n'/$'\n'    }"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ -n "$pattern" ]] && ! grep -q -- "$pattern" <<<"$output"; then
    echo "FAIL: $desc (output missing pattern: $pattern)"
    echo "${output//$'\n'/$'\n'    }"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

write() { # write <path>  -- reads fixture content from stdin
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

# ---------------------------------------------------------------------------
# gate 1: name mismatch
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate1/skills/gate1-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: does-not-match-dirname
description: Fixture for gate 1. Use when testing the lint gate itself.
metadata:
  category: preference
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/gate1/skills" 2>&1)"; CODE=$?
check "gate1 fires on name != dirname" 1 "$CODE" "$OUT" "frontmatter.name 'does-not-match-dirname' != directory name 'gate1-bad'"

# ---------------------------------------------------------------------------
# gate 2: description too long
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate2/skills/gate2-bad"
PADDING="$(printf 'x%.0s' $(seq 1 480))"
write "$FIX/SKILL.md" <<EOF
---
name: gate2-bad
description: Use when this fixture intentionally exceeds the description budget. $PADDING
metadata:
  category: preference
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/gate2/skills" 2>&1)"; CODE=$?
check "gate2 fires on description >500 chars" 1 "$CODE" "$OUT" "exceeds 500"

# ---------------------------------------------------------------------------
# gate 3: no 'Use when' sentence
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate3/skills/gate3-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: gate3-bad
description: Fixture for gate 3 with no trigger sentence at all.
metadata:
  category: preference
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/gate3/skills" 2>&1)"; CODE=$?
check "gate3 fires when description has no 'Use when' sentence" 1 "$CODE" "$OUT" "has no 'Use when ...' sentence"

# ---------------------------------------------------------------------------
# gate 4: body too long
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate4/skills/gate4-bad"
mkdir -p "$FIX"
{
  cat <<'EOF'
---
name: gate4-bad
description: Fixture for gate 4. Use when testing the lint gate itself.
metadata:
  category: preference
---

EOF
  for i in $(seq 1 520); do
    echo "Filler line number $i of this oversized body."
  done
} > "$FIX/SKILL.md"
OUT="$("$LINT" "$TMPROOT/gate4/skills" 2>&1)"; CODE=$?
check "gate4 fires on body >500 lines" 1 "$CODE" "$OUT" "exceeds 500"

# ---------------------------------------------------------------------------
# gate 5a: dangling markdown link outside any fence
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate5a/skills/gate5a-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: gate5a-bad
description: Fixture for gate 5. Use when testing the lint gate itself.
metadata:
  category: preference
---

See [missing doc](nonexistent-doc-xyz.md) for details.
EOF
OUT="$("$LINT" "$TMPROOT/gate5a/skills" 2>&1)"; CODE=$?
check "gate5 fires on dangling markdown link outside a fence" 1 "$CODE" "$OUT" "referenced file 'nonexistent-doc-xyz.md' does not exist"

# ---------------------------------------------------------------------------
# gate 5b: unterminated fence
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate5b/skills/gate5b-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: gate5b-bad
description: Fixture for gate 5. Use when testing the lint gate itself.
metadata:
  category: preference
---

```python
print("this fence never closes")
EOF
OUT="$("$LINT" "$TMPROOT/gate5b/skills" 2>&1)"; CODE=$?
check "gate5 fires on an unterminated fence" 1 "$CODE" "$OUT" "unterminated code fence"

# ---------------------------------------------------------------------------
# gate 6: dangling backticked skill cross-reference (boundary-bullet form)
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate6/skills/gate6-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: gate6-bad
description: Fixture for gate 6. Use when testing the lint gate itself.
metadata:
  category: preference
---

## Boundary with other skills

- **`totally-fake-skill-xyz`**: this skill name does not exist anywhere.
EOF
OUT="$("$LINT" "$TMPROOT/gate6/skills" 2>&1)"; CODE=$?
check "gate6 fires on a dangling boundary-bullet skill cross-ref" 1 "$CODE" "$OUT" "backticked skill reference \`totally-fake-skill-xyz\` does not resolve"

# ---------------------------------------------------------------------------
# gate 7: bad/missing metadata.category
# ---------------------------------------------------------------------------
FIX="$TMPROOT/gate7/skills/gate7-bad"
write "$FIX/SKILL.md" <<'EOF'
---
name: gate7-bad
description: Fixture for gate 7. Use when testing the lint gate itself.
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/gate7/skills" 2>&1)"; CODE=$?
check "gate7 fires on missing metadata.category" 1 "$CODE" "$OUT" "metadata.category must be 'capability' or 'preference'"

# ---------------------------------------------------------------------------
# waiver parsing + WAIVED output (reuses the gate7 fixture, waived this time)
# ---------------------------------------------------------------------------
WAIVERS_FIX="$TMPROOT/waivers-fixture.waivers"
cat > "$WAIVERS_FIX" <<'EOF'
# comment line, and a blank line follow
gate7-bad gate7 # deliberately waived for the test
EOF
OUT="$("$LINT" "$TMPROOT/gate7/skills" --waivers "$WAIVERS_FIX" 2>&1)"; CODE=$?
check "a waived (skill, gate) prints WAIVED and does not fail the run" 0 "$CODE" "$OUT" "WAIVED:.*metadata.category"

# ---------------------------------------------------------------------------
# interpreter selection: a python3 on PATH without PyYAML must fall back to
# /usr/bin/python3 (when that one imports yaml); an explicit $PYTHON is honored
# as-is and fails loudly. `-S` drops site-packages, which is where PyYAML lives.
# ---------------------------------------------------------------------------
NOYAML_BIN="$TMPROOT/noyaml-bin"
mkdir -p "$NOYAML_BIN"
cat > "$NOYAML_BIN/python3" <<'EOF'
#!/bin/sh
exec /usr/bin/python3 -S "$@"
EOF
chmod +x "$NOYAML_BIN/python3"
if [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c 'import yaml' >/dev/null 2>&1 \
   && ! "$NOYAML_BIN/python3" -c 'import yaml' >/dev/null 2>&1; then
  OUT="$(PATH="$NOYAML_BIN:$PATH" PYTHON='' "$LINT" "$TMPROOT/gate7/skills" --waivers "$WAIVERS_FIX" 2>&1)"; CODE=$?
  check "python3 on PATH without PyYAML falls back to /usr/bin/python3" 0 "$CODE" "$OUT" "WAIVED:.*metadata.category"
  OUT="$(PYTHON="$NOYAML_BIN/python3" "$LINT" "$TMPROOT/gate7/skills" --waivers "$WAIVERS_FIX" 2>&1)"; CODE=$?
  check "explicit PYTHON without PyYAML is honored and fails loudly" 1 "$CODE" "$OUT" "PyYAML is required"
  OUT="$(PYTHON=/usr/bin/python3 "$LINT" "$TMPROOT/gate7/skills" --waivers "$WAIVERS_FIX" 2>&1)"; CODE=$?
  check "explicit PYTHON with PyYAML is used" 0 "$CODE" "$OUT" "WAIVED:.*metadata.category"
else
  echo "SKIP: interpreter fallback tests (need /usr/bin/python3 with PyYAML and a -S run without it)"
fi

# ---------------------------------------------------------------------------
# tilde fence: content inside a ~~~ fence must not be gate-5 checked
# ---------------------------------------------------------------------------
FIX="$TMPROOT/tilde/skills/tilde-ok"
write "$FIX/SKILL.md" <<'EOF'
---
name: tilde-ok
description: Fixture for tilde fences. Use when testing the lint gate itself.
metadata:
  category: preference
---

~~~markdown
See [missing doc](nonexistent-doc-xyz.md) for details.
~~~

Real prose after the fence.
EOF
OUT="$("$LINT" "$TMPROOT/tilde/skills" 2>&1)"; CODE=$?
check "tilde (~~~) fences are recognized and their content is skipped by gate 5" 0 "$CODE" "$OUT" ""

# ---------------------------------------------------------------------------
# quad-backtick fence: a nested bare ``` inside a #### fence must not close it
# ---------------------------------------------------------------------------
FIX="$TMPROOT/quad/skills/quad-ok"
write "$FIX/SKILL.md" <<'EOF'
---
name: quad-ok
description: Fixture for quad-backtick fences. Use when testing the lint gate itself.
metadata:
  category: preference
---

````markdown
See [missing doc](nonexistent-doc-xyz.md) for details.

```
this inner triple-backtick fence is just literal content
```
````

Real prose after the fence.
EOF
OUT="$("$LINT" "$TMPROOT/quad/skills" 2>&1)"; CODE=$?
check "a nested \`\`\` inside a \`\`\`\` fence does not prematurely close it" 0 "$CODE" "$OUT" ""

# ---------------------------------------------------------------------------
# standalone-overlay layout: run from a cwd that is NOT the script's repo,
# with no explicit flags — defaults must resolve off the script's own path.
# ---------------------------------------------------------------------------
OUT="$(cd /tmp && "$LINT" "$REPO_ROOT/skills" 2>&1)"; CODE=$?
check "defaults resolve via the script's own repo root, not cwd" 0 "$CODE" "$OUT" "WAIVED:.*arch-docs"

# ---------------------------------------------------------------------------
# standalone-overlay layout, SYNTHETIC: builds its own fake overlay (own
# install.conf.yaml + one over-budget skill + own waivers file) inside the
# tempdir and runs from inside it with explicit --waivers/--conf pointing
# both at itself and at this script's own repo (standing in for "the real
# public dotfiles checkout", which is a fine stand-in since it's the exact
# thing being pointed at in production). This is intentionally NOT a test
# against the real private dotfiles-mic submodule — that submodule is
# private and unavailable on hosted public CI (actions/checkout defaults
# submodules off), so a test depending on it would fail there. The REAL
# overlay is already covered by the overlay's own CI running this same
# script against its own skills/ — no need to duplicate that here.
# ---------------------------------------------------------------------------
FAKE_OVERLAY="$TMPROOT/fake-overlay"
mkdir -p "$FAKE_OVERLAY/skills/fake-overlay-skill"
{
  cat <<'EOF'
---
name: fake-overlay-skill
description: Synthetic overlay fixture. Use when testing the standalone-overlay layout.
metadata:
  category: preference
---

EOF
  for i in $(seq 1 520); do
    echo "Filler line number $i of this over-budget synthetic overlay skill."
  done
} > "$FAKE_OVERLAY/skills/fake-overlay-skill/SKILL.md"

cat > "$FAKE_OVERLAY/install.conf.yaml" <<'EOF'
- link:
    ~/.claude/skills/fake-overlay-skill: skills/fake-overlay-skill
EOF

cat > "$FAKE_OVERLAY/lint-skills.waivers" <<'EOF'
fake-overlay-skill gate4 # synthetic fixture, deliberately over budget
EOF

OUT="$(cd "$FAKE_OVERLAY" && "$LINT" skills/ \
  --waivers lint-skills.waivers \
  --conf "$REPO_ROOT/install.conf.yaml" \
  --conf install.conf.yaml 2>&1)"; CODE=$?
check "synthetic standalone-overlay layout exits 0 with the fake skill WAIVED" 0 "$CODE" "$OUT" "WAIVED:.*fake-overlay-skill"

# ---------------------------------------------------------------------------
# fail-closed: an EXPLICITLY given --conf path that does not exist is fatal,
# never a silent warn-and-skip (that behavior is reserved for the implicit
# default overlay conf when no --conf is given at all).
# ---------------------------------------------------------------------------
FIX="$TMPROOT/missing-conf/skills/ok-skill"
write "$FIX/SKILL.md" <<'EOF'
---
name: ok-skill
description: Fixture for the missing-explicit---conf case. Use when testing the lint gate itself.
metadata:
  category: preference
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/missing-conf/skills" --conf "$TMPROOT/missing-conf/does-not-exist.yaml" 2>&1)"; CODE=$?
check "an explicit --conf path that doesn't exist is fatal" 1 "$CODE" "$OUT" "ERROR: --conf path '.*does-not-exist.yaml' does not exist"

# ---------------------------------------------------------------------------
# fail-closed: an EXPLICITLY given --waivers path that does not exist is
# fatal too.
# ---------------------------------------------------------------------------
FIX="$TMPROOT/missing-waivers/skills/ok-skill"
write "$FIX/SKILL.md" <<'EOF'
---
name: ok-skill
description: Fixture for the missing-explicit---waivers case. Use when testing the lint gate itself.
metadata:
  category: preference
---

Body.
EOF
OUT="$("$LINT" "$TMPROOT/missing-waivers/skills" --waivers "$TMPROOT/missing-waivers/does-not-exist.waivers" 2>&1)"; CODE=$?
check "an explicit --waivers path that doesn't exist is fatal" 1 "$CODE" "$OUT" "ERROR: --waivers path '.*does-not-exist.waivers' does not exist"

# ---------------------------------------------------------------------------
# fail-closed: an explicitly EMPTY --waivers/--conf value (both spellings)
# must not silently fall back to the default — empty is still "explicit".
# ---------------------------------------------------------------------------
FIX="$TMPROOT/empty-args/skills/ok-skill"
write "$FIX/SKILL.md" <<'EOF'
---
name: ok-skill
description: Fixture for the explicitly-empty-arg case. Use when testing the lint gate itself.
metadata:
  category: preference
---

Body.
EOF

OUT="$("$LINT" "$TMPROOT/empty-args/skills" --waivers= 2>&1)"; CODE=$?
check "--waivers= (empty, equals form) is fatal, not a silent default fallback" 1 "$CODE" "$OUT" "ERROR: --waivers path '' does not exist"

OUT="$("$LINT" "$TMPROOT/empty-args/skills" --waivers "" 2>&1)"; CODE=$?
check "--waivers '' (empty, space form) is fatal, not a silent default fallback" 1 "$CODE" "$OUT" "ERROR: --waivers path '' does not exist"

OUT="$("$LINT" "$TMPROOT/empty-args/skills" --conf= 2>&1)"; CODE=$?
check "--conf= (empty, equals form) is fatal, not a silent default fallback" 1 "$CODE" "$OUT" "ERROR: --conf path '' does not exist"

OUT="$("$LINT" "$TMPROOT/empty-args/skills" --conf "" 2>&1)"; CODE=$?
check "--conf '' (empty, space form) is fatal, not a silent default fallback" 1 "$CODE" "$OUT" "ERROR: --conf path '' does not exist"

# ---------------------------------------------------------------------------
echo
echo "lint-skills-test.sh: $PASS passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
