#!/bin/sh
# Frozen independent acceptance checks: batch-1 Claude status line.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
exec python3 - "$ROOT/claude/statusline.sh" <<'PY'
import copy
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

with tempfile.TemporaryDirectory(prefix="test-claude-statusline.") as temporary:
    root = Path(temporary)
    bindir = root / "bin"
    bindir.mkdir()
    cache = root / "cache"
    cache.mkdir()
    repo = root / "Rust repo with spaces"
    repo.mkdir()
    plain = root / "not a repository"
    plain.mkdir()
    for name, executable in (("git", real_git), ("jq", real_jq)):
        wrapper = bindir / name
        wrapper.write_text('#!/bin/sh\nprintf "' + name + '\\n" >>"$CALL_LOG"\nexec ' + shlex.quote(executable) + ' "$@"\n')
        wrapper.chmod(0o755)
    ae = bindir / "ae"
    ae.write_text('#!/bin/sh\n[ "$1" = _quota-feed ] || exit 9\ncat >"$QUOTA_LOG"\n')
    ae.chmod(0o755)

    def git(*args):
        return subprocess.check_output([real_git, "-C", str(repo), *args], text=True, stderr=subprocess.PIPE).strip()

    git("init", "-q")
    # commit-tree makes one fixture commit without hooks, signing or identity changes.
    git("symbolic-ref", "HEAD", "refs/heads/acceptance")
    tree = subprocess.check_output([real_git, "-C", str(repo), "mktree"], input="", text=True).strip()
    identity = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid", GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    commit = subprocess.check_output([real_git, "-C", str(repo), "commit-tree", tree], input="fixture\n", text=True, env=identity).strip()
    git("update-ref", "refs/heads/acceptance", commit)

    def render(label, payload, expected, git_count=None):
        global passed
        call_log = root / (str(passed) + ".calls")
        quota_log = root / (str(passed) + ".quota")
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"], TMPDIR=str(cache), CALL_LOG=str(call_log), QUOTA_LOG=str(quota_log))
        encoded = json.dumps(payload)
        result = subprocess.run(["/bin/bash", str(script)], input=encoded, text=True, capture_output=True, env=env, cwd=str(plain), timeout=15)
        assert result.returncode == 0, (label, "exit", result.returncode, result.stderr)
        assert result.stdout == expected, (label, "display", repr(result.stdout), repr(expected))
        calls = call_log.read_text().splitlines() if call_log.exists() else []
        assert calls.count("jq") == 1, (label, "jq process count", calls)
        assert calls.count("git") <= 1, (label, "git process count", calls)
        if git_count is not None:
            assert calls.count("git") == git_count, (label, "cache git count", calls)
        deadline = time.monotonic() + 2
        while (not quota_log.exists() or quota_log.read_text() != encoded) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert quota_log.exists() and quota_log.read_text() == encoded, (label, "ae quota payload missing or changed")
        passed += 1
        print("PASS:", label)

    def expected(directory, branch=None, effort="high", context="42", cost="12.35", prompt_cache="warm", five="23", seven="87", model="Model X"):
        value = "🧠 " + model
        if effort is not None:
            value += " (" + effort + ")"
        value += "  📁 " + directory
        if branch is not None:
            value += "  🌿 " + branch
        for rendered in (("ctx " + context + "%") if context is not None else None,
                         ("$" + cost) if cost is not None else None,
                         ("cache " + prompt_cache) if prompt_cache is not None else None,
                         ("5h " + five + "%") if five is not None else None,
                         ("7d " + seven + "%") if seven is not None else None):
            if rendered is not None:
                value += "  " + rendered
        return value

    payload = {"model": {"display_name": "Model X"}, "effort": {"level": "high"}, "workspace": {"current_dir": str(plain)}, "context_window": {"used_percentage": 42.9}, "cost": {"total_cost_usd": 12.345}, "prompt_cache": {"warm": True}, "rate_limits": {"five_hour": {"used_percentage": 23.9}, "seven_day": {"used_percentage": 87.6}, "spend_limit": {"used_percentage": 99}}}
    render("all fields; floor percentages; two-decimal cost; non-git cwd", payload, expected(plain.name))
    fields = (("model", "display_name", "model", "?"), ("effort", "level", "effort", None), ("context_window", "used_percentage", "context", None), ("cost", "total_cost_usd", "cost", None), ("prompt_cache", "warm", "prompt_cache", None), ("rate_limits", "five_hour", "five", None), ("rate_limits", "seven_day", "seven", None))
    for parent, key, argument, absent in fields:
        for mode in ("absent", "null"):
            item = copy.deepcopy(payload)
            if mode == "absent":
                del item[parent][key]
            else:
                item[parent][key] = None
            render(parent + "." + key + " " + mode, item, expected(plain.name, **{argument: absent}))
    item = copy.deepcopy(payload)
    item["prompt_cache"]["warm"] = False
    render("cache cold is not omitted", item, expected(plain.name, prompt_cache="cold"))
    item = copy.deepcopy(payload)
    item["context_window"]["used_percentage"] = 0
    item["cost"]["total_cost_usd"] = 0
    item["rate_limits"]["five_hour"]["used_percentage"] = 0
    item["rate_limits"]["seven_day"]["used_percentage"] = 0
    render("numeric zero remains visible", item, expected(plain.name, context="0", cost="0.00", five="0", seven="0"))
    render("all optional fields missing and cwd missing", {}, "🧠 ?  📁 ")
    render("all top-level fields null", {key: None for key in payload}, "🧠 ?  📁 ")
    item = copy.deepcopy(payload)
    del item["workspace"]
    item["cwd"] = str(plain)
    render("cwd fallback", item, expected(plain.name))
    item["workspace"] = {"current_dir": None}
    render("null workspace cwd uses fallback", item, expected(plain.name))
    item["workspace"] = {"current_dir": str(repo)}
    render("cold git cache; workspace beats cwd; spaces preserved", item, expected(repo.name, "acceptance"), 1)
    render("warm per-cwd git cache", item, expected(repo.name, "acceptance"), 0)
    git("symbolic-ref", "HEAD", "refs/heads/next-branch")
    git("update-ref", "refs/heads/next-branch", commit)
    time.sleep(5.2)
    render("expired cache refreshes branch", item, expected(repo.name, "next-branch"), 1)
    # Files in TMPDIR belong only to the status-line branch cache.
    files = [path for path in cache.rglob("*") if path.is_file()]
    assert files, "branch cache must use a file under TMPDIR"
    for path in files:
        path.chmod(0)
    try:
        render("unreadable cache falls back to one git call", item, expected(repo.name, "next-branch"), 1)
    finally:
        for path in cache.rglob("*"):
            if path.is_file():
                path.chmod(0o600)
    git("update-ref", "--no-deref", "HEAD", commit)
    time.sleep(5.2)
    render("detached HEAD after cache expiry", item, expected(repo.name, "HEAD"), 1)
    render("non-git cwd never inherits another cwd branch", payload, expected(plain.name))

print(str(passed) + " passed, 0 failed")
PY
