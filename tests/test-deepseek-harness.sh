#!/bin/sh
# Tests for the DeepSeek Harness pilot's tracked surfaces.
#
# Offline and dependency-free on purpose: it asserts the SHAPE of the tracked
# files and the ORDER of the install steps, so it runs on a machine where the
# harness was never provisioned and never reaches the network. Anything that
# needs the installed runtime — the copied-preset drift check, live MCP status —
# belongs to `scripts/harness-update.sh --only dsh --check`, not here.
#
# Every `~/...` and `$HOME/...` string here is a literal pattern matched against
# the CONTENT of a config file, never a path this script resolves, so tilde and
# parameter expansion must NOT happen. File-wide because every occurrence is the
# same deliberate pattern.
# shellcheck disable=SC2088,SC2016
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
DIR=$ROOT/deepseek-harness
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-deepseek-harness.XXXXXX")

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

PASS=0
FAIL=0

ok() {
    printf 'PASS: %s\n' "$1"
    PASS=$((PASS + 1))
}

bad() {
    printf 'FAIL: %s\n' "$1" >&2
    FAIL=$((FAIL + 1))
}

check() { # check <description> <condition-as-shell-word...>
    desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

equals() { # equals <description> <actual> <expected>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1 (got '$2', want '$3')"
    fi
}

# Line number of the first line matching a pattern, or 0. Used for the ordering
# assertions: install steps are correct only in the right sequence.
line_of() { # line_of <file> <pattern>
    awk -v pat="$2" 'index($0, pat) { print NR; exit }' "$1" || true
}

# ---------------------------------------------------------------------------
# 1. The pin is exact, and the lock agrees with it
# ---------------------------------------------------------------------------
check 'package.json exists' test -f "$DIR/package.json"
check 'package-lock.json exists' test -f "$DIR/package-lock.json"
check 'project .npmrc exists' test -f "$DIR/.npmrc"

# An exact version, never a range: a developer preview that floats defeats the
# whole point of pinning it.
pin=$(awk -F'"' '/"@deepseek-ai\/dsh":/ { print $4; exit }' "$DIR/package.json")
check 'dependency is an exact version, not a range' \
    test -n "$(printf '%s' "$pin" | awk '/^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$/')"

# The lock is what actually pins the plugin graph; a lock naming a different
# version than package.json is exactly what `npm ci` refuses, so catch it here.
locked=$(awk '
    /"node_modules\/@deepseek-ai\/dsh": \{/ { inblock = 1 }
    inblock && /"version":/ { gsub(/[",]/, ""); print $2; exit }
' "$DIR/package-lock.json")
equals 'lockfile pins the same version as package.json' "$locked" "$pin"

check 'lockfile records an integrity hash for the harness' \
    grep -q '"integrity": "sha512-' "$DIR/package-lock.json"
check 'project .npmrc keeps the lifecycle guard on' \
    grep -q '^strict-allow-scripts=true$' "$DIR/.npmrc"

# ---------------------------------------------------------------------------
# 2. The lifecycle policy is minimal and lives where a DENY is expressible
# ---------------------------------------------------------------------------
# npm's .npmrc allow-scripts list can only ever ALLOW; a deny is expressible
# only as a package.json boolean. A deny that drifted into .npmrc would silently
# become an allow, so assert the policy is not there.
check 'the allow/deny policy is in package.json' \
    grep -q '"allowScripts"' "$DIR/package.json"
check 'the .npmrc carries no allow-scripts list' \
    test -z "$(grep -c '^allow-scripts' "$DIR/.npmrc" | grep -v '^0$')"

# Anchored to a pinned "name@version" key so `"private": true` is not counted.
allowed=$(grep -c '"[^"]*@[0-9][^"]*": true' "$DIR/package.json" || true)
denied=$(grep -c '"[^"]*@[0-9][^"]*": false' "$DIR/package.json" || true)
equals 'exactly three packages may run install scripts' "$allowed" "3"
equals 'exactly two packages are explicitly denied' "$denied" "2"
for pkg in koffi node-pty '@deepseek-ai/dsh-subprocess-local'; do
    check "$pkg is allowed with a pinned version" \
        grep -q "\"$pkg@[0-9][^\"]*\": true" "$DIR/package.json"
done
for pkg in '@google/genai' protobufjs; do
    check "$pkg is denied with a pinned version" \
        grep -q "\"$pkg@[0-9][^\"]*\": false" "$DIR/package.json"
done

# ---------------------------------------------------------------------------
# 3. Layer discipline: host patch selects the preset and owns no tools
# ---------------------------------------------------------------------------
#
# Three layers, not one. `composeProfile` applies $DSH_HOME/cordis.patch.yml to
# EVERY profile after that profile's own layer, so the shared model route lives
# there exactly once and the per-profile files carry only what their own
# composition has a row for.
PATCH=$DIR/cordis.patch.yml
WEB_PATCH=$DIR/profiles/web/cordis.patch.yml
TUI_PATCH=$DIR/profiles/dsh-tui/cordis.patch.yml
check 'home patch exists' test -f "$PATCH"
check 'web profile patch exists' test -f "$WEB_PATCH"
check 'dsh-tui profile patch exists' test -f "$TUI_PATCH"

# The home layer reaches sdk-minimal too, which has no dsh-base and therefore no
# roster row at all. A roster row here would warn on every one of its boots.
check 'home patch carries the shared model route' grep -q '^- id: llm-pi-ai$' "$PATCH"
check 'home patch carries no roster row' \
    test "$(grep -c '^- id: .*agent-presets$' "$PATCH" || true)" = 0

# Two rows, not one. `llm-pi-ai` decides what the OpenRouter provider CAN
# reach; `agent-default-model` decides what a freshly created agent actually
# starts on. With only the route composed, every surface still selected
# deepseek-official/deepseek-flash and asked for DEEPSEEK_API_KEY - the route
# was present and unreachable.
check 'home patch carries the shared default-model override' \
    grep -q '^- id: agent-default-model$' "$PATCH"
equals 'the default-model override is defined exactly once' \
    "$(grep -c '^- id: agent-default-model$' "$PATCH" || true)" "1"
check 'the default-model override names the OpenRouter provider route' \
    grep -q '^    provider: openrouter$' "$PATCH"

# The two rows must name the SAME preset. A `models` list REPLACES the served
# catalog, so a default naming anything else selects a model this route cannot
# serve - and the failure surfaces only at the first request.
route_model=$(awk '/^          - id: / { print $3; exit }' "$PATCH")
default_model=$(awk '/^- id: agent-default-model$/ { f = 1 } f && /^    model: / { print $2; exit }' "$PATCH")
check 'the route names a model at all' test -n "$route_model"
equals 'the default selects exactly the model the route serves' \
    "$default_model" "$route_model"
equals 'the default names the pinned preset, never a bare model id' \
    "$default_model" "'@preset/deepseek-v41-flash-us-zdr'"

# `reasoningEffort` is a settings-layer field by the plugin's own design: a
# composition value would be re-inherited after a saved selection cleared it,
# so the config schema has no such field and the route's `reasoning: high`
# stays the default-effort source.
check 'the default-model override carries no reasoningEffort' \
    test "$(grep -c '^    reasoningEffort:' "$PATCH" || true)" = 0

# OpenRouter's strict preset filters on endpoint-advertised parameter names.
# Every endpoint for V4.1 Flash advertises `max_tokens`; none advertises pi-ai's
# inferred OpenRouter default, `max_completion_tokens`. Keep the route override
# explicit so a pi-ai catalog change cannot silently restore the rejected name.
check 'the route emits the endpoint-supported max_tokens spelling' \
    grep -q '^          maxTokensField: max_tokens$' "$PATCH"

# The roster id is NOT the same on both surfaces: dsh-web-app mounts it as
# `agent-presets`, the dsh-tui bundle as its own scoped `dsh-tui-agent-presets`
# and self-disables when an official row is present. Copying one file over the
# other would target a missing id and silently lose the managed preset.
check 'web profile patch targets the official roster id' \
    grep -q '^- id: agent-presets$' "$WEB_PATCH"
check 'dsh-tui profile patch targets the scoped roster id' \
    grep -q '^- id: dsh-tui-agent-presets$' "$TUI_PATCH"
check 'web profile patch selects the managed preset' grep -q '^    default: dotfiles$' "$WEB_PATCH"
check 'dsh-tui profile patch selects the managed preset' grep -q '^    default: dotfiles$' "$TUI_PATCH"
check 'the two roster rows are not interchangeable' \
    test "$(grep -c '^- id: dsh-tui-agent-presets$' "$WEB_PATCH" || true)" = 0

# The route is defined once. A copy in a profile layer is drift waiting to
# happen, which is the whole reason it sits in the home layer.
for f in "$WEB_PATCH" "$TUI_PATCH"; do
    check "profile patch ${f##*/profiles/} carries no model route" \
        test "$(grep -c 'openrouter.ai' "$f" || true)" = 0
    # The default belongs beside the route for the same reason: one copy, or
    # five that drift apart.
    check "profile patch ${f##*/profiles/} carries no default-model row" \
        test "$(grep -c '^- id: agent-default-model$' "$f" || true)" = 0
done

# Both surfaces expose model-facing tools only from a preset, so an MCP row in
# any host-plane layer would connect its server and reach no model.
for f in "$PATCH" "$WEB_PATCH" "$TUI_PATCH"; do
    check "patch ${f##*/deepseek-harness/} contains no MCP rows" \
        test "$(grep -c 'dsh-mcp-client' "$f" || true)" = 0
done

# An empty or comment-only patch parses as null, and the loader then treats the
# layer as absent rather than failing: every profile would boot unrouted with no
# error. The installer refuses that, so the tracked source must never be empty.
for f in "$PATCH" "$WEB_PATCH" "$TUI_PATCH"; do
    check "patch ${f##*/deepseek-harness/} is a non-empty entry list" \
        test -n "$(sed 's/#.*//' "$f" | tr -d '[:space:]')"
done

# ---------------------------------------------------------------------------
# 3b. The composition itself, where a runtime exists to compose it
# ---------------------------------------------------------------------------
# Shape is not selection. The tracked layer can name the route and the default
# perfectly and still lose - to a profile layer, to a shipped row applied
# later, or to an id that moved between release candidates. Only a composed
# profile answers what a fresh agent actually starts on.
#
# So this composes the TRACKED layer against the installed runtime and the real
# profile trees. It runs in a throwaway home: the layer is copied in, the
# profile trees (50-odd MB of installed node_modules) are linked and only ever
# read, and the session and storage directories the composition creates land in
# the temp home rather than the live ~/.dsh.
comp_bin=${DSH_PREFIX:-$HOME/.local/share/dsh}/node_modules/.bin/dsh
comp_profiles=${DSH_HOME:-$HOME/.dsh}/profiles
if [ -x "$comp_bin" ] && [ -d "$comp_profiles" ]; then
    comp_home=$TMP_ROOT/comphome
    mkdir -p "$comp_home"
    cp "$PATCH" "$comp_home/cordis.patch.yml"
    ln -s "$comp_profiles" "$comp_home/profiles"
    comp_err=$TMP_ROOT/comp.err

    for prof in dsh-tui web headless acp sdk; do
        rc=0
        comp_out=$(DSH_HOME=$comp_home "$comp_bin" --profile "$prof" \
            --dump-config 2>"$comp_err") || rc=$?
        equals "profile $prof composes cleanly" "$rc" "0"
        equals "profile $prof composes with no warning at all" \
            "$(grep -c . "$comp_err" || true)" "0"
        equals "profile $prof carries exactly one OpenRouter route" \
            "$(printf '%s\n' "$comp_out" |
                grep -c '^        baseURL: https://openrouter.ai/api/v1$' || true)" "1"
        # THE REGRESSION THIS SECTION EXISTS FOR. Before the default-model
        # override, this line read `deepseek-official deepseek-flash` on every
        # one of these five profiles: the OpenRouter route composed, and no
        # fresh agent ever selected it. Every static check above was green.
        equals "profile $prof starts a fresh agent on the pinned preset" \
            "$(printf '%s\n' "$comp_out" | awk '
                /^- id: agent-default-model$/ { f = 1 }
                f && /^    provider: / { p = $2 }
                f && /^    model: / { print p " " $2; exit }')" \
            "openrouter '@preset/deepseek-v41-flash-us-zdr'"
        equals "profile $prof selects that default exactly once" \
            "$(printf '%s\n' "$comp_out" | grep -c '^- id: agent-default-model$' || true)" "1"
    done

    # `sdk-minimal` is the pinned exception: no dsh-base, so NEITHER row has an
    # id to target and both warn. Two lines, each exactly once.
    rc=0
    comp_out=$(DSH_HOME=$comp_home "$comp_bin" --profile sdk-minimal \
        --dump-config 2>"$comp_err") || rc=$?
    equals 'sdk-minimal composes cleanly' "$rc" "0"
    equals 'sdk-minimal emits exactly two warning lines' "$(grep -c . "$comp_err" || true)" "2"
    equals 'sdk-minimal names the unmatched route row once' \
        "$(grep -c 'patch: entry "llm-pi-ai" not found' "$comp_err" || true)" "1"
    equals 'sdk-minimal names the unmatched default-model row once' \
        "$(grep -c 'patch: entry "agent-default-model" not found' "$comp_err" || true)" "1"
    equals 'sdk-minimal carries no OpenRouter route' \
        "$(printf '%s\n' "$comp_out" | grep -c 'openrouter.ai' || true)" "0"

    # Config shape alone is not proof: the loader could accept maxTokensField
    # and pi-ai could still ignore it. Aim a copied patch at a local recorder,
    # run the REAL headless profile with a dummy key, and assert on the outbound
    # JSON. No OpenRouter request or model inference occurs in this test.
    wire_home=$TMP_ROOT/wire-home
    wire_capture=$TMP_ROOT/wire-request.json
    wire_port_file=$TMP_ROOT/wire-port
    wire_recorder=$TMP_ROOT/wire-recorder.mjs
    wire_out=$TMP_ROOT/wire.out
    wire_err=$TMP_ROOT/wire.err
    mkdir -p "$wire_home"
    cp "$PATCH" "$wire_home/cordis.patch.yml"
    ln -s "$comp_profiles" "$wire_home/profiles"
    cat >"$wire_recorder" <<'RECORDER'
import fs from 'node:fs'
import http from 'node:http'

const [capturePath, portPath] = process.argv.slice(2)
const server = http.createServer((request, response) => {
  let raw = ''
  request.setEncoding('utf8')
  request.on('data', (chunk) => { raw += chunk })
  request.on('end', () => {
    const body = JSON.parse(raw)
    fs.writeFileSync(capturePath, JSON.stringify(body))
    response.writeHead(200, { 'content-type': 'text/event-stream' })
    const common = {
      id: 'chatcmpl-loopback',
      object: 'chat.completion.chunk',
      created: 0,
      model: body.model,
    }
    response.write(`data: ${JSON.stringify({
      ...common,
      choices: [{
        index: 0,
        delta: { role: 'assistant', content: 'loopback-ok' },
        finish_reason: null,
      }],
    })}\n\n`)
    response.write(`data: ${JSON.stringify({
      ...common,
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
    })}\n\n`)
    response.end('data: [DONE]\n\n')
    clearTimeout(deadline)
    setTimeout(() => server.close(), 25)
  })
})
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(portPath, String(server.address().port))
})
const deadline = setTimeout(() => server.close(() => { process.exitCode = 124 }), 10000)
RECORDER

    node "$wire_recorder" "$wire_capture" "$wire_port_file" &
    wire_recorder_pid=$!
    wire_wait=0
    while [ ! -s "$wire_port_file" ] && [ "$wire_wait" -lt 200 ]; do
        sleep 0.025
        wire_wait=$((wire_wait + 1))
    done
    if [ ! -s "$wire_port_file" ]; then
        bad 'the loopback recorder starts'
        kill "$wire_recorder_pid" 2>/dev/null || true
        wait "$wire_recorder_pid" 2>/dev/null || true
    else
        wire_port=$(cat "$wire_port_file")
        sed "s#baseURL: https://openrouter.ai/api/v1#baseURL: http://127.0.0.1:$wire_port/v1#" \
            "$PATCH" >"$wire_home/cordis.patch.yml"
        rc=0
        DSH_HOME=$wire_home OPENROUTER_API_KEY=dummy-loopback-key \
            "$comp_bin" --profile headless 'return the word loopback-ok' \
            >"$wire_out" 2>"$wire_err" || rc=$?
        equals 'the real headless profile completes against loopback' "$rc" "0"
        if [ -s "$wire_capture" ]; then
            wire_fields=$(node -e '
              const fs = require("node:fs")
              const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
              const present = (key) => Object.hasOwn(body, key) ? "present" : "missing"
              process.stdout.write([
                `model=${body.model}`,
                `max_tokens=${present("max_tokens")}`,
                `max_completion_tokens=${present("max_completion_tokens")}`,
              ].join(" "))
            ' "$wire_capture")
            equals 'headless emits the supported token-limit parameter on the wire' \
                "$wire_fields" \
                "model=@preset/deepseek-v41-flash-us-zdr max_tokens=present max_completion_tokens=missing"
        else
            bad 'the real headless profile reaches the loopback recorder'
        fi
        kill "$wire_recorder_pid" 2>/dev/null || true
        wait "$wire_recorder_pid" 2>/dev/null || true
    fi

    # The link into the live profile trees has done its job; drop it here
    # rather than leaving a 50MB target reachable through the temp tree.
    rm -f "$comp_home/profiles"
else
    ok 'composition cases skipped (runtime or profile trees not provisioned)'
fi

# ---------------------------------------------------------------------------
# 4. The managed preset carries exactly the four servers, shaped correctly
# ---------------------------------------------------------------------------
PRESET=$DIR/presets/dotfiles/agent.cordis.yml
check 'preset composition exists' test -f "$PRESET"
check 'preset metadata exists' test -f "$DIR/presets/dotfiles/preset.yml"
check 'preset composition is a top-level list' \
    test -n "$(head -n 200 "$PRESET" | awk '/^- id: / { print; exit }')"

# The snapshot region is delimited by ONE exact marker line: everything before
# it must be the shipped `standard` composition byte for byte. Both the updater
# and the fixtures below locate it the same way, by byte offset rather than by
# line number, so a changed line ending or a missing final newline counts as
# the drift it is.
MARKER='# ── MCP servers (dotfiles addition'
markers=$(grep -c -F -- "$MARKER" "$PRESET" || true)
equals 'the snapshot marker appears exactly once' "$markers" "1"
MARKER_OFFSET=$(grep -b -F -m1 -- "$MARKER" "$PRESET" | cut -d: -f1)
check 'the snapshot marker has a byte offset' test -n "$MARKER_OFFSET"

# When the runtime is provisioned, the snapshot must still BE the installed
# standard. This is the check that catches a DSH bump moving it underneath us.
SHIPPED=${DSH_PREFIX:-$HOME/.local/share/dsh}/node_modules/@deepseek-ai/dsh-agent-presets/presets/standard/agent.cordis.yml
if [ -f "$SHIPPED" ]; then
    check 'the snapshot prefix is the installed standard, byte for byte' \
        sh -c 'head -c "$1" "$2" | cmp -s - "$3"' _ "$MARKER_OFFSET" "$PRESET" "$SHIPPED"
    equals 'the snapshot prefix is exactly as long as the installed standard' \
        "$MARKER_OFFSET" "$(wc -c <"$SHIPPED" | tr -d ' ')"
else
    ok 'snapshot drift check skipped (runtime not provisioned)'
fi

rows=$(grep -c "name: '@deepseek-ai/dsh-mcp-client'" "$PRESET" || true)
equals 'preset declares exactly four MCP rows' "$rows" "4"

names=$(awk '/^    serverName: / { print $2 }' "$PRESET")
count=$(printf '%s\n' "$names" | grep -c . || true)
unique=$(printf '%s\n' "$names" | sort -u | grep -c . || true)
equals 'every serverName is unique' "$count" "$unique"
# mcp__<serverName>__<rawName> is the model-facing namespace, and DSH rejects a
# name outside this class.
bad_names=$(printf '%s\n' "$names" | awk '!/^[A-Za-z0-9_-]{1,32}$/' | grep -c . || true)
equals 'every serverName matches [A-Za-z0-9_-]{1,32}' "$bad_names" "0"

ids=$(awk '/^- id: / { print $3 }' "$PRESET")
dup_ids=$(printf '%s\n' "$ids" | sort | uniq -d | grep -c . || true)
equals 'no duplicate top-level row ids' "$dup_ids" "0"

for server in serena context7 chrome-devtools open-design; do
    check "$server is configured" grep -q "^    serverName: $server$" "$PRESET"
done

# Phase 1 proved a failing `true` row aborts the WHOLE profile at boot. Every
# row here is optional by construction, so none may be allowed to do that.
# Anchored to the config indentation so the comment explaining the setting is
# not mistaken for a fifth row.
strict=$(grep -c '^    failOnStartupError: true$' "$PRESET" || true)
equals 'no MCP row can abort the profile at boot' "$strict" "0"
lenient=$(grep -c '^    failOnStartupError: false$' "$PRESET" || true)
equals 'every MCP row is explicitly optional' "$lenient" "4"

# The pins must match what the other clients already use; they are bumped
# together, and a silent divergence here is the failure this catches.
check 'Serena is pinned to the shared commit' \
    grep -q 'serena@949a27ef1e5fda1a6e7b561e777bcece345c6ffd' "$PRESET"
check 'Context7 is pinned to the shared version' \
    grep -q "@upstash/context7-mcp@4.0.5" "$PRESET"
check 'Chrome DevTools is pinned to the shared version' \
    grep -q 'chrome-devtools-mcp@1.8.0' "$PRESET"
for flag in --no-usage-statistics --no-performance-crux; do
    check "Chrome DevTools keeps $flag" grep -q -- "$flag" "$PRESET"
done
check 'the same Serena pin is used by OpenCode' \
    grep -q 'serena@949a27ef1e5fda1a6e7b561e777bcece345c6ffd' "$ROOT/opencode/config.json"

# ---------------------------------------------------------------------------
# 5. The wrapper fails clearly instead of obscurely
# ---------------------------------------------------------------------------
WRAPPER=$ROOT/bin/dsh
check 'wrapper is executable' test -x "$WRAPPER"

rc=0
out=$(DSH_PREFIX=$TMP_ROOT/absent sh "$WRAPPER" --version 2>&1) || rc=$?
equals 'missing runtime exits 127' "$rc" "127"
check 'missing runtime names the expected path' \
    test -n "$(printf '%s' "$out" | awk '/not installed at/')"
check 'missing runtime points at ./install' \
    test -n "$(printf '%s' "$out" | awk '/run \.\/install/')"

# With a runtime present the wrapper must exec it, pass arguments through, and
# hand it a DSH_HOME. A stub stands in for the real harness so this stays
# offline.
stub_prefix=$TMP_ROOT/prefix
mkdir -p "$stub_prefix/node_modules/.bin"
cat >"$stub_prefix/node_modules/.bin/dsh" <<'STUB'
#!/bin/sh
printf 'home=%s args=%s\n' "${DSH_HOME:-unset}" "$*"
STUB
chmod +x "$stub_prefix/node_modules/.bin/dsh"

out=$(DSH_PREFIX=$stub_prefix HOME=$TMP_ROOT/fakehome sh "$WRAPPER" --profile web --no-open)
equals 'wrapper defaults DSH_HOME and forwards arguments' \
    "$out" "home=$TMP_ROOT/fakehome/.dsh args=--profile web --no-open"

out=$(DSH_PREFIX=$stub_prefix DSH_HOME=$TMP_ROOT/elsewhere sh "$WRAPPER" --version)
equals 'wrapper respects an exported DSH_HOME' \
    "$out" "home=$TMP_ROOT/elsewhere args=--version"

# ---------------------------------------------------------------------------
# 5b. The dispatch contract, every row of it
# ---------------------------------------------------------------------------
# The wrapper owns exactly one token: the first. It rewrites a surface NAME into
# the --profile the official launcher wants and forwards the rest verbatim. The
# rows below ARE the contract; a change here is a change to what `dsh` means.
H=$TMP_ROOT/fakehome
# `dsh plugin` refuses to run without the pinned pnpm, so every dispatch row is
# given one. Whether each row actually EXPOSES it is asserted separately below.
pnpm_stub=$TMP_ROOT/pnpmprefix
mkdir -p "$pnpm_stub/bin"
printf '#!/bin/sh\nprintf "pinned\\n"\n' >"$pnpm_stub/bin/pnpm"
chmod +x "$pnpm_stub/bin/pnpm"

dispatch() { # dispatch <description> <expected-args> [argv...]
    desc=$1
    want=$2
    shift 2
    got=$(DSH_PREFIX=$stub_prefix HOME=$H DSH_PNPM_PREFIX=$pnpm_stub sh "$WRAPPER" ${1+"$@"})
    equals "$desc" "$got" "home=$H/.dsh args=$want"
}

dispatch 'zero args enter the managed TUI profile' '--profile dsh-tui'
dispatch 'tui enters the managed TUI profile' '--profile dsh-tui' tui
dispatch 'tui preserves its arguments' '--profile dsh-tui --resume abc' tui --resume abc
dispatch 'headless selects the official one-shot profile' \
    '--profile headless run the tests' headless 'run the tests'
# Verbatim on purpose: `dsh web` is someone asking for the browser surface, so
# injecting --no-open there would defeat the request. Nothing selects it
# implicitly any more, which is what "no browser auto-launch" protects.
dispatch 'web is forwarded verbatim as the official alias' 'web --no-open' web --no-open
dispatch 'web with no arguments is still verbatim' 'web' web
dispatch 'an explicit --profile is never overridden' '--profile acp' --profile acp
dispatch 'plugin is forwarded verbatim' 'plugin --profile x add y' plugin --profile x add y
dispatch '--version passes through with no defaults added' '--version' --version
dispatch '--help passes through' '--help' --help

# Never guess a surface. A bare launcher flag is ambiguous - the official
# launcher rejects it without a --profile anyway - so say so and stop.
for bad in --patch --dump-config --dump-default-config bogus -x; do
    rc=0
    out=$(DSH_PREFIX=$stub_prefix HOME=$H sh "$WRAPPER" "$bad" 2>&1) || rc=$?
    equals "an unrecognized first token ($bad) exits 2" "$rc" "2"
    check "the $bad refusal names the token" \
        test -n "$(printf '%s' "$out" | awk -v t="$bad" 'index($0, t)')"
    check "the $bad refusal shows the usage" \
        test -n "$(printf '%s' "$out" | awk '/dsh headless <task\.\.\.>/')"
done

# The default must not be reachable by accident from the Web side.
out=$(DSH_PREFIX=$stub_prefix HOME=$H sh "$WRAPPER")
check 'the zero-argument default names no web profile' \
    test -z "$(printf '%s' "$out" | awk '/profile web/')"

# --- the pinned pnpm is exposed to `dsh plugin` and to nothing else ---------
# `dsh plugin` forwards to whatever pnpm it finds on PATH. It must find the
# pinned one: npm resolves the profile's optional peers against the tree and
# installs a second @deepseek-ai plane, which is double registration.
cat >"$stub_prefix/node_modules/.bin/dsh" <<'STUBPATH'
#!/bin/sh
printf 'args=%s pnpm=%s\n' "$*" "$(command -v pnpm || echo none)"
STUBPATH
chmod +x "$stub_prefix/node_modules/.bin/dsh"

out=$(DSH_PREFIX=$stub_prefix HOME=$H DSH_PNPM_PREFIX=$pnpm_stub sh "$WRAPPER" plugin --profile x add y)
equals 'plugin sees the pinned pnpm' "$out" "args=plugin --profile x add y pnpm=$pnpm_stub/bin/pnpm"
# Scoped means scoped: no other dispatch row may leak it onto PATH.
for row in '' 'tui' 'headless x' 'web' '--profile acp' '--version'; do
    out=$(DSH_PREFIX=$stub_prefix HOME=$H DSH_PNPM_PREFIX=$pnpm_stub sh "$WRAPPER" ${row:+$row})
    check "the pinned pnpm stays off PATH for 'dsh ${row:-(no args)}'" \
        test -n "$(printf '%s' "$out" | awk '/pnpm=none/')"
done
rc=0
out=$(DSH_PREFIX=$stub_prefix HOME=$H DSH_PNPM_PREFIX=$TMP_ROOT/absent sh "$WRAPPER" plugin --profile x add y 2>&1) || rc=$?
equals 'plugin without the pinned pnpm exits 127' "$rc" "127"
check 'the missing pnpm names the expected path' \
    test -n "$(printf '%s' "$out" | awk '/pinned pnpm not installed at/')"
check 'the missing pnpm points at ./install' \
    test -n "$(printf '%s' "$out" | awk '/run \.\/install/')"

# Restore the argument-echoing stub for anything that follows.
cat >"$stub_prefix/node_modules/.bin/dsh" <<'STUB2'
#!/bin/sh
printf 'home=%s args=%s\n' "${DSH_HOME:-unset}" "$*"
STUB2
chmod +x "$stub_prefix/node_modules/.bin/dsh"

# ---------------------------------------------------------------------------
# 5c. The managed dsh-tui profile's tracked install inputs
# ---------------------------------------------------------------------------
TUI=$DIR/profiles/dsh-tui
check 'dsh-tui profile manifest exists' test -f "$TUI/package.json"
check 'dsh-tui profile lock exists' test -f "$TUI/pnpm-lock.yaml"
check 'dsh-tui profile pnpm settings exist' test -f "$TUI/pnpm-workspace.yaml"

# `dsh-tui` is not a shipped template, so nothing materializes it the way
# --dump-config materializes `web`; these three files ARE the profile.
tui_pin=$(awk -F'"' '/"@deepseek-harness-tui\/dsh-tui":/ { print $4; exit }' "$TUI/package.json")
check 'the TUI dependency is an exact version, not a range' \
    test -n "$(printf '%s' "$tui_pin" | awk '/^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$/')"
check 'the lock pins the same TUI version as the manifest' \
    grep -q "'@deepseek-harness-tui/dsh-tui@$tui_pin':" "$TUI/pnpm-lock.yaml"
check 'the lock records an integrity hash for the TUI' \
    test -n "$(awk -v v="$tui_pin" '
        index($0, "@deepseek-harness-tui/dsh-tui@" v "'"'"':") { found = 1; next }
        found && /integrity: sha512-/ { print; exit }
    ' "$TUI/pnpm-lock.yaml")"

# The layer stack is the composition. dsh-base first, the TUI bundle over it -
# the TUI patches dsh-base rows, so the order is not decorative.
# Read the order out of the bundles array itself: the package name also appears
# earlier under "dependencies", so a whole-file line comparison proves nothing.
tui_bundles=$(awk '/"bundles"/ { b = 1; next } b && /\]/ { exit } b { print }' "$TUI/package.json")
check 'the profile stacks dsh-base under the TUI bundle' \
    test -n "$(printf '%s\n' "$tui_bundles" | awk '/dsh-base/')"
check 'the TUI bundle is listed after dsh-base' \
    test "$(printf '%s\n' "$tui_bundles" | awk '/dsh-base/ { print NR; exit }')" \
        -lt "$(printf '%s\n' "$tui_bundles" | awk '/@deepseek-harness-tui\/dsh-tui/ { print NR; exit }')"

# autoInstallPeers:false is the single line standing between this profile and a
# second @deepseek-ai plane. The TUI's 29 peer ranges cap at 0.1.5-rc.1 while the
# official umbrella resolves rc.2 internals; every peer is optional, so pnpm
# installs none of them and the plane stays in the runtime prefix. Flip this and
# pnpm resolves them locally, which is double registration, not a fix.
check 'the profile keeps pnpm from auto-installing peers' \
    grep -q '^autoInstallPeers: false$' "$TUI/pnpm-workspace.yaml"
check 'the profile keeps the shipped node linker' \
    grep -q '^nodeLinker: hoisted$' "$TUI/pnpm-workspace.yaml"
check 'the profile lock records the same peer policy' \
    grep -q '^  autoInstallPeers: false$' "$TUI/pnpm-lock.yaml"
check 'the tracked profile ships no node_modules' test ! -d "$TUI/node_modules"

# ---------------------------------------------------------------------------
# 5d. The pinned pnpm helper
# ---------------------------------------------------------------------------
# It exists for one reason: npm cannot install this profile without producing a
# second plane, and `dsh plugin` shells out to pnpm. It is a separate project so
# the official runtime graph stays byte-identical to the evidence it was gated
# against.
PNPM=$DIR/pnpm
check 'pnpm helper manifest exists' test -f "$PNPM/package.json"
check 'pnpm helper lock exists' test -f "$PNPM/package-lock.json"
check 'pnpm helper .npmrc exists' test -f "$PNPM/.npmrc"
pnpm_pin=$(awk -F'"' '/"pnpm":/ { print $4; exit }' "$PNPM/package.json")
check 'pnpm is pinned to an exact version' \
    test -n "$(printf '%s' "$pnpm_pin" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/')"
check 'the helper lock pins the same pnpm version' \
    test "$(awk '
        /"node_modules\/pnpm": \{/ { inblock = 1 }
        inblock && /"version":/ { gsub(/[",]/, ""); print $2; exit }
    ' "$PNPM/package-lock.json")" = "$pnpm_pin"
check 'the helper lock records an integrity hash for pnpm' \
    test -n "$(awk '/"node_modules\/pnpm": \{/ { i = 1 } i && /"integrity":/ { print; exit }' "$PNPM/package-lock.json")"
check 'the helper carries the same lifecycle guard as the runtime' \
    grep -q '^strict-allow-scripts=true$' "$PNPM/.npmrc"
# Denied, not allowed. pnpm's install.js swaps a placeholder for the native
# binary; its own comment says that with scripts blocked the placeholder stays
# and bin/pnpm.mjs runs the same binary, which arrives as a locked optional
# dependency rather than a download. Corepack uses that entry point for exactly
# this reason, so denying costs nothing and removes an install-time hook.
check 'the helper denies pnpm its lifecycle scripts' \
    grep -q "\"pnpm@$pnpm_pin\": false" "$PNPM/package.json"
# A helper that grew a plane package would reintroduce the split singleton by
# the back door.
check 'the helper lock carries no plane packages' \
    test "$(grep -c '@deepseek-ai' "$PNPM/package-lock.json" || true)" = 0
check 'the helper is not a dependency of the official runtime' \
    test "$(grep -c '"pnpm"' "$DIR/package.json" || true)" = 0
# Three files, no more. `dsh plugin` needs a `pnpm` on PATH and npm creates no
# bin link for a scripts-denied package, so a shim is unavoidable - but it is
# generated by ./install, not tracked: it carries no version or integrity of its
# own and an executable in the repo that lands on PATH buys nothing.
check 'the helper tracks no executable of its own' \
    test -z "$(find "$PNPM" -type f -perm -u+x -print 2>/dev/null | head -n 1)"
check 'the pnpm shim is generated by the installer' \
    grep -q 'node_modules/pnpm/bin/pnpm.mjs' "$ROOT/install.conf.yaml"

# ---------------------------------------------------------------------------
# 5e. The credential adapter: the OpenCode key, this process, and nothing else
# ---------------------------------------------------------------------------
# The composed route resolves `apiKeyEnv: OPENROUTER_API_KEY`, and the
# credentials plugin reads the launching environment before anything else. The
# wrapper fills that variable from the OpenRouter key the OpenCode auth store
# already holds, so this machine keeps one copy of the secret instead of two.
#
# Every case runs against an isolated fake home, a fixture store and a stub
# launcher that echoes what it received. The real store is never read: the
# fixture path is handed over through OPENCODE_AUTH_FILE.
#
# Cleared once, deliberately: the case below that must see NO ambient key is
# the default, and a key exported into the test runner's own environment would
# silently make every one of them pass for the wrong reason.
unset OPENROUTER_API_KEY

cred_prefix=$TMP_ROOT/credprefix
cred_home=$TMP_ROOT/credhome
AUTH=$TMP_ROOT/opencode-auth.json
mkdir -p "$cred_prefix/node_modules/.bin" "$cred_home/.dsh"
cat >"$cred_prefix/node_modules/.bin/dsh" <<'CREDSTUB'
#!/bin/sh
# Reports the credential as the exec'd launcher sees it, and its own argv, so
# one line proves both halves: present in the ENVIRONMENT, absent from argv.
printf 'key=%s argv=%s\n' "${OPENROUTER_API_KEY:-UNSET}" "$*"
CREDSTUB
chmod +x "$cred_prefix/node_modules/.bin/dsh"

cred() { # cred -> the stub's line, with no ambient credential
    DSH_PREFIX=$cred_prefix HOME=$cred_home OPENCODE_AUTH_FILE=$AUTH \
        sh "$WRAPPER" --version
}
cred_key() { # cred_key -> just the credential the child saw
    cred | sed 's/^key=//; s/ argv=.*//'
}

STORE_KEY=sk-or-v1-fixture-store-key
ENV_KEY=sk-or-v1-fixture-env-key

# The shape the store actually has, verified against the installed OpenCode
# auth file: a per-provider record with `type` and, for an API credential, a
# `key` string.
printf '%s\n' '{"openrouter":{"type":"api","key":"'"$STORE_KEY"'"}}' >"$AUTH"
equals 'an API record in the store supplies the child' "$(cred_key)" "$STORE_KEY"

# An explicit export is a deliberate choice of ACCOUNT, and that account is the
# one billed. The store never overrides it.
equals 'an exported key wins over the store' \
    "$(OPENROUTER_API_KEY=$ENV_KEY DSH_PREFIX=$cred_prefix HOME=$cred_home \
        OPENCODE_AUTH_FILE=$AUTH sh "$WRAPPER" --version | sed 's/^key=//; s/ argv=.*//')" \
    "$ENV_KEY"
# Exported-but-empty is not a choice of account; it is an unset variable with
# extra steps, so the store still answers.
equals 'an exported but empty key falls back to the store' \
    "$(OPENROUTER_API_KEY='' DSH_PREFIX=$cred_prefix HOME=$cred_home \
        OPENCODE_AUTH_FILE=$AUTH sh "$WRAPPER" --version | sed 's/^key=//; s/ argv=.*//')" \
    "$STORE_KEY"

# Surrounding whitespace is the store's, not the credential's.
printf '%s\n' '{"openrouter":{"type":"api","key":"  '"$STORE_KEY"'  "}}' >"$AUTH"
equals 'a padded key is trimmed, not forwarded with its padding' \
    "$(cred_key)" "$STORE_KEY"

# Every shape that is not an API credential leaves the variable UNSET, so DSH
# reports its own MISSING_CREDENTIAL instead of the wrapper inventing an error
# about a file the user never configured. A wrapper that guessed here would
# hand the gateway a refresh token and call the result a credential problem.
for case in \
    'oauth record:{"openrouter":{"type":"oauth","access":"'"$STORE_KEY"'","refresh":"r"}}' \
    'empty key:{"openrouter":{"type":"api","key":""}}' \
    'whitespace-only key:{"openrouter":{"type":"api","key":"   "}}' \
    'non-string key:{"openrouter":{"type":"api","key":12345}}' \
    'scalar record:{"openrouter":"just-a-string"}' \
    'null record:{"openrouter":null}' \
    'array document:[{"openrouter":{"type":"api","key":"x"}}]' \
    'no openrouter record:{"github-copilot":{"type":"oauth","access":"a"}}'; do
    lbl=${case%%:*}
    printf '%s\n' "${case#*:}" >"$AUTH"
    equals "a $lbl leaves the credential unset" "$(cred_key)" "UNSET"
done

printf 'not json at all {\n' >"$AUTH"
equals 'a malformed store leaves the credential unset' "$(cred_key)" "UNSET"
rc=0
cred >/dev/null 2>&1 || rc=$?
equals 'a malformed store does not fail the launch' "$rc" "0"

: >"$AUTH"
equals 'an empty store file leaves the credential unset' "$(cred_key)" "UNSET"
rm -f "$AUTH"
equals 'a missing store leaves the credential unset' "$(cred_key)" "UNSET"
rc=0
cred >/dev/null 2>&1 || rc=$?
equals 'a missing store does not fail the launch' "$rc" "0"

# A directory where the store belongs is neither readable JSON nor a crash.
mkdir -p "$AUTH"
equals 'a directory where the store belongs leaves the credential unset' \
    "$(cred_key)" "UNSET"
rmdir "$AUTH"

# --- the key reaches the child and nothing else ----------------------------
printf '%s\n' '{"openrouter":{"type":"api","key":"'"$STORE_KEY"'"}}' >"$AUTH"

# argv is world-readable in `ps`, so the credential must never become a word of
# it - not the launcher's, and not the wrapper's own reader's.
check 'the credential never appears in the launched argv' \
    test -z "$(cred | sed 's/^.* argv=//' | awk -v k="$STORE_KEY" 'index($0, k)')"
check 'the wrapper hands its reader a path, never the credential' \
    grep -q 'node -e .* "$opencode_auth"' "$WRAPPER"

# The wrapper itself says nothing. A silent stub makes the wrapper the only
# possible author of any remaining output.
cat >"$cred_prefix/node_modules/.bin/dsh" <<'SILENTSTUB'
#!/bin/sh
exit 0
SILENTSTUB
chmod +x "$cred_prefix/node_modules/.bin/dsh"
quiet=$(DSH_PREFIX=$cred_prefix HOME=$cred_home OPENCODE_AUTH_FILE=$AUTH \
    sh "$WRAPPER" --version 2>&1)
equals 'the wrapper prints nothing at all while adapting a credential' "$quiet" ""

# Restore the echoing stub, then prove nothing was persisted. DSH_HOME defaults
# to $HOME/.dsh here, which is the one directory a careless implementation
# would cache a key into.
cat >"$cred_prefix/node_modules/.bin/dsh" <<'CREDSTUB2'
#!/bin/sh
printf 'key=%s argv=%s\n' "${OPENROUTER_API_KEY:-UNSET}" "$*"
CREDSTUB2
chmod +x "$cred_prefix/node_modules/.bin/dsh"
cred >/dev/null 2>&1
check 'the credential is never written under $DSH_HOME' \
    test -z "$(grep -rl "$STORE_KEY" "$cred_home" 2>/dev/null | head -n 1)"
check 'the adapter leaves no file behind at all' \
    test -z "$(find "$cred_home/.dsh" -type f -print 2>/dev/null | head -n 1)"

# The adapter must not disturb the dispatch contract it sits behind.
equals 'the adapter leaves the dispatch contract intact' \
    "$(DSH_PREFIX=$cred_prefix HOME=$cred_home OPENCODE_AUTH_FILE=$AUTH \
        sh "$WRAPPER" tui --resume abc | sed 's/^key=[^ ]* //')" \
    "argv=--profile dsh-tui --resume abc"

# --- the store path is configurable, and defaults where OpenCode puts it ---
check 'the wrapper defaults to the documented OpenCode store path' \
    grep -q 'OPENCODE_AUTH_FILE:-\$HOME/\.local/share/opencode/auth\.json' "$WRAPPER"
mkdir -p "$cred_home/.local/share/opencode"
printf '%s\n' '{"openrouter":{"type":"api","key":"'"$STORE_KEY"'"}}' \
    >"$cred_home/.local/share/opencode/auth.json"
equals 'with no override the wrapper reads the default store path' \
    "$(DSH_PREFIX=$cred_prefix HOME=$cred_home sh "$WRAPPER" --version |
        sed 's/^key=//; s/ argv=.*//')" \
    "$STORE_KEY"
rm -rf "$cred_home/.local"

# --- the harness scrubs the credential back out of every tool child --------
# Three installed READMEs describe ONE scrub, applied at the subprocess seam:
#   @deepseek-ai/dsh-subprocess    "Children never inherit the harness's
#                                   ambient secrets"
#   @deepseek-ai/dsh-mcp-client    "ambient names matching
#                                   /KEY|PASSWORD|SECRET|TOKEN/i ... are dropped"
#   @deepseek-ai/dsh-bash-local    "the subprocess service scrubs ambient
#                                   credentials ... independently"
# (@deepseek-ai/dsh-terminal-bash says the same for terminal sessions.)
# Reading the prose is not the test: the case below composes the REAL bash
# tool over the REAL subprocess provider and reads the child's environment.
# `RUNTIME` and `real_node` belong to later sections; this one resolves its own
# so the ordering of the file is not load-bearing.
cred_runtime=${DSH_PREFIX:-$HOME/.local/share/dsh}
cred_node=$(command -v node || true)
SCRUB_R=$cred_runtime/node_modules/@deepseek-ai
for pkg_doc in dsh-subprocess dsh-mcp-client dsh-bash-local dsh-terminal-bash; do
    if [ -f "$SCRUB_R/$pkg_doc/README.md" ]; then
        check "the installed $pkg_doc README documents the credential scrub" \
            grep -qi 'scrub' "$SCRUB_R/$pkg_doc/README.md"
    else
        ok "$pkg_doc README check skipped (runtime not provisioned)"
    fi
done
if [ -f "$SCRUB_R/dsh-mcp-client/README.md" ]; then
    check 'the MCP README names the exact scrubbed name class' \
        grep -q 'KEY|PASSWORD|SECRET|TOKEN' "$SCRUB_R/dsh-mcp-client/README.md"
fi

if [ -n "$cred_node" ] && [ -d "$SCRUB_R/dsh-bash-local" ] &&
    [ -d "$SCRUB_R/dsh-subprocess-local" ]; then
    canary=$TMP_ROOT/bash-tool-canary.mjs
    cat >"$canary" <<'CANARY'
// The composed bash tool, not a stand-in: the local subprocess provider under
// the bash executor, the pair every profile composes. Proves a credential in
// the LAUNCHING environment never reaches a tool child.
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
// The dummy the caller exports as OPENROUTER_API_KEY. Held here rather than
// read from a second variable: that variable would itself survive the scrub
// and report as a leak that never happened.
const SENTINEL = 'sk-or-v1-0000canary0000'
const require = createRequire(process.argv[2] + '/package.json')
const load = async (spec) => (await import(pathToFileURL(require.resolve(spec)).href)).default
const { Context } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis')).href)
const ctx = new Context()
ctx.plugin(await load('@deepseek-ai/dsh-subprocess-local'))
ctx.plugin(await load('@deepseek-ai/dsh-bash-local'), { cwd: process.cwd() })
await ctx.start?.()
// Plugins mount asynchronously; wait for the service rather than sleeping.
let shell
for (let i = 0; i < 200 && shell?.run === undefined; i++) {
  shell = ctx.get('shell')
  if (shell?.run === undefined) await new Promise((r) => setTimeout(r, 25))
}
if (shell?.run === undefined) throw new Error('bash-local never registered a shell service')
const out = await shell.run(shell.resolve({ command: 'env', timeoutMs: 20000 }))
const text = out.stdout?.text ?? String(out.stdout ?? '')
process.stdout.write([
  'value=' + (text.includes(SENTINEL) ? 'LEAKED' : 'absent'),
  'name=' + (/^OPENROUTER_API_KEY=/m.test(text) ? 'LEAKED' : 'absent'),
  'harmless=' + (/^CANARY_HARMLESS=kept$/m.test(text) ? 'kept' : 'lost'),
].join(' '))
await ctx.stop?.()
CANARY
    # CANARY_HARMLESS carries no DSH_ prefix on purpose: ambient DSH_* names
    # are scrubbed too, so a DSH_-prefixed control would prove nothing.
    scrubbed=$(OPENROUTER_API_KEY=sk-or-v1-0000canary0000 CANARY_HARMLESS=kept \
        "$cred_node" "$canary" "$cred_runtime" 2>/dev/null || true)
    equals 'a composed bash tool child sees neither the name nor the value' \
        "$scrubbed" "value=absent name=absent harmless=kept"
else
    ok 'composed bash-tool scrub case skipped (runtime not provisioned)'
fi

# ---------------------------------------------------------------------------
# 6. Install ordering, which is the part that silently breaks
# ---------------------------------------------------------------------------
CONF=$ROOT/install.conf.yaml
create_dsh=$(line_of "$CONF" '    - ~/.dsh')
render=$(line_of "$CONF" 'scripts/render-contract.sh')
npm_ci=$(line_of "$CONF" 'npm ci')
init=$(line_of "$CONF" '--profile web --dump-config')
copy_step=$(line_of "$CONF" 'install_copy "$home_patch"')
pnpm_step=$(line_of "$CONF" 'prefix="$HOME/.local/share/dsh-pnpm"')
tui_step=$(line_of "$CONF" 'install --frozen-lockfile')

check 'install creates ~/.dsh' test "$create_dsh" -gt 0
check 'install creates the preset scan root' \
    grep -q '    - ~/.dsh/.agent-presets' "$CONF"
# The renderer never creates an identity; it skips one that is missing. So the
# home has to exist before the contract is rendered or the seventh target is
# silently dropped.
check '~/.dsh is created before the contract render' test "$create_dsh" -lt "$render"
# Linking before DSH builds its own tree lets Dotbot create a plain directory
# where the harness needs its profile.
check 'the runtime is installed before the profile is initialized' \
    test "$npm_ci" -lt "$init"
check 'the profile is initialized before the managed files are copied' \
    test "$init" -lt "$copy_step"
# `dsh-tui` is not a shipped template, so nothing materializes it: it is built
# from its tracked inputs by pnpm, which must therefore already be installed.
check 'the pinned pnpm is installed before the dsh-tui profile needs it' \
    test "$pnpm_step" -lt "$tui_step"
check 'the dsh-tui profile is provisioned before its patch is copied' \
    test "$tui_step" -lt "$copy_step"
# Separate prefixes, so the official runtime graph is untouched by the helper.
check 'the pnpm helper installs into its own prefix' \
    grep -q 'dsh-pnpm' "$CONF"
check 'the pnpm helper is reached by path, never added to PATH' \
    test "$(grep -c 'PATH=.*dsh-pnpm' "$CONF" || true)" = 0
# A single plane package in either place is a split singleton, so the installer
# refuses rather than leaving one behind.
check 'the installer refuses a second plane in the dsh-tui profile' \
    grep -q "second plane, refusing" "$CONF"
# A patch file that parses as null leaves every profile unrouted with no error,
# so every layer is PARSED before it replaces a working file. Section 12b runs
# the check; these two assert it is wired to all three layers.
check 'the installer parses each patch layer before replacing it' \
    grep -q 'check_patch_layer "\$f"' "$CONF"
equals 'all three layers go through the parse check' \
    "$(awk '/for f in "\$home_patch"/, /done/' "$CONF" | grep -c 'cordis.patch.yml' || true)" "2"
# patchReload is live: DSH recomposes the running tree when a patch file
# changes, so a half-written document must never be visible.
check 'the copier writes atomically' grep -q 'mv -f "$tmp" "$2"' "$CONF"
# npm writes into its project directory; a symlink would write through into
# this repo, so the runtime inputs must be copied.
check 'runtime inputs are copied, not linked' grep -q 'cp "deepseek-harness/\$f" "\$prefix/\$f"' "$CONF"
# The patch and the preset follow the same rule, and for a stronger reason: a
# link there aims the harness itself at this working tree, so anything writing
# through it lands in the repo.
equals 'the patch and preset are never linked into ~/.dsh' \
    "$(grep -c '~/\.dsh/profiles/web/cordis\.patch\.yml:\|~/\.dsh/\.agent-presets/dotfiles:' "$CONF" || true)" "0"
check 'the copier removes an existing symlink instead of writing through it' \
    grep -q 'replacing the symlink at' "$CONF"
check 'install links the launcher' grep -q '~/.local/bin/dsh: bin/dsh' "$CONF"

# ---------------------------------------------------------------------------
# 6b. Dotbot runs `shell:` blocks under $SHELL, so ./install pins a POSIX one
# ---------------------------------------------------------------------------
# THE REGRESSION THIS EXISTS FOR. Dotbot passes os.environ['SHELL'] to
# subprocess as `executable`, so a `shell:` block runs under the user's LOGIN
# shell. On a fish login every block here died at its first POSIX assignment
# (`fish: Unsupported use of =`) with the step half-executed, and the whole DSH
# install silently never happened.
#
# Extracting a block and running it under `sh` - which is what the rest of this
# file does - cannot see that, because it skips the very call chain that breaks.
# So these assert the chain: what ./install hands Dotbot, and what Dotbot then
# hands a command.
INSTALL_SH=$ROOT/install
MIC_CONF=$ROOT/dotfiles-mic/install.conf.yaml

check 'the root install script exists' test -f "$INSTALL_SH"
# The upstream behaviour this depends on. A Dotbot bump that stops honouring
# $SHELL would make the pin pointless, and silently so.
check 'Dotbot still selects the interpreter from $SHELL' \
    grep -q "executable = os.environ.get('SHELL')" "$ROOT/dotbot/dotbot/util/common.py"
# Both passes, or the overlay installs under fish while the public layer does
# not - which is worse than failing outright, because it half-works.
equals 'both Dotbot invocations pin the interpreter' \
    "$(grep -c '^[[:space:]]*SHELL="\${DOTBOT_SHELL}" \\$' "$INSTALL_SH" || true)" "2"
check 'the pinned interpreter is POSIX sh' \
    grep -q '^DOTBOT_SHELL="/bin/sh"$' "$INSTALL_SH"
# Command-scoped, not exported: the caller's login shell must survive ./install.
check 'the pin is never exported' \
    test "$(grep -c '^[[:space:]]*export SHELL' "$INSTALL_SH" || true)" = 0

# --- the real seam: Dotbot, a real config, a non-POSIX login shell ----------
# Reproduces the failure and proves the fix, using the REAL Dotbot binary and a
# throwaway config. No live home is touched: the block only writes into a temp
# directory.
login_shell=$(command -v fish || true)
if [ -x "$ROOT/dotbot/bin/dotbot" ] && [ -n "$login_shell" ]; then
    seam=$TMP_ROOT/seam
    mkdir -p "$seam"
    # A block that is POSIX and nothing more: an assignment and a redirect.
    # fish rejects the assignment; every POSIX shell accepts it.
    cat >"$seam/seam.conf.yaml" <<'SEAMCONF'
- shell:
  - command: |
      set -eu
      marker=ran
      printf '%s\n' "$marker" >"$SEAM_OUT"
    description: POSIX assignment canary
    stderr: true
SEAMCONF

    run_seam() { # run_seam <shell>
        rm -f "$seam/out"
        SHELL=$1 SEAM_OUT=$seam/out \
            "$ROOT/dotbot/bin/dotbot" -d "$seam" -c "$seam/seam.conf.yaml" \
            >"$seam/log" 2>&1
    }

    rc=0
    run_seam "$login_shell" || rc=$?
    check 'a fish login shell fails a POSIX block (the reported regression)' \
        test "$rc" != "0"
    check 'the fish failure is the unsupported-assignment one' \
        grep -q "Unsupported use of '='" "$seam/log"
    check 'the fish run produced no output file' test ! -e "$seam/out"

    rc=0
    run_seam /bin/sh || rc=$?
    equals 'the same block under /bin/sh succeeds' "$rc" "0"
    check 'the block under /bin/sh actually ran' test -s "$seam/out"
else
    ok 'Dotbot seam cases skipped (no dotbot checkout or no fish to reproduce with)'
fi

# --- the wiring: what the REAL ./install hands each Dotbot pass -------------
# Runs the real script with a stub Dotbot that records the SHELL it received,
# a stub git so the submodule lines are inert, and a temp HOME so the preflight
# cannot touch the real ~/.claude.
if command -v bash >/dev/null 2>&1; then
    wire=$TMP_ROOT/wire
    mkdir -p "$wire/home" "$wire/base/dotbot/bin" "$wire/base/dotfiles-mic" "$wire/bin"
    cp "$INSTALL_SH" "$wire/base/install"
    : >"$wire/base/install.conf.yaml"
    : >"$wire/base/dotfiles-mic/install.conf.yaml"
    : >"$wire/base/dotfiles-mic/.git"

    cat >"$wire/base/dotbot/bin/dotbot" <<'STUBBOT'
#!/bin/sh
# Records the interpreter Dotbot would hand subprocess, plus which pass this is.
printf '%s\t%s\n' "${SHELL:-UNSET}" "$*" >>"$WIRE_LOG"
exit 0
STUBBOT
    chmod +x "$wire/base/dotbot/bin/dotbot"

    cat >"$wire/bin/git" <<'STUBGIT'
#!/bin/sh
exit 0
STUBGIT
    chmod +x "$wire/bin/git"

    wire_log=$wire/log
    : >"$wire_log"
    rc=0
    (
        PATH=$wire/bin:$PATH HOME=$wire/home WIRE_LOG=$wire_log \
            SHELL=${login_shell:-/usr/bin/false} \
            bash "$wire/base/install"
    ) >"$wire/out" 2>&1 || rc=$?
    equals 'the real install script completes under a fish login shell' "$rc" "0"
    equals 'both Dotbot passes ran' "$(grep -c . "$wire_log" || true)" "2"
    equals 'every Dotbot pass received /bin/sh' \
        "$(awk -F'\t' '$1 == "/bin/sh" { n++ } END { print n + 0 }' "$wire_log")" "2"
    check 'the public pass is the one with the public config' \
        test -n "$(awk -F'\t' 'NR == 1 && index($2, "install.conf.yaml")' "$wire_log")"
    check 'the overlay pass is the one with the overlay config' \
        test -n "$(awk -F'\t' 'NR == 2 && index($2, "dotfiles-mic")' "$wire_log")"
    # The pin must not leak back into the caller.
    check 'the caller login shell is left alone' \
        test -z "$(awk -F'\t' '$1 != "/bin/sh"' "$wire_log")"
else
    ok 'install wiring cases skipped (bash not installed)'
fi

# --- the precondition for pinning /bin/sh at all ---------------------------
# Pinning a POSIX interpreter is only safe while every block IS POSIX. This is
# the standing check: a bashism added later fails here instead of failing an
# install on Ubuntu, where /bin/sh is dash rather than bash in POSIX mode.
scan_node=$(command -v node || true)
scan_prefix=${DSH_PREFIX:-$HOME/.local/share/dsh}
if [ -n "$scan_node" ] && "$scan_node" -e \
    'require("node:module").createRequire(process.argv[1] + "/package.json")("js-yaml")' \
    "$scan_prefix" >/dev/null 2>&1; then
    blocks=$TMP_ROOT/blocks
    mkdir -p "$blocks"
    n_blocks=$("$scan_node" -e '
        const { createRequire } = require("node:module")
        const yaml = createRequire(process.argv[1] + "/package.json")("js-yaml")
        const fs = require("node:fs")
        let n = 0
        for (const [tag, f] of [["pub", process.argv[3]], ["mic", process.argv[4]]]) {
          if (!fs.existsSync(f)) continue
          for (const b of yaml.load(fs.readFileSync(f, "utf8"))) {
            for (const st of (Array.isArray(b.shell) ? b.shell : [])) {
              if (typeof st?.command !== "string") continue
              n++
              fs.writeFileSync(`${process.argv[2]}/${tag}-${n}.sh`, st.command + "\n")
            }
          }
        }
        process.stdout.write(String(n))
    ' "$scan_prefix" "$blocks" "$CONF" "$MIC_CONF")
    check 'the shell blocks were extracted' test "${n_blocks:-0}" -gt 0

    bad_syntax=0
    for b in "$blocks"/*.sh; do
        sh -n "$b" 2>/dev/null || bad_syntax=$((bad_syntax + 1))
    done
    equals 'every shell block parses as POSIX sh' "$bad_syntax" "0"

    # dash is the stricter reading, and it is what /bin/sh IS on Ubuntu/WSL.
    if command -v dash >/dev/null 2>&1; then
        bad_dash=0
        for b in "$blocks"/*.sh; do
            dash -n "$b" 2>/dev/null || bad_dash=$((bad_dash + 1))
        done
        equals 'every shell block parses under dash, which is Ubuntu /bin/sh' \
            "$bad_dash" "0"
    else
        ok 'dash block parse skipped (dash not installed)'
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        check 'no shell block uses a bashism shellcheck can name' \
            sh -c 'shellcheck -s sh -f gcc "$1"/*.sh 2>&1 | grep -qE "SC3[0-9]{3}|SC2039" && exit 1 || exit 0' \
            _ "$blocks"
    else
        ok 'block bashism scan skipped (shellcheck not installed)'
    fi

    # The pin is inert only while nothing downstream reads $SHELL.
    check 'no shell block reads $SHELL, so pinning it changes nothing else' \
        sh -c 'grep -l "SHELL" "$1"/*.sh >/dev/null 2>&1 && exit 1 || exit 0' _ "$blocks"
else
    ok 'shell-block POSIX scan skipped (no installed runtime to borrow js-yaml from)'
fi

# ---------------------------------------------------------------------------
# 7. Contract target and updater wiring
# ---------------------------------------------------------------------------
check 'the renderer knows the seventh target' \
    grep -q '^\$HOME/\.dsh|\$HOME/\.dsh/AGENTS\.md$' "$ROOT/scripts/render-contract.sh"
check 'the updater accepts --only dsh' \
    grep -q 'claude|codex|agy|grok|opencode|muse|ae|dsh|contract' "$ROOT/scripts/harness-update.sh"
check 'the updater has a dsh step' \
    grep -q '^process_dsh() {' "$ROOT/scripts/harness-update.sh"
check 'the dsh step is exported for the supervised shell' \
    grep -q 'process_dsh process_contract' "$ROOT/scripts/harness-update.sh"
check 'the dsh step runs in the dispatch loop' \
    grep -q 'for tool in claude codex agy grok opencode muse ae dsh contract; do' \
    "$ROOT/scripts/harness-update.sh"
# A developer preview must never be upgraded by the daily timer.
check 'the updater never installs or upgrades dsh' \
    test "$(awk '/^process_dsh\(\) \{/, /^\}/' "$ROOT/scripts/harness-update.sh" |
        grep -c 'npm_install_latest\|npm install\|npm update' || true)" = 0
check 'the status probe exists' test -f "$DIR/mcp-status.mjs"

# ---------------------------------------------------------------------------
# 8. The probe refuses to describe a harness it cannot see
# ---------------------------------------------------------------------------
# Probing the repo copy instead of the live preset would report healthy servers
# while DSH mounted none, so these are the cases that must NOT print a count.
PROBE=$DIR/mcp-status.mjs
if command -v node >/dev/null 2>&1; then
    fake_home=$TMP_ROOT/probehome
    mkdir -p "$fake_home/.agent-presets"

    rc=0
    out=$(DSH_HOME=$fake_home node "$PROBE" 2>&1) || rc=$?
    equals 'missing live preset exits 2' "$rc" "2"
    check 'missing live preset names the path it wanted' \
        test -n "$(printf '%s' "$out" | awk '/does not have the managed preset/')"
    check 'missing live preset reports no tool counts' \
        test -z "$(printf '%s' "$out" | awk '/ OK [0-9]+ tool/')"

    # A live preset that is not the managed one is just as misleading.
    mkdir -p "$fake_home/.agent-presets/dotfiles"
    sed 's/serverName: serena/serverName: impostor/' "$PRESET" \
        >"$fake_home/.agent-presets/dotfiles/agent.cordis.yml"
    rc=0
    out=$(DSH_HOME=$fake_home node "$PROBE" 2>&1) || rc=$?
    equals 'drifted live preset exits 2' "$rc" "2"
    check 'drifted live preset says it would not describe the harness' \
        test -n "$(printf '%s' "$out" | awk '/does not match the tracked one/')"
    check 'drifted live preset reports no tool counts' \
        test -z "$(printf '%s' "$out" | awk '/ OK [0-9]+ tool/')"

    # An identical live preset but no runtime: still refuse, never guess.
    cp "$PRESET" "$fake_home/.agent-presets/dotfiles/agent.cordis.yml"
    rc=0
    out=$(DSH_HOME=$fake_home DSH_PREFIX=$TMP_ROOT/no-runtime node "$PROBE" 2>&1) || rc=$?
    equals 'missing runtime prefix exits 2' "$rc" "2"
    check 'missing runtime prefix points at ./install' \
        test -n "$(printf '%s' "$out" | awk '/run \.\/install/')"
else
    ok 'probe cases skipped (node not installed)'
fi

# ---------------------------------------------------------------------------
# 9. Child environment: the probe must scrub exactly as the harness does
# ---------------------------------------------------------------------------
# The probe imports scrubbedParentEnv from the pinned runtime instead of
# reimplementing it, so this exercises the REAL scrub under a seeded
# environment. Skipped when the runtime is not provisioned.
RUNTIME=${DSH_PREFIX:-$HOME/.local/share/dsh}
check 'the probe builds its child env from the harness scrub' \
    grep -q 'scrubbedParentEnv(), \.\.\.env' "$PROBE"
check 'the probe never forwards the raw environment' \
    test "$(grep -c '\.\.\.process\.env' "$PROBE" || true)" = 0

if [ -f "$RUNTIME/node_modules/@deepseek-ai/dsh-subprocess/lib/index.js" ] &&
    command -v node >/dev/null 2>&1; then
    canary=$(
        MY_API_KEY=leak MY_PASSWORD=leak MY_SECRET=leak MY_TOKEN=leak \
            DSH_WEB_URL=leak HARMLESS=kept \
            node --input-type=module -e "
            const { scrubbedParentEnv } = await import('file://$RUNTIME/node_modules/@deepseek-ai/dsh-subprocess/lib/index.js')
            const env = { ...scrubbedParentEnv(), ...{ ROW_OVERRIDE: 'set', HARMLESS: 'overridden' } }
            const leaked = ['MY_API_KEY','MY_PASSWORD','MY_SECRET','MY_TOKEN','DSH_WEB_URL'].filter((k) => k in env)
            process.stdout.write([
              'leaked=' + leaked.join(','),
              'path=' + (env.PATH ? 'kept' : 'lost'),
              'home=' + (env.HOME ? 'kept' : 'lost'),
              'row=' + env.ROW_OVERRIDE,
              'merge=' + env.HARMLESS,
            ].join(' '))
          "
    )
    equals 'secrets and DSH_* are scrubbed, PATH/HOME kept, row env wins' \
        "$canary" "leaked= path=kept home=kept row=set merge=overridden"
else
    ok 'env canary skipped (runtime not provisioned)'
fi

# ---------------------------------------------------------------------------
# 10. Updater severity, exercised with fake MCP outcomes
# ---------------------------------------------------------------------------
# Losing Serena, Context7 or Chrome DevTools is a real failure that must reach
# the daily notification. Losing only OpenDesign is explicit and nonfatal. And
# an OK line must never be printed over an earlier static failure. Greps cannot
# prove any of that, so these run the real step function.
UPDATER=$ROOT/scripts/harness-update.sh
real_node=$(command -v node || true)
if [ -n "$real_node" ]; then
    up_home=$TMP_ROOT/uphome
    up_prefix=$up_home/.local/share/dsh
    mkdir -p "$up_home/.local/bin" "$up_prefix/node_modules/.bin" \
        "$up_prefix/node_modules/@deepseek-ai/dsh-agent-presets/presets/standard"
    for f in .npmrc package.json package-lock.json; do
        cp "$DIR/$f" "$up_prefix/$f"
    done
    pinned=$("$real_node" -e \
        'process.stdout.write(require(process.argv[1]).packages["node_modules/@deepseek-ai/dsh"].version)' \
        "$DIR/package-lock.json")
    # The stub answers both things the updater asks the launcher for: its
    # version, and a composed config dump per profile. The dump matters because
    # the composition gate is the only check that can see an unmatched patch
    # row, and `sdk-minimal` is expected to emit exactly one - it is the one
    # shipped template without dsh-base, so the home layer's llm-pi-ai row has
    # nothing to target there.
    cat >"$up_prefix/node_modules/.bin/dsh" <<STUBDSH
#!/bin/sh
profile=
dump=0
while [ "\$#" -gt 0 ]; do
    case \$1 in
    --profile) profile=\$2; shift 2 ;;
    --dump-config) dump=1; shift ;;
    *) shift ;;
    esac
done
if [ "\$dump" -eq 0 ]; then
    printf '%s\n' "$pinned"
    exit 0
fi
if [ "\$profile" = sdk-minimal ]; then
    # FAKE_SDK_WARN lets a test choose which shape the composition gate has to
    # tell apart. TWO pinned lines are the expected state now - sdk-minimal
    # matches neither the route row nor the default-model row - so the gate has
    # to separate: both pinned, both present but one reworded, a third line, a
    # missing one, and silence.
    case \${FAKE_SDK_WARN:-pinned} in
    pinned)
        printf 'dsh: [%s] patch: entry "llm-pi-ai" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        printf 'dsh: [%s] patch: entry "agent-default-model" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        ;;
    changed)
        printf 'dsh: [%s] patch: entry "llm-pi-ai" skipped\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        printf 'dsh: [%s] patch: entry "agent-default-model" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        ;;
    repeated)
        printf 'dsh: [%s] patch: entry "llm-pi-ai" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        printf 'dsh: [%s] patch: entry "llm-pi-ai" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        ;;
    triple)
        printf 'dsh: [%s] patch: entry "llm-pi-ai" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        printf 'dsh: [%s] patch: entry "agent-default-model" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        printf 'dsh: [%s] patch: entry "something-else" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        ;;
    single)
        printf 'dsh: [%s] patch: entry "llm-pi-ai" not found\n' "\$HOME/.dsh/cordis.patch.yml" >&2
        ;;
    none) ;;
    esac
    printf -- '- id: sdk-minimal\n'
    exit 0
fi
printf -- '- id: llm-pi-ai\n'
printf '  config:\n    providers:\n      openrouter:\n'
printf '        baseURL: https://openrouter.ai/api/v1\n'
# The default selection is a SEPARATE row from the route, and the gate counts
# it separately. FAKE_DEFAULT drops or duplicates it so the count assertion is
# exercised rather than assumed.
case \${FAKE_DEFAULT:-one} in
one)
    printf -- '- id: agent-default-model\n'
    printf '  config:\n    provider: openrouter\n'
    printf "    model: '@preset/deepseek-v41-flash-us-zdr'\n"
    ;;
double)
    printf -- '- id: agent-default-model\n'
    printf '  config:\n    provider: openrouter\n'
    printf "    model: '@preset/deepseek-v41-flash-us-zdr'\n"
    printf -- '- id: agent-default-model\n'
    printf '  config:\n    provider: openrouter\n'
    printf "    model: '@preset/deepseek-v41-flash-us-zdr'\n"
    ;;
missing) ;;
unrouted)
    printf -- '- id: agent-default-model\n'
    printf '  config:\n    provider: deepseek-official\n'
    printf '    model: deepseek-flash\n'
    ;;
esac
exit 0
STUBDSH
    chmod +x "$up_prefix/node_modules/.bin/dsh"

    # The pinned pnpm helper, in its own prefix exactly as ./install lays it out.
    up_pnpm=$up_home/.local/share/dsh-pnpm
    mkdir -p "$up_pnpm/node_modules/pnpm/bin"
    for f in .npmrc package.json package-lock.json; do
        cp "$DIR/pnpm/$f" "$up_pnpm/$f"
    done
    pnpm_pinned=$("$real_node" -e \
        'process.stdout.write(require(process.argv[1]).packages["node_modules/pnpm"].version)' \
        "$DIR/pnpm/package-lock.json")
    printf 'process.stdout.write("%s\\n")\n' "$pnpm_pinned" >"$up_pnpm/node_modules/pnpm/bin/pnpm.mjs"

    # The managed dsh-tui profile, built from the same tracked inputs ./install
    # copies. Its node_modules stays empty: a single @deepseek-ai package here
    # is the split singleton the whole profile-local shape exists to prevent.
    mkdir -p "$up_home/.dsh/profiles/dsh-tui/node_modules"
    for f in package.json pnpm-workspace.yaml pnpm-lock.yaml cordis.patch.yml; do
        cp "$DIR/profiles/dsh-tui/$f" "$up_home/.dsh/profiles/dsh-tui/$f"
    done
    # What actually boots is the package in node_modules, so the fixture has to
    # carry one: the tracked inputs being self-consistent says nothing about
    # what a half-finished or stale install left behind.
    tui_pinned=$("$real_node" -e \
        'process.stdout.write(require(process.argv[1]).dependencies["@deepseek-harness-tui/dsh-tui"])' \
        "$DIR/profiles/dsh-tui/package.json")
    up_tui=$up_home/.dsh/profiles/dsh-tui/node_modules/@deepseek-harness-tui/dsh-tui
    mkdir -p "$up_tui"
    write_installed_tui() { # write_installed_tui <version>
        printf '{"name":"@deepseek-harness-tui/dsh-tui","version":"%s"}\n' "$1" \
            >"$up_tui/package.json"
    }
    write_installed_tui "$tui_pinned"
    # The tracked preset is the copy plus our appended block, so the "installed
    # standard" fixture is exactly the BYTES before the marker line. A line
    # count would not be the same thing: it silently tolerates a changed line
    # ending or a missing final newline, which is drift.
    std_dir=$up_prefix/node_modules/@deepseek-ai/dsh-agent-presets/presets/standard
    head -c "$MARKER_OFFSET" "$PRESET" >"$std_dir/agent.cordis.yml"
    # The runtime copies the updater compares against the tracked originals.
    mkdir -p "$up_home/.dsh/profiles/web" "$up_home/.dsh/.agent-presets/dotfiles"
    # Three layers now: the shared route at the home level, one roster row per
    # profile. The updater compares each against its own tracked source.
    cp "$PATCH" "$up_home/.dsh/cordis.patch.yml"
    cp "$WEB_PATCH" "$up_home/.dsh/profiles/web/cordis.patch.yml"
    cp "$PRESET" "$DIR/presets/dotfiles/preset.yml" "$up_home/.dsh/.agent-presets/dotfiles/"

    # `harness-update.sh` rewrites PATH to put $HOME/.local/bin first, so a fake
    # node there is what the step actually runs. It answers for the probe and
    # delegates everything else to the real node.
    cat >"$up_home/.local/bin/node" <<FAKE
#!/bin/sh
case "\$*" in
    *mcp-status.mjs*)
        cat "\$FAKE_MCP_OUT"
        exit "\$FAKE_MCP_RC"
        ;;
esac
exec "$real_node" "\$@"
FAKE
    chmod +x "$up_home/.local/bin/node"

    run_updater() { # run_updater <fixture-output> <fixture-rc>
        printf '%s\n' "$1" >"$TMP_ROOT/mcpout"
        HOME=$up_home DSH_PREFIX=$up_prefix \
            FAKE_MCP_OUT=$TMP_ROOT/mcpout FAKE_MCP_RC=$2 \
            sh "$UPDATER" --only dsh --check 2>&1
    }

    all_ok='mcp serena OK 23 tool(s) in 1ms
mcp context7 OK 2 tool(s) in 1ms
mcp chrome-devtools OK 29 tool(s) in 1ms
mcp open-design OK 22 tool(s) in 1ms'
    optional_down='mcp serena OK 23 tool(s) in 1ms
mcp context7 OK 2 tool(s) in 1ms
mcp chrome-devtools OK 29 tool(s) in 1ms
mcp open-design DEGRADED connection refused'
    core_down='mcp serena OK 23 tool(s) in 1ms
mcp context7 DEGRADED timed out after 60000ms
mcp chrome-devtools OK 29 tool(s) in 1ms
mcp open-design OK 22 tool(s) in 1ms'

    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'all servers healthy exits 0' "$rc" "0"
    check 'all servers healthy reports OK' \
        test -n "$(printf '%s' "$out" | awk '/^dsh OK /')"

    rc=0
    out=$(run_updater "$optional_down" 1) || rc=$?
    equals 'only OpenDesign down stays nonfatal' "$rc" "0"
    check 'only OpenDesign down is reported as degraded' \
        test -n "$(printf '%s' "$out" | awk '/^dsh DEGRADED optional MCP unavailable/')"
    check 'only OpenDesign down does not claim OK' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"

    rc=0
    out=$(run_updater "$core_down" 1) || rc=$?
    check 'a core server loss fails the step' test "$rc" != "0"
    check 'a core server loss is reported as FAIL' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL 1 core MCP server/')"
    check 'a core server loss does not claim OK' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"

    rc=0
    out=$(run_updater 'mcp-status: the harness does not have the managed preset' 2) || rc=$?
    check 'an unprobeable harness fails the step' test "$rc" != "0"
    check 'an unprobeable harness is not called degraded' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL cannot probe the live MCP configuration/')"

    # Static failure first, every server healthy second: the OK line must not
    # paper over it.
    printf 'tampered\n' >>"$up_prefix/package.json"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a drifted runtime copy fails the step' test "$rc" != "0"
    check 'a drifted runtime copy is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL runtime package.json differs/')"
    check 'a healthy probe never prints OK over a static failure' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"
    cp "$DIR/package.json" "$up_prefix/package.json"

    # --- the snapshot drift check, in both directions ----------------------
    std=$std_dir/agent.cordis.yml
    cp "$std" "$TMP_ROOT/standard.orig"

    # A shipped `standard` that GREW: upstream added rows the snapshot does
    # not carry.
    printf '\n- id: brand-new-upstream-row\n  name: %s\n' "'@deepseek-ai/dsh-whatever'" >>"$std"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a grown installed standard fails the step' test "$rc" != "0"
    check 'a grown installed standard is reported as drift' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL managed preset drifted/')"

    # A shipped standard that SHRANK is the case the replaced rule got wrong.
    # It compared the tracked preset's first N lines, N taken from the SHIPPED
    # file, so upstream deleting trailing rows left the surviving prefix
    # matching and the drift invisible.
    head -n 10 "$TMP_ROOT/standard.orig" >"$std"
    check 'the replaced line-count rule would have missed a shrunken standard' \
        sh -c 'head -n "$(wc -l <"$1")" "$2" | cmp -s - "$1"' _ "$std" "$PRESET"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a shrunken installed standard fails the step' test "$rc" != "0"
    check 'a shrunken installed standard is reported as drift' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL managed preset drifted/')"

    # A single changed byte inside the snapshot region is drift as well.
    sed '5s/.*/# tampered/' "$TMP_ROOT/standard.orig" >"$std"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'one changed byte in the snapshot is drift' test "$rc" != "0"
    cp "$TMP_ROOT/standard.orig" "$std"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'the restored standard passes again' "$rc" "0"

    # --- the runtime copies are compared, not assumed ----------------------
    up_patch=$up_home/.dsh/profiles/web/cordis.patch.yml
    up_preset=$up_home/.dsh/.agent-presets/dotfiles

    # Each of the three layers is compared against its OWN tracked source, and
    # each is named distinctly: the roster ids differ between the surfaces, so
    # "a patch drifted" is not actionable unless it says which.
    for layer in \
        "home:$up_home/.dsh/cordis.patch.yml:$PATCH" \
        "web profile:$up_patch:$WEB_PATCH" \
        "dsh-tui profile:$up_home/.dsh/profiles/dsh-tui/cordis.patch.yml:$TUI_PATCH"; do
        lbl=${layer%%:*}
        rest=${layer#*:}
        live=${rest%:*}
        src=${rest##*:}

        printf '\n# hand edit\n' >>"$live"
        rc=0
        out=$(run_updater "$all_ok" 0) || rc=$?
        check "a drifted $lbl patch fails the step" test "$rc" != "0"
        check "a drifted $lbl patch is named" \
            test -n "$(printf '%s' "$out" | awk -v l="$lbl" 'index($0, "dsh FAIL " l " cordis.patch.yml differs")')"
        cp "$src" "$live"

        rm -f "$live"
        ln -s "$src" "$live"
        rc=0
        out=$(run_updater "$all_ok" 0) || rc=$?
        check "a symlinked $lbl patch fails the step" test "$rc" != "0"
        check "a symlinked $lbl patch is named as a symlink" \
            test -n "$(printf '%s' "$out" | awk -v l="$lbl" 'index($0, "dsh FAIL " l " cordis.patch.yml is a symlink")')"
        rm -f "$live"
        cp "$src" "$live"
    done

    # The installed TUI, not just the tracked pin. A profile installed before
    # the pin moved, or one whose install never finished, passes every static
    # gate above while running something else entirely.
    rm -rf "$up_home/.dsh/profiles/dsh-tui/node_modules/@deepseek-harness-tui"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a dsh-tui profile with no installed TUI fails the step' test "$rc" != "0"
    check 'the missing installed TUI is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL the dsh-tui profile has no installed TUI package/')"
    check 'a missing installed TUI never prints OK' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"

    mkdir -p "$up_tui"
    write_installed_tui 0.0.0-not-the-pin
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'an installed TUI that is not the pin fails the step' test "$rc" != "0"
    check 'both versions are named so the drift is actionable' \
        test -n "$(printf '%s' "$out" | awk -v v="$tui_pinned" \
            'index($0, "dsh FAIL installed TUI 0.0.0-not-the-pin does not match pinned " v)')"
    write_installed_tui "$tui_pinned"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'the restored installed TUI passes again' "$rc" "0"

    # --- the pinned sdk-minimal exception, and its DEGRADED path -----------
    # TWO unmatched-row warnings on sdk-minimal are expected - it matches
    # neither the route row nor the default-model row - and both must stay
    # invisible. CHANGED text across the same two lines is a signal to read,
    # not a broken surface: exit 0, but never an OK line over it.
    check 'the pinned sdk-minimal warnings are not themselves reported' \
        test -z "$(printf '%s' "$out" | awk '/sdk-minimal/')"

    FAKE_SDK_WARN=changed
    export FAKE_SDK_WARN
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'changed text across the same two warnings stays nonfatal' "$rc" "0"
    check 'the changed sdk-minimal warnings are reported as degraded' \
        test -n "$(printf '%s' "$out" | awk '/^dsh DEGRADED sdk-minimal warnings changed/')"
    check 'the changed warning text is quoted so it can be read' \
        test -n "$(printf '%s' "$out" | awk 'index($0, "skipped")')"
    check 'a degraded sdk-minimal never also prints OK' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"
    check 'a degraded run still ends in a single verdict line' \
        test -n "$(printf '%s' "$out" | awk '/^dsh DEGRADED see the dsh lines above/')"

    # Two lines of the RIGHT COUNT but the wrong composition: the same warning
    # twice is not the pinned pair, and a gate that counted matches in bulk
    # would have called this healthy.
    FAKE_SDK_WARN=repeated
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'one warning emitted twice stays nonfatal but is not silent' "$rc" "0"
    check 'one warning emitted twice is reported as degraded' \
        test -n "$(printf '%s' "$out" | awk '/^dsh DEGRADED sdk-minimal warnings changed/')"

    # A THIRD warning line is a failure, not a signal.
    FAKE_SDK_WARN=triple
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a third sdk-minimal warning fails the step' test "$rc" != "0"
    check 'the extra sdk-minimal warning is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL sdk-minimal does not emit exactly the two pinned warnings/')"

    # So is a MISSING one: half the exception is not the exception.
    FAKE_SDK_WARN=single
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'only one of the two sdk-minimal warnings fails the step' test "$rc" != "0"
    check 'the missing sdk-minimal warning is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL sdk-minimal does not emit exactly the two pinned warnings/')"

    # No warning at all means the pinned exception has gone stale.
    FAKE_SDK_WARN=none
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'vanished sdk-minimal warnings fail the step' test "$rc" != "0"
    check 'the stale pinned exception is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL sdk-minimal no longer emits its known unmatched-row warnings/')"

    FAKE_SDK_WARN=pinned
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'the pinned sdk-minimal warnings pass again' "$rc" "0"
    unset FAKE_SDK_WARN

    # --- the default selection is counted, not assumed ---------------------
    # The bug this whole row exists for was a composed route nobody selected:
    # every profile carried the OpenRouter provider and every fresh agent still
    # started on deepseek-official. A gate that counted only the route was
    # green throughout, so the count below is the one that would have caught it.
    export FAKE_DEFAULT
    FAKE_DEFAULT=missing
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a profile composing the route but no preset default fails the step' \
        test "$rc" != "0"
    check 'the missing preset default is named with its count' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL profile dsh-tui carries 0 preset default\(s\), expected 1/')"
    check 'a missing preset default never prints OK' \
        test -z "$(printf '%s' "$out" | awk '/^dsh OK /')"

    # A default pointing somewhere else is exactly the RED state, and it must
    # read as a missing preset default rather than as a healthy profile.
    FAKE_DEFAULT=unrouted
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a default selecting the vendor API fails the step' test "$rc" != "0"
    check 'the unrouted default is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL profile dsh-tui carries 0 preset default\(s\), expected 1/')"

    # Two copies is drift in the other direction: a duplicated row means the
    # home layer and a profile layer both own the default.
    FAKE_DEFAULT=double
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a duplicated preset default fails the step' test "$rc" != "0"
    check 'the duplicated preset default is named with its count' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL profile dsh-tui carries 2 preset default\(s\), expected 1/')"

    FAKE_DEFAULT=one
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'the single preset default passes again' "$rc" "0"
    unset FAKE_DEFAULT

    # The plane gate, on both prefixes it protects.
    mkdir -p "$up_home/.dsh/profiles/dsh-tui/node_modules/@deepseek-ai/dsh-llm"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a plane package in the dsh-tui profile fails the step' test "$rc" != "0"
    check 'the second plane in the profile is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL dsh-tui profile contains @deepseek-ai/')"
    rm -rf "$up_home/.dsh/profiles/dsh-tui/node_modules/@deepseek-ai"

    mkdir -p "$up_pnpm/node_modules/@deepseek-ai/dsh-llm"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a plane package in the pnpm helper fails the step' test "$rc" != "0"
    check 'the second plane in the helper is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL pnpm helper prefix contains @deepseek-ai/')"
    rm -rf "$up_pnpm/node_modules/@deepseek-ai"

    # A drifted TUI lock means the profile on disk is not the one that was
    # gated, which is exactly what the pin exists to catch.
    printf '\n# drift\n' >>"$up_home/.dsh/profiles/dsh-tui/pnpm-lock.yaml"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a drifted dsh-tui lock fails the step' test "$rc" != "0"
    check 'the drifted dsh-tui lock is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL dsh-tui profile pnpm-lock.yaml differs/')"
    cp "$DIR/profiles/dsh-tui/pnpm-lock.yaml" "$up_home/.dsh/profiles/dsh-tui/pnpm-lock.yaml"

    rm -rf "$up_preset"
    ln -s "$DIR/presets/dotfiles" "$up_preset"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a symlinked runtime preset fails the step' test "$rc" != "0"
    check 'a symlinked runtime preset is named as a symlink' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL runtime preset is a symlink/')"
    rm -f "$up_preset"
    mkdir -p "$up_preset"
    cp "$PRESET" "$DIR/presets/dotfiles/preset.yml" "$up_preset/"

    printf 'left over\n' >"$up_preset/retired.yml"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'an untracked file in the runtime preset fails the step' test "$rc" != "0"
    check 'the untracked runtime preset file is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL runtime preset carries retired.yml/')"
    rm -f "$up_preset/retired.yml"

    printf '\n# hand edit\n' >>"$up_preset/preset.yml"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a drifted runtime preset file fails the step' test "$rc" != "0"
    check 'the drifted runtime preset file is named' \
        test -n "$(printf '%s' "$out" | awk '/^dsh FAIL runtime preset file preset.yml differs/')"
    cp "$DIR/presets/dotfiles/preset.yml" "$up_preset/preset.yml"

    rm -f "$up_preset/agent.cordis.yml"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    check 'a missing runtime preset file fails the step' test "$rc" != "0"
    cp "$PRESET" "$up_preset/agent.cordis.yml"
    rc=0
    out=$(run_updater "$all_ok" 0) || rc=$?
    equals 'the restored runtime copies pass again' "$rc" "0"
else
    ok 'updater severity cases skipped (node not installed)'
fi

# ---------------------------------------------------------------------------
# 11. The install step must retry after a failed npm ci
# ---------------------------------------------------------------------------
# "inputs equal and node_modules present" is not proof of a good install: a
# failed `npm ci` leaves a partial tree that looks complete to the next run.
# This runs the REAL step out of install.conf.yaml against a fake npm.
step=$TMP_ROOT/npm-ci-step.sh
awk '
    /^        set -eu$/ { collecting = 1 }
    collecting && /^      description: Installing the pinned DeepSeek Harness runtime$/ { exit }
    collecting { sub(/^        /, ""); print }
' "$CONF" >"$step"
check 'the install step was extracted' test -s "$step"
check 'the extracted step is valid shell' sh -n "$step"
check 'the extracted step clears the stamp before installing' grep -q 'rm -f "$stamp"' "$step"

fake_npm_home=$TMP_ROOT/stamphome
mkdir -p "$fake_npm_home/bin"
cat >"$fake_npm_home/bin/npm" <<'FAKENPM'
#!/bin/sh
# Records every invocation, and fails when asked to.
printf '%s\n' "$*" >>"$NPM_CALLS"
mkdir -p node_modules/partial
[ "${NPM_FAIL:-0}" = "1" ] && exit 1
exit 0
FAKENPM
chmod +x "$fake_npm_home/bin/npm"

calls=$TMP_ROOT/npm-calls
: >"$calls"
prefix=$fake_npm_home/.local/share/dsh
stamp=$prefix/.npm-ci-ok

run_step() { # run_step <fail?>
    (
        cd "$ROOT" || exit 1
        PATH=$fake_npm_home/bin:$PATH HOME=$fake_npm_home \
            NPM_CALLS=$calls NPM_FAIL=$1 sh "$step"
    )
}

rc=0
run_step 1 >/dev/null 2>&1 || rc=$?
check 'a failed npm ci fails the step' test "$rc" != "0"
check 'a failed npm ci writes no success stamp' test ! -e "$stamp"
check 'a failed npm ci can still leave a partial tree' test -d "$prefix/node_modules"
equals 'the failed attempt called npm once' "$(grep -c . "$calls")" "1"

rc=0
run_step 0 >/dev/null 2>&1 || rc=$?
equals 'the next install retries despite the partial tree' "$rc" "0"
equals 'the retry called npm a second time' "$(grep -c . "$calls")" "2"
check 'a successful npm ci writes the stamp' test -s "$stamp"

rc=0
run_step 0 >/dev/null 2>&1 || rc=$?
equals 'a third run with unchanged inputs is a no-op' "$(grep -c . "$calls")" "2"
equals 'the no-op run still succeeds' "$rc" "0"

# A changed input must invalidate the stamp even though node_modules is intact.
printf 'stale\n' >"$stamp"
run_step 0 >/dev/null 2>&1 || true
equals 'a stale stamp forces a reinstall' "$(grep -c . "$calls")" "3"

# ---------------------------------------------------------------------------
# 12. The managed patch and preset are COPIES, and copying never writes back
# ---------------------------------------------------------------------------
# A symlink in ~/.dsh aims the harness at this working tree, so anything that
# writes through it lands in the repo. `cp` onto a symlink writes THROUGH it,
# which is the failure this exercises: the real step out of install.conf.yaml,
# run against a decoy the symlink points at.
copy=$TMP_ROOT/copy-step.sh
awk '
    /^        profile="\$HOME\/\.dsh\/profiles\/web"$/ { collecting = 1; print "set -eu" }
    collecting && /^      description: Installing the managed DeepSeek Harness patch and preset$/ { exit }
    collecting { sub(/^        /, ""); print }
' "$CONF" >"$copy"
check 'the copy step was extracted' test -s "$copy"
check 'the extracted copy step is valid shell' sh -n "$copy"

copy_home=$TMP_ROOT/copyhome
mkdir -p "$copy_home/.dsh/profiles/web" "$copy_home/.dsh/.agent-presets" \
    "$copy_home/.dsh/profiles/dsh-tui"
decoy=$TMP_ROOT/decoy.yml
printf 'DECOY - must not be overwritten\n' >"$decoy"
ln -s "$decoy" "$copy_home/.dsh/profiles/web/cordis.patch.yml"
ln -s "$DIR/presets/dotfiles" "$copy_home/.dsh/.agent-presets/dotfiles"

run_copy() {
    (
        cd "$ROOT" || exit 1
        HOME=$copy_home sh "$copy"
    )
}
rc=0
run_copy >/dev/null 2>&1 || rc=$?
equals 'the copy step succeeds' "$rc" "0"

copied_patch=$copy_home/.dsh/profiles/web/cordis.patch.yml
copied_preset=$copy_home/.dsh/.agent-presets/dotfiles
check 'the patch symlink was replaced by a regular file' \
    sh -c 'test -f "$1" && test ! -L "$1"' _ "$copied_patch"
check 'the copied web profile patch matches its tracked source' \
    cmp -s "$WEB_PATCH" "$copied_patch"
# The shared route lands one level up, where every profile picks it up.
check 'the copied home layer matches its tracked source' \
    cmp -s "$PATCH" "$copy_home/.dsh/cordis.patch.yml"
check 'the copied home layer is a regular file' \
    sh -c 'test -f "$1" && test ! -L "$1"' _ "$copy_home/.dsh/cordis.patch.yml"
# The two profile layers are not interchangeable, so prove the web profile did
# not receive the terminal profile's roster row.
# A row, not a mention: each file's comments name the other id deliberately.
check 'the web profile did not receive the scoped roster row' \
    test "$(grep -c '^- id: dsh-tui-agent-presets$' "$copied_patch" || true)" = 0
check 'the dsh-tui profile did not receive the official roster row' \
    test "$(grep -c '^- id: agent-presets$' "$copy_home/.dsh/profiles/dsh-tui/cordis.patch.yml" || true)" = 0
check 'the copied dsh-tui patch matches its tracked source' \
    cmp -s "$TUI_PATCH" "$copy_home/.dsh/profiles/dsh-tui/cordis.patch.yml"
check 'the preset symlink was replaced by a real directory' \
    sh -c 'test -d "$1" && test ! -L "$1"' _ "$copied_preset"
check 'the copied preset composition matches the tracked one' \
    cmp -s "$PRESET" "$copied_preset/agent.cordis.yml"
check 'the copied preset metadata matches the tracked one' \
    cmp -s "$DIR/presets/dotfiles/preset.yml" "$copied_preset/preset.yml"
check 'the copied preset files are regular files' \
    sh -c 'test ! -L "$1/agent.cordis.yml" && test ! -L "$1/preset.yml"' _ "$copied_preset"
# The point of the whole finding: nothing was written through the link.
equals 'the decoy behind the symlink was never written' \
    "$(cat "$decoy")" "DECOY - must not be overwritten"

# A second run is a no-op, and a file retired from the preset is mirrored out.
# HARD guard, not an assertion: if the copy step failed above, this path is
# still the symlink into the repo, and the next line would write the fixture
# straight into deepseek-harness/presets/dotfiles/. A failed assertion would
# report that afterwards; this stops before it happens.
if [ -L "$copied_preset" ] || [ ! -d "$copied_preset" ]; then
    bad 'the runtime preset is still a link - refusing to write the retired-file fixture'
else
    printf 'left over\n' >"$copied_preset/retired.yml"
fi
rc=0
run_copy >/dev/null 2>&1 || rc=$?
equals 'the copy step is repeatable' "$rc" "0"
check 'a retired preset file is removed from the runtime copy' \
    test ! -e "$copied_preset/retired.yml"
check 'the tracked preset is untouched by the mirror' \
    test -f "$DIR/presets/dotfiles/preset.yml"

# ---------------------------------------------------------------------------
# 12b. The patch-layer parse check tells the broken shapes apart
# ---------------------------------------------------------------------------
# A layer that parses as null leaves every profile unrouted with NO error, and
# a scalar or a map breaks composition instead. Text inspection cannot tell any
# of those from a valid list, which is the whole reason this parses. It needs
# the runtime's own js-yaml, so it runs where a runtime exists and says so
# where one does not.
layer_prefix=${DSH_PREFIX:-$HOME/.local/share/dsh}
if [ -n "$real_node" ] && "$real_node" -e \
    'const r = require("node:module").createRequire(process.argv[1] + "/package.json")
     r("js-yaml"); if (!r("@deepseek-ai/cordis-plugin-include").entryListSchema) process.exit(1)' \
    "$layer_prefix" >/dev/null 2>&1; then
    layer=$TMP_ROOT/check-patch-layer.sh
    {
        printf 'set -eu\nprefix=$1\nshift\n'
        awk '
            /^        check_patch_layer\(\) \{$/ { f = 1 }
            f { sub(/^        /, ""); print; if ($0 == "}") exit }
        ' "$CONF"
        printf 'check_patch_layer "$1"\n'
    } >"$layer"
    check 'the parse check was extracted' test -s "$layer"
    check 'the extracted parse check is valid shell' sh -n "$layer"

    run_layer() { # run_layer <file>
        sh "$layer" "$layer_prefix" "$1" 2>&1
    }
    layer_rc() { # layer_rc <file>
        sh "$layer" "$layer_prefix" "$1" >/dev/null 2>&1
    }

    # Accepted: the real files, and a deliberately empty layer.
    for good in "$PATCH" "$WEB_PATCH" "$TUI_PATCH"; do
        check "a tracked layer parses as a list ($(basename "$(dirname "$good")"))" \
            layer_rc "$good"
    done
    printf '[]\n' >"$TMP_ROOT/layer-empty.yml"
    check 'a deliberately empty layer is accepted as the literal []' \
        layer_rc "$TMP_ROOT/layer-empty.yml"
    # The loader's own `!!js` scalar tag is not stock YAML; rejecting it here
    # would reject a file a real boot accepts.
    printf -- '- id: x\n  when: !!js "ctx.foo === 1"\n' >"$TMP_ROOT/layer-js.yml"
    check 'the loader-specific !!js tag is accepted, as the loader accepts it' \
        layer_rc "$TMP_ROOT/layer-js.yml"
    # ...and the dialect is the loader's, not js-yaml's default: DEFAULT_SCHEMA
    # would happily construct a tag the loader has never heard of.
    printf -- '- id: x\n  at: !!timestamp 2026-09-12\n' >"$TMP_ROOT/layer-tag.yml"
    check 'a tag outside the loader dialect is refused, as a boot would refuse it' \
        sh -c '! sh "$1" "$2" "$3" >/dev/null 2>&1' _ "$layer" "$layer_prefix" \
        "$TMP_ROOT/layer-tag.yml"

    # Refused, each for its own reason, and each with a distinct message.
    printf '# only a comment\n' >"$TMP_ROOT/layer-comment.yml"
    : >"$TMP_ROOT/layer-blank.yml"
    printf 'just a string\n' >"$TMP_ROOT/layer-scalar.yml"
    printf 'id: llm-pi-ai\nconfig: {}\n' >"$TMP_ROOT/layer-map.yml"
    printf -- '- id: [unterminated\n' >"$TMP_ROOT/layer-corrupt.yml"

    for bad in comment blank scalar map corrupt; do
        rc=0
        out=$(run_layer "$TMP_ROOT/layer-$bad.yml") || rc=$?
        check "a $bad layer is refused" test "$rc" != "0"
        check "the $bad layer refusal names the file" \
            test -n "$(printf '%s' "$out" | awk -v f="layer-$bad.yml" 'index($0, f)')"
    done

    # The messages have to be different, or the refusal is not actionable.
    check 'an unparseable layer is named as invalid YAML' \
        test -n "$(run_layer "$TMP_ROOT/layer-corrupt.yml" | awk '/is not valid YAML/')"
    check 'a null layer is named as having no entries' \
        test -n "$(run_layer "$TMP_ROOT/layer-comment.yml" | awk '/got no entries/')"
    check 'a map layer is named as a map, not as empty' \
        test -n "$(run_layer "$TMP_ROOT/layer-map.yml" | awk '/got a map/')"
    check 'a scalar layer is named as a scalar' \
        test -n "$(run_layer "$TMP_ROOT/layer-scalar.yml" | awk '/got a string/')"
    check 'a refused layer is told how to write an empty one' \
        test -n "$(run_layer "$TMP_ROOT/layer-comment.yml" | awk '/must be the literal \[\]/')"
else
    ok 'patch-layer parse cases skipped (no installed runtime to borrow js-yaml from)'
fi

# ---------------------------------------------------------------------------
# 12c. The copier rewrites nothing it does not have to, and refuses the rest
# ---------------------------------------------------------------------------
# patchReload is live: DSH recomposes a RUNNING tree when one of these files
# changes. An install that rewrites an identical file therefore restarts
# composition on every single run, for nothing.
run_copy >/dev/null 2>&1 || true
copied_home=$copy_home/.dsh/cordis.patch.yml
# A fixed old timestamp on the files AND on a reference, so "not rewritten" is
# `find -newer` against that reference - no clock tick to wait for, and no
# parsing of `ls` output.
mtime_ref=$TMP_ROOT/mtime-ref
: >"$mtime_ref"
touch -t 202001010000 "$copied_home" "$copied_preset/agent.cordis.yml" "$mtime_ref"
rc=0
run_copy >/dev/null 2>&1 || rc=$?
equals 'a no-op copy run still succeeds' "$rc" "0"
check 'an unchanged patch layer is not rewritten' \
    test -z "$(find "$copied_home" -newer "$mtime_ref")"
check 'an unchanged preset file is not rewritten' \
    test -z "$(find "$copied_preset/agent.cordis.yml" -newer "$mtime_ref")"

# A changed copy IS rewritten - "never rewrites" would be the opposite bug.
printf '\n# hand edit\n' >>"$copied_home"
run_copy >/dev/null 2>&1 || true
check 'a drifted patch layer is replaced by the tracked one' \
    cmp -s "$PATCH" "$copied_home"

# `mv` into a directory succeeds and leaves the managed file uninstalled, so a
# non-regular destination is refused outright rather than half-handled.
rm -f "$copied_home"
mkdir -p "$copied_home"
rc=0
out=$(run_copy 2>&1) || rc=$?
check 'a directory where a patch layer belongs fails the install' test "$rc" != "0"
check 'the non-regular destination is named and the fix given' \
    test -n "$(printf '%s' "$out" | awk '/is not a regular file - remove it and re-run/')"
check 'nothing was moved inside the directory' \
    test -z "$(ls -A "$copied_home")"
rmdir "$copied_home"
run_copy >/dev/null 2>&1 || true
check 'the install recovers once the directory is gone' cmp -s "$PATCH" "$copied_home"

# The temp file is same-directory (so mv is a rename) and never survives.
check 'the copier leaves no temp file behind' \
    test -z "$(find "$copy_home/.dsh" -name '.dsh-install.*' -print 2>/dev/null | head -n 1)"
check 'the temp file is a sibling, not a nested path' \
    grep -q 'tmp="${2%/\*}/.dsh-install.\$\$.tmp"' "$CONF"

# ---------------------------------------------------------------------------
# 12d. The probe refuses a live preset that is a symlink, before reading it
# ---------------------------------------------------------------------------
# A symlink into this repo compares byte-equal to the tracked preset, so the
# content check cannot see it. It is still wrong: DSH reloads these files live,
# so the link would publish a half-finished repo edit into a running harness.
if [ -n "$real_node" ]; then
    sym_home=$TMP_ROOT/symhome
    mkdir -p "$sym_home/.agent-presets/dotfiles"
    live=$sym_home/.agent-presets/dotfiles/agent.cordis.yml

    ln -s "$PRESET" "$live"
    rc=0
    out=$(DSH_HOME=$sym_home "$real_node" "$DIR/mcp-status.mjs" --timeout-ms 1000 2>&1) || rc=$?
    equals 'a symlinked live preset refuses to report' "$rc" "2"
    check 'the symlinked live preset is named as a symlink, not as drift' \
        test -n "$(printf '%s' "$out" | awk '/is a symlink, not a managed copy/')"
    check 'the refusal says where the link actually points' \
        test -n "$(printf '%s' "$out" | awk -v p="$PRESET" 'index($0, p)')"
    check 'a symlinked live preset is never reported as matching' \
        test -z "$(printf '%s' "$out" | awk '/OK [0-9]+ tool/')"

    rm -f "$live"
    mkdir -p "$live"
    rc=0
    out=$(DSH_HOME=$sym_home "$real_node" "$DIR/mcp-status.mjs" --timeout-ms 1000 2>&1) || rc=$?
    equals 'a directory where the live preset belongs refuses to report' "$rc" "2"
    check 'the non-regular live preset is named' \
        test -n "$(printf '%s' "$out" | awk '/is not a regular file/')"
    rmdir "$live"

    rc=0
    out=$(DSH_HOME=$sym_home "$real_node" "$DIR/mcp-status.mjs" --timeout-ms 1000 2>&1) || rc=$?
    equals 'a missing live preset still refuses to report' "$rc" "2"
    check 'the missing live preset asks for a managed copy, not a link' \
        test -n "$(printf '%s' "$out" | awk '/run .\/install to place the managed copy/')"
else
    ok 'live-preset shape cases skipped (node not installed)'
fi

# ---------------------------------------------------------------------------
# 13. The probe is bounded by ONE deadline, not one per server
# ---------------------------------------------------------------------------
# Four rows probed sequentially against their own timers can take four
# timeouts. These rows never speak MCP at all, so each would hang until its
# budget expired; the whole run must still finish within one budget.
if command -v node >/dev/null 2>&1; then
    probe_root=$TMP_ROOT/probe-repo
    mkdir -p "$probe_root/presets/dotfiles"
    cp "$PROBE" "$probe_root/mcp-status.mjs"
    silent=$TMP_ROOT/silent-server.sh
    printf '#!/bin/sh\n# Speaks no MCP: reads forever and answers nothing.\ncat >/dev/null\n' >"$silent"
    chmod +x "$silent"
    {
        for n in 1 2 3 4; do
            printf -- "- id: mcp-silent%s\n" "$n"
            printf "  name: '@deepseek-ai/dsh-mcp-client'\n"
            printf '  config:\n    transport: stdio\n    serverName: silent%s\n' "$n"
            printf '    command: %s\n    args: []\n    env: {}\n' "$silent"
            printf '    failOnStartupError: false\n'
        done
    } >"$probe_root/presets/dotfiles/agent.cordis.yml"
    probe_home=$TMP_ROOT/probe-deadline-home
    mkdir -p "$probe_home/.agent-presets/dotfiles"
    cp "$probe_root/presets/dotfiles/agent.cordis.yml" \
        "$probe_home/.agent-presets/dotfiles/agent.cordis.yml"

    started=$(date +%s)
    rc=0
    out=$(DSH_HOME=$probe_home node "$probe_root/mcp-status.mjs" --timeout-ms 3000 2>&1) || rc=$?
    elapsed=$(( $(date +%s) - started ))
    equals 'four unreachable rows report as degraded' "$rc" "1"
    equals 'every row is reported' \
        "$(printf '%s\n' "$out" | grep -c 'DEGRADED' || true)" "4"
    # Four sequential 3s timers would be ~12s. One shared deadline is ~3s; 8s
    # leaves room for a slow machine without admitting a second timeout.
    check 'the whole run is bounded by one timeout' test "$elapsed" -lt 8
    # Positional results, so the report does not depend on who answers first.
    equals 'the report keeps preset order' \
        "$(printf '%s\n' "$out" | awk '{ print $2 }' | tr '\n' ' ')" \
        "silent1 silent2 silent3 silent4 "
else
    ok 'probe deadline case skipped (node not installed)'
fi

# ---------------------------------------------------------------------------
# 14. What the daily MCP count does and does not prove
# ---------------------------------------------------------------------------
# Measured: chrome-devtools-mcp@1.8.0 pointed at a dead port still completes
# initialize and tools/list and advertises all 29 tools. So Chrome DevTools
# stays in the core set — its server starts reliably — but the count proves the
# server and its tool catalog, never that a browser is attached. Saying so in
# the README is the only thing that keeps the daily line from being read as a
# browser health check.
check 'the README says the count does not prove browser attachability' \
    grep -q 'not that a browser is attached' "$DIR/README.md"
check 'the README keeps Chrome DevTools in the core set' \
    grep -q 'Serena, Context7 and Chrome DevTools' "$DIR/README.md"
# No DSH-owned startup timeout exists, so startup and discovery are bounded by
# the MCP SDK default alone. Anyone tuning this needs to know there is no knob.
check 'the preset records the startup timeout that actually applies' \
    grep -q 'DEFAULT_REQUEST_TIMEOUT_MSEC' "$PRESET"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
