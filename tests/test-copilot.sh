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

# The attribution block must treat a copilot-shim symlink as absent: the
# existing message, no `copilot config`, no installed marker, and no exec.
python3 - "$ROOT/install.conf.yaml" "$tmp" <<'PY'
import os, pathlib, subprocess, sys
import yaml
config, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
blocks = [x['command'] for group in yaml.safe_load(config.read_text()) if 'shell' in group
          for x in group['shell'] if isinstance(x, dict) and 'command' in x]
chosen = [x for x in blocks if 'includeCoAuthoredBy' in x]
assert len(chosen) == 1, chosen
block = chosen[0]
for product in ('code', 'code-insiders'):
    home = root / f'stub-{product}'
    shim = home / 'opt/share' / product / 'bin/copilot-shim'
    bindir = home / '.local/bin'
    shim.mkdir(parents=True)
    bindir.mkdir(parents=True)
    stub = shim / 'copilot'
    stub.write_text('#!/bin/sh\nprintf executed\\n >>"$HOME/stub-executed"\nexit 0\n')
    stub.chmod(0o700)
    link = bindir / 'copilot'
    link.symlink_to(f'../../opt/share/{product}/bin/copilot-shim/copilot')
    env = dict(os.environ, HOME=str(home), PATH=str(bindir)+':'+os.environ['PATH'])
    proc = subprocess.run(['/bin/sh','-ec',block], env=env, cwd=config.parent, text=True, capture_output=True)
    assert proc.returncode == 0, (proc.returncode, proc.stdout, proc.stderr)
    assert 'Copilot CLI absent; native attribution setting skipped' in proc.stdout, proc.stdout
    assert 'includeCoAuthoredBy' not in proc.stdout + proc.stderr
    assert not (home/'.local/state/harness-update/copilot-installed').exists()
    assert not (home/'stub-executed').exists(), 'stub was executed'
print('PASS: VS Code copilot-shim is absent during install')
PY

# command -v is relative when the PATH entry is. A real CLI must still run.
# A copilot-shim reached through that relative entry must not.
python3 - "$ROOT/install.conf.yaml" "$tmp" <<'PY'
import os, pathlib, subprocess, sys
import yaml
config, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
blocks = [x['command'] for group in yaml.safe_load(config.read_text()) if 'shell' in group
          for x in group['shell'] if isinstance(x, dict) and 'command' in x]
block = [x for x in blocks if 'includeCoAuthoredBy' in x][0]
work = root / 'relative-path'
rel = work / 'relative-bin'
rel.mkdir(parents=True)
real = rel / 'copilot'
real.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$HOME/calls"\n')
real.chmod(0o700)
home = work / 'home-real'
home.mkdir()
env = dict(os.environ, HOME=str(home), PATH='relative-bin:/usr/bin:/bin')
proc = subprocess.run(['/bin/sh','-ec',block], env=env, cwd=work, text=True, capture_output=True)
assert proc.returncode == 0, (proc.returncode, proc.stdout, proc.stderr)
assert (home/'calls').read_text() == 'config includeCoAuthoredBy false\n', (home/'calls').read_text() if (home/'calls').exists() else proc.stdout
assert (home/'.local/state/harness-update/copilot-installed').is_file()
assert 'absent' not in proc.stdout

shim = work / 'opt/share/code/bin/copilot-shim'
shim.mkdir(parents=True)
stub = shim / 'copilot'
stub.write_text('#!/bin/sh\nprintf executed\\n >>"$HOME/stub-executed"\nexit 0\n')
stub.chmod(0o700)
real.unlink()
(rel/'copilot').symlink_to('../opt/share/code/bin/copilot-shim/copilot')
home = work / 'home-stub'
home.mkdir()
env = dict(os.environ, HOME=str(home), PATH='relative-bin:/usr/bin:/bin')
proc = subprocess.run(['/bin/sh','-ec',block], env=env, cwd=work, text=True, capture_output=True)
assert proc.returncode == 0, (proc.returncode, proc.stdout, proc.stderr)
assert 'Copilot CLI absent; native attribution setting skipped' in proc.stdout, proc.stdout
assert not (home/'calls').exists()
assert not (home/'stub-executed').exists()
assert not (home/'.local/state/harness-update/copilot-installed').exists()
print('PASS: relative PATH Copilot CLI runs; relative PATH shim is absent')
PY

# /bin/sh PATH=:/usr/bin:/bin prints a bare name for an executable in cwd.
# That must run config and write the marker, as before shim detection.
# A canonical copilot-shim path (no symlink) stays absent and is not executed.
python3 - "$ROOT/install.conf.yaml" "$tmp" <<'PY'
import os, pathlib, subprocess, sys
import yaml
config, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
blocks = [x['command'] for group in yaml.safe_load(config.read_text()) if 'shell' in group
          for x in group['shell'] if isinstance(x, dict) and 'command' in x]
block = [x for x in blocks if 'includeCoAuthoredBy' in x][0]
work = root / 'empty-path'
work.mkdir()
exe = work / 'copilot'
exe.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$HOME/calls"\n')
exe.chmod(0o700)
home = work / 'home'
home.mkdir()
env = dict(os.environ, HOME=str(home), PATH=':/usr/bin:/bin')
proc = subprocess.run(['/bin/sh','-c', block], env=env, cwd=work, text=True, capture_output=True)
assert proc.returncode == 0, (proc.returncode, proc.stdout, proc.stderr)
assert (home/'calls').read_text() == 'config includeCoAuthoredBy false\n'
assert (home/'.local/state/harness-update/copilot-installed').is_file()
assert 'absent' not in proc.stdout

canon = root / 'canon-shim' / 'opt/share/code/bin/copilot-shim'
canon.mkdir(parents=True)
stub = canon / 'copilot'
stub.write_text('#!/bin/sh\nprintf executed\\n >>"$HOME/stub-executed"\nexit 0\n')
stub.chmod(0o700)
home = root / 'canon-shim' / 'home'
home.mkdir()
env = dict(os.environ, HOME=str(home), PATH=str(canon)+':/usr/bin:/bin')
proc = subprocess.run(['/bin/sh','-c', block], env=env, cwd=root/'canon-shim', text=True, capture_output=True)
assert proc.returncode == 0, (proc.returncode, proc.stdout, proc.stderr)
assert 'Copilot CLI absent; native attribution setting skipped' in proc.stdout, proc.stdout
assert not (home/'stub-executed').exists()
assert not (home/'.local/state/harness-update/copilot-installed').exists()
print('PASS: empty PATH component runs the cwd CLI; canonical shim is absent')
PY
