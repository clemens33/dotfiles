#!/bin/sh
# Hardening checks for the status line's branch cache (additive to the frozen
# tests/test-claude-statusline.sh, which stays byte-identical).
#
# Requirement: a damaged, hostile or foreign cache file never breaks the footer,
# never costs more than one git process, and a symlink or file planted at the
# predictable temp name in a shared TMPDIR is never written through. Expected
# outputs are written out literally. `ae` is replaced by a stub, so no payload
# reaches the real quota cache. Everything runs in a temporary directory.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
exec python3 -I - "$ROOT/claude/statusline.sh" <<'PY'
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

script = Path(sys.argv[1]).resolve()
real_git = shutil.which("git")
real_jq = shutil.which("jq")
assert real_git and real_jq, "git and jq are required"
passed = 0

with tempfile.TemporaryDirectory(prefix="test-claude-statusline-cache.") as temporary:
    root = Path(temporary)
    bindir = root / "bin"
    bindir.mkdir()
    cache = root / "cache"
    cache.mkdir()
    repo = root / "repo"
    repo.mkdir()
    sentinel = root / "sentinel.txt"
    for name, executable in (("git", real_git), ("jq", real_jq)):
        wrapper = bindir / name
        body = '#!/bin/sh\nprintf "' + name + '\\n" >>"$CALL_LOG"\n'
        if name == "git":
            # Plant a symlink at the predictable temp name of the status-line process
            # (git runs in a command substitution: PPID is that subshell, whose parent
            # is the status-line shell).
            body += ('if [ -n "${PLANT_NAME:-}" ]; then\n'
                     '  main=$(ps -o ppid= -p "$PPID" | tr -d " ")\n'
                     '  ln -s "$PLANT_TARGET" "$PLANT_DIR/$PLANT_NAME.$main"\n'
                     'fi\n')
        wrapper.write_text(body + 'exec ' + shlex.quote(executable) + ' "$@"\n')
        wrapper.chmod(0o755)
    ae = bindir / "ae"
    ae.write_text('#!/bin/sh\ncat >/dev/null\n')
    ae.chmod(0o755)

    def git(*args):
        return subprocess.check_output([real_git, "-C", str(repo), *args], text=True, stderr=subprocess.PIPE).strip()

    git("init", "-q")
    git("symbolic-ref", "HEAD", "refs/heads/hardening")
    tree = subprocess.check_output([real_git, "-C", str(repo), "mktree"], input="", text=True).strip()
    identity = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                    GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    commit = subprocess.check_output([real_git, "-C", str(repo), "commit-tree", tree], input="fixture\n", text=True, env=identity).strip()
    git("update-ref", "refs/heads/hardening", commit)

    payload = json.dumps({"model": {"display_name": "M"}, "workspace": {"current_dir": str(repo)}})
    want = "🧠 M  📁 repo  🌿 hardening"

    def render(label, expected_git, extra_env=None):
        global passed
        call_log = root / (str(passed) + ".calls")
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"], TMPDIR=str(cache), CALL_LOG=str(call_log))
        env.update(extra_env or {})
        result = subprocess.run(["/bin/bash", str(script)], input=payload, text=True, capture_output=True, env=env, cwd=str(root), timeout=15)
        assert result.returncode == 0, (label, "exit", result.returncode, result.stderr)
        assert result.stdout == want, (label, "display", repr(result.stdout), repr(want))
        calls = call_log.read_text().splitlines() if call_log.exists() else []
        assert calls.count("jq") == 1, (label, "jq count", calls)
        assert calls.count("git") == expected_git, (label, "git count", calls)
        passed += 1
        print("PASS:", label)

    def cache_file():
        files = [p for p in cache.iterdir() if p.name.startswith("claude-statusline-") and "." not in p.name[len("claude-statusline-"):]]
        assert len(files) == 1, files
        return files[0]

    def reset():
        for p in cache.iterdir():
            p.unlink()

    render("cold render creates the cache", 1)
    target = cache_file()
    name = target.name
    render("fresh cache hits", 0)

    def damaged(label, content):
        target.write_text(content)
        render(label + ": one git call, correct footer", 1)
        render(label + ": cache repaired, next render hits", 0)

    now = int(time.time())
    damaged("leading-zero epoch (octal-looking)", "00000000008\n" + str(repo) + "\nbogus\n")
    damaged("all-zero epoch", "00000000000\n" + str(repo) + "\nbogus\n")
    damaged("leading-zero epoch with an 8 or 9 in the 11 digits", "09999999999\n" + str(repo) + "\nbogus\n")
    damaged("empty file", "")
    damaged("two lines only", str(now) + "\n" + str(repo) + "\n")
    damaged("non-numeric epoch", "abc\n" + str(repo) + "\nbogus\n")
    damaged("epoch with a sign", "-5\n" + str(repo) + "\nbogus\n")
    damaged("epoch too long for the field", "1" * 25 + "\n" + str(repo) + "\nbogus\n")
    damaged("epoch far in the future (negative age)", str(now + 100000) + "\n" + str(repo) + "\nbogus\n")
    damaged("fresh epoch but a different cwd line (hash collision guard)", str(now) + "\n/somewhere/else\nbogus\n")

    # A symlink as the cache file itself is not read, even when its target looks valid.
    elsewhere = root / "elsewhere.txt"
    elsewhere.write_text(str(now) + "\n" + str(repo) + "\nbogus\n")
    target.unlink()
    target.symlink_to(elsewhere)
    render("cache file is a symlink: ignored, one git call", 1)
    assert elsewhere.read_text() == str(now) + "\n" + str(repo) + "\nbogus\n", "symlink target was modified"
    reset()

    # A symlink planted at the predictable temp name is never written through.
    sentinel.write_text("SENTINEL\n")
    render("cold render before planting", 1)
    target = cache_file()
    target.unlink()
    render("planted symlink to a file: footer survives, one git call", 1,
           {"PLANT_NAME": name, "PLANT_TARGET": str(sentinel), "PLANT_DIR": str(cache)})
    assert sentinel.read_text() == "SENTINEL\n", "the status line wrote through a planted symlink"
    reset()
    dangling = root / "never-created.txt"
    render("planted dangling symlink: footer survives, one git call", 1,
           {"PLANT_NAME": name, "PLANT_TARGET": str(dangling), "PLANT_DIR": str(cache)})
    assert not dangling.exists(), "the status line created a file through a planted dangling symlink"

print(str(passed) + " passed, 0 failed")
PY
