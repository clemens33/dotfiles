#!/usr/bin/env bash
# Offline native MCP schema and installer contracts. Never use the real HOME.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-copilot.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
merge="$ROOT/scripts/copilot-mcp-merge.sh"
target="$tmp/mcp-config.json"
source="$tmp/servers.json"
printf '%s\n' '{"context7":{"type":"stdio","command":"npx","args":["-y","context7"],"env":{}}}' >"$source"
printf '%s\n' '{"preference":7,"mcpServers":{"local":{"custom":true},"serena":{"command":"obsolete"}}}' >"$target"
"$merge" "$target" "$source"
jq -e '.preference == 7 and .mcpServers.local.custom and (.mcpServers.serena == null) and .mcpServers.context7 == {type:"local",command:"npx",args:["-y","context7"],env:{},tools:["*"]}' "$target" >/dev/null
cp "$target" "$tmp/before"
"$merge" "$target" "$source"
cmp "$target" "$tmp/before"
test -n "$(find "$target" -perm 600 -print)"

unchanged_failure() {
    cp "$target" "$tmp/before"
    if "$merge" "$target" "$source" >"$tmp/out" 2>"$tmp/err"; then
        echo 'FAIL: malformed/unsupported schema accepted' >&2; exit 1
    fi
    cmp "$target" "$tmp/before"
    test -z "$(find "$tmp" -name '.copilot-mcp.*' -print)"
}
for invalid in '[]' '{"mcpServers":{}}' '{"unowned":{"command":"bad"}}' \
    '{"context7":{"type":"http","url":"https://example.invalid"}}' \
    '{"context7":{"command":"npx","args":"wrong"}}' \
    '{"context7":{"command":"npx","args":false}}' \
    '{"context7":{"command":"npx","env":null}}' \
    '{"context7":{"command":"npx","type":false}}' \
    '{"context7":{"command":"npx","env":{"KEY":42}}}' \
    '{"context7":{"command":"npx","invented":true}}'; do
    printf '%s\n' "$invalid" >"$source"
    unchanged_failure
done
printf '{}\n{}\n' >"$source"
unchanged_failure
printf '{}\n' >"$source"
cp "$target" "$tmp/valid-target"
printf '{}\n{}\n' >"$target"
unchanged_failure
cp "$tmp/valid-target" "$target"
"$merge" "$target" "$source"
jq -e '.mcpServers | has("context7") | not' "$target" >/dev/null
cp "$target" "$tmp/referent"
ln -s "$tmp/referent" "$tmp/link"
if "$merge" "$tmp/link" "$source" >/dev/null 2>&1; then
    echo 'FAIL: symlink target accepted' >&2; exit 1
fi
cmp "$tmp/referent" "$target"

# Run the actual installer Copilot blocks with a fake native CLI, preserving
# an opaque authentication file and another preference under an overridden home.
python3 - "$ROOT/install.conf.yaml" "$tmp" <<'PY'
import json, os, pathlib, subprocess, sys
import yaml
config, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
home, native = root / 'home', root / 'native home'
(home / '.local/bin').mkdir(parents=True)
native.mkdir()
(native / 'config.json').write_text('// opaque auth/state\n')
(native / 'settings.json').write_text('{"theme":"keep"}')
fake = home / '.local/bin/copilot'
fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
assert sys.argv[1:] == ['config','includeCoAuthoredBy','false'], sys.argv
p=pathlib.Path(os.environ['COPILOT_HOME'])/'settings.json'
d=json.loads(p.read_text()); d['includeCoAuthoredBy']=False
p.write_text(json.dumps(d))
''')
fake.chmod(0o700)
env = dict(os.environ, HOME=str(home), COPILOT_HOME=str(native), PATH=str(fake.parent)+':'+os.environ['PATH'])
blocks = [x['command'] for group in yaml.safe_load(config.read_text()) if 'shell' in group
          for x in group['shell'] if isinstance(x, dict) and 'command' in x]
chosen = [x for x in blocks if 'copilot-mcp-merge.sh' in x or 'includeCoAuthoredBy' in x]
assert len(chosen) == 2, chosen
for block in chosen:
    subprocess.run(['/bin/sh','-ec',block],env=env,cwd=config.parent,check=True)
assert (native/'config.json').read_text() == '// opaque auth/state\n'
assert json.loads((native/'settings.json').read_text()) == {'theme':'keep','includeCoAuthoredBy':False}
assert (home/'.local/state/harness-update/copilot-installed').is_file()
assert (native/'mcp-config.json').is_file()
assert not (home/'.copilot').exists()
print('PASS: native adapter and isolated installer contracts')
PY
