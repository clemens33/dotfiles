#!/usr/bin/env python3
"""eval-skills.py - small skill routing / task-outcome evaluation runner.

Compares the skill catalog at committed HEAD (public repo HEAD + overlay HEAD)
against the current worktree WITHOUT modifying either tree, drives one model
command per case (argv only, no shell), verifies deterministically, and records
run metadata under .local/ by default.

Subcommands
  catalog       print the catalog text a side would show (--side head|worktree)
  check         validate fixtures against both catalogs (+ PyYAML cross-check when importable)
  measure       catalog budget numbers per side; --codex-native adds the live Codex block
  run           evaluate one side, one suite, through a model command:  ... -- <argv...>
  compare       diff two run directories (baseline vs candidate)
  native-check  drive the real harness with the raw prompt and observe skill tool calls

What this measures and what it does not
  `run` is a CATALOG-PROMPT SIMULATION: the model sees the catalog text inside a
  prompt and answers with a JSON selection. It is NOT the harness's native
  routing (system-prompt skill listing, tool descriptions, harness heuristics).
  Same model + same prompt on both sides makes it a fair A/B of the catalog
  text, nothing more. `native-check` observes the installed (worktree) skills
  through the real harness and is direction-only evidence. The fake model in
  evals/skills/fake_model.py proves the pipeline, never model quality.

Python 3 stdlib only. Runs on /usr/bin/python3 (3.9) and newer.
"""
import argparse
import ast
import io
import shutil
import tarfile
import tempfile
import datetime as dt
import fnmatch
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

RUNNER_VERSION = "1.0"
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
OVERLAY_DIR = REPO_ROOT / "dotfiles-mic"
FIXTURE_DIR = REPO_ROOT / "evals" / "skills"
LOCAL_ROOT = REPO_ROOT / ".local"
DEFAULT_OUT = LOCAL_ROOT / "eval-skills"

SKILL_MD_RE = re.compile(r"^skills/([^/]+)/SKILL\.md$")
AGENT_MD_RE = re.compile(r"^agents/([^/]+)\.md$")
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):(?:[ \t]+(.*))?$")
CATEGORY_RE = re.compile(r"^\s+category:\s*['\"]?([A-Za-z-]+)", re.M)
FENCE_RE = re.compile(r"```([A-Za-z0-9_+.-]*)[^\n]*\n(.*?)```", re.S)
PROVIDER_BY_TOOL = {
    "claude": "Anthropic", "codex": "OpenAI", "grok": "xAI", "agy": "Google",
    "opencode": "declare-upstream", "fake_model.py": "fake",
}


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------
def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def utc_stamp():
    # microseconds keep back-to-back runs (self-test, scripted pilots) from colliding
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")


def utc_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def die(msg, code=1):
    sys.stderr.write("eval-skills: %s\n" % msg)
    sys.exit(code)


def git_out(args, cwd, check=True):
    r = subprocess.run(["git"] + list(args), cwd=str(cwd), capture_output=True)
    if check and r.returncode != 0:
        raise RuntimeError("git %s failed in %s: %s" % (" ".join(args), cwd, r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout.decode("utf-8", "replace")


def git_rev(ref, cwd):
    try:
        return git_out(["rev-parse", "--verify", ref + "^{commit}"], cwd).strip() or None
    except RuntimeError:
        return None


def norm_ws(text):
    return " ".join((text or "").split())


def resolve_out(out, allow_outside):
    p = Path(out).resolve()
    local = LOCAL_ROOT.resolve()
    if not allow_outside and p != local and local not in p.parents:
        die("refusing to write results outside %s (got %s); pass --allow-outside-local to override" % (local, p))
    return p


# --------------------------------------------------------------------------
# frontmatter (stdlib, tolerant: folded/literal/quoted/plain scalars)
# --------------------------------------------------------------------------
def split_frontmatter(text):
    if not text.startswith("---\n"):
        return None, text
    parts = text.split("\n---\n", 1)
    if len(parts) != 2:
        return None, text
    return parts[0][4:], parts[1]


def _unquote(joined):
    q = joined[0]
    out = []
    i = 1
    n = len(joined)
    while i < n:
        ch = joined[i]
        if q == "'":
            if ch == "'":
                if i + 1 < n and joined[i + 1] == "'":
                    out.append("'")
                    i += 2
                    continue
                break
            out.append(ch)
            i += 1
        else:
            if ch == "\\" and i + 1 < n:
                nxt = joined[i + 1]
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
                i += 2
                continue
            if ch == '"':
                break
            out.append(ch)
            i += 1
    return "".join(out)


def parse_scalar(lines, i, first_value):
    v = (first_value or "").strip()
    cont = []
    j = i + 1
    while j < len(lines):
        ln = lines[j]
        if ln.strip() == "":
            cont.append("")
            j += 1
            continue
        if not ln[0].isspace():
            break
        cont.append(ln.strip())
        j += 1
    while cont and cont[-1] == "":
        cont.pop()
    if v[:1] in (">", "|"):
        if v[0] == ">":
            paras, para = [], []
            for c in cont:
                if c == "":
                    if para:
                        paras.append(" ".join(para))
                        para = []
                    paras.append("")
                else:
                    para.append(c)
            if para:
                paras.append(" ".join(para))
            return "\n".join(paras).strip(), j
        return "\n".join(cont).strip(), j
    if v[:1] in ('"', "'"):
        return _unquote(" ".join([v] + [c for c in cont if c != ""])), j
    return " ".join([v] + [c for c in cont if c != ""]).strip(), j


def parse_frontmatter(fm_text):
    """Top-level scalar keys only (name, description, ...). Good enough for catalogs."""
    lines = fm_text.splitlines()
    out = {}
    i = 0
    while i < len(lines):
        m = KEY_RE.match(lines[i])
        if not m:
            i += 1
            continue
        key, first = m.group(1), m.group(2)
        if first is None or first.strip() == "":
            # nested mapping (metadata:) or empty; skip its block
            j = i + 1
            while j < len(lines) and (lines[j].strip() == "" or lines[j][0].isspace()):
                j += 1
            out[key] = ""
            i = j
            continue
        value, i = parse_scalar(lines, i, first)
        out[key] = value
    cat = CATEGORY_RE.search(fm_text)
    out["_category"] = cat.group(1) if cat else None
    return out


# --------------------------------------------------------------------------
# catalog
# --------------------------------------------------------------------------
class Entry(object):
    def __init__(self, name, kind, source, description, path, sha, text, category):
        self.name = name
        self.kind = kind
        self.source = source
        self.description = description
        self.path = path
        self.sha256 = sha
        self.text = text
        self.category = category

    def as_dict(self):
        return {"name": self.name, "kind": self.kind, "source": self.source,
                "description": self.description, "path": self.path,
                "sha256": self.sha256, "category": self.category,
                "description_chars": len(self.description)}


class Catalog(object):
    def __init__(self, side, entries, warnings, roots):
        self.side = side
        self.entries = entries
        self.warnings = warnings
        self.roots = roots
        self.text = "\n".join("- %s (%s): %s" % (e.name, e.kind, e.description) for e in entries)
        self.sha256 = sha256_text(self.text)

    def names(self):
        return set(e.name for e in self.entries)

    def get(self, name):
        for e in self.entries:
            if e.name == name:
                return e
        return None

    def summary(self):
        by_source = {}
        for e in self.entries:
            b = by_source.setdefault(e.source, {"skills": 0, "agents": 0, "description_chars": 0})
            b["skills" if e.kind == "skill" else "agents"] += 1
            b["description_chars"] += len(e.description)
        return {
            "side": self.side,
            "entries": len(self.entries),
            "skills": sum(1 for e in self.entries if e.kind == "skill"),
            "agents": sum(1 for e in self.entries if e.kind == "agent"),
            "description_chars_total": sum(len(e.description) for e in self.entries),
            "description_chars_skills_only": sum(len(e.description) for e in self.entries if e.kind == "skill"),
            "catalog_text_chars": len(self.text),
            "catalog_text_est_tokens": len(self.text) // 4,
            "sha256": self.sha256,
            "by_source": by_source,
            "roots": self.roots,
            "warnings": self.warnings,
        }


def overlay_available():
    return OVERLAY_DIR.is_dir() and (OVERLAY_DIR / "skills").is_dir()


def _root_specs(side, overlay, public_ref, overlay_ref):
    specs = [("public", REPO_ROOT, public_ref)]
    if overlay and overlay_available():
        specs.append(("overlay", OVERLAY_DIR, overlay_ref))
    return specs


def list_side_paths(side, root, ref):
    if side == "head":
        paths = git_out(["ls-tree", "-r", "--name-only", ref], root).splitlines()
    else:
        paths = []
        for p in list(root.glob("skills/*/SKILL.md")) + list(root.glob("agents/*.md")):
            paths.append(p.relative_to(root).as_posix())
    return sorted(p for p in paths if SKILL_MD_RE.match(p) or AGENT_MD_RE.match(p))


def read_side_file(side, root, ref, relpath):
    if side == "head":
        r = subprocess.run(["git", "show", "%s:%s" % (ref, relpath)], cwd=str(root), capture_output=True)
        if r.returncode != 0:
            return None
        return r.stdout.decode("utf-8", "replace")
    p = root / relpath
    if not p.is_file():
        return None
    return p.read_text(encoding="utf-8", errors="replace")


def list_side_tree(side, root, ref, prefix):
    """All file paths under prefix (relative to root) on the given side."""
    if side == "head":
        out = git_out(["ls-tree", "-r", "--name-only", ref, "--", prefix], root, check=False)
        return sorted(out.splitlines())
    base = root / prefix
    if not base.is_dir():
        return []
    return sorted(p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file())


def load_catalog(side, overlay=True, public_ref="HEAD", overlay_ref="HEAD"):
    if side not in ("head", "worktree"):
        die("side must be head or worktree")
    entries, warnings, roots = [], [], []
    for label, root, ref in _root_specs(side, overlay, public_ref, overlay_ref):
        roots.append({"source": label, "root": str(root), "ref": ref if side == "head" else None})
        for rel in list_side_paths(side, root, ref):
            text = read_side_file(side, root, ref, rel)
            if text is None:
                warnings.append("%s: unreadable %s" % (label, rel))
                continue
            m = SKILL_MD_RE.match(rel)
            kind = "skill" if m else "agent"
            dirname = (m or AGENT_MD_RE.match(rel)).group(1)
            fm, _ = split_frontmatter(text)
            parsed = parse_frontmatter(fm or "")
            name = norm_ws(parsed.get("name", "")) or dirname
            if name != dirname:
                warnings.append("%s: %s frontmatter name %r != dir %r" % (label, rel, name, dirname))
            desc = norm_ws(parsed.get("description", ""))
            if not desc:
                warnings.append("%s: %s has no description" % (label, rel))
            entries.append(Entry(name, kind, label, desc, rel, sha256_text(text), text, parsed.get("_category")))
    seen = {}
    for e in entries:
        if e.name in seen:
            warnings.append("duplicate name %s in %s and %s" % (e.name, seen[e.name], e.source))
        seen[e.name] = e.source
    entries.sort(key=lambda e: (e.kind, e.name))
    return Catalog(side, entries, warnings, roots)


def collect_refs():
    refs = {
        "public_head": git_rev("HEAD", REPO_ROOT),
        "public_branch": git_out(["rev-parse", "--abbrev-ref", "HEAD"], REPO_ROOT, check=False).strip() or None,
        "overlay_head": git_rev("HEAD", OVERLAY_DIR) if overlay_available() else None,
        "public_gitlink_overlay": None,
        "worktree_dirty_catalog_paths": {},
    }
    gl = git_out(["rev-parse", "HEAD:dotfiles-mic"], REPO_ROOT, check=False).strip()
    refs["public_gitlink_overlay"] = gl or None
    refs["overlay_head_matches_gitlink"] = (refs["overlay_head"] == refs["public_gitlink_overlay"]) if refs["overlay_head"] else None
    for label, root in (("public", REPO_ROOT), ("overlay", OVERLAY_DIR)):
        if not root.is_dir():
            continue
        st = git_out(["status", "--porcelain", "--", "skills", "agents"], root, check=False)
        refs["worktree_dirty_catalog_paths"][label] = len([l for l in st.splitlines() if l.strip()])
    return refs


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------
def load_fixture(suite, path=None):
    base = FIXTURE_DIR / suite
    cases_path = Path(path) if path else base / "cases.json"
    if not cases_path.is_file():
        die("fixture not found: %s" % cases_path)
    raw = cases_path.read_bytes()
    data = json.loads(raw.decode("utf-8"))
    template_path = cases_path.parent / data.get("prompt_template", "prompt.md")
    if not template_path.is_file():
        die("prompt template not found: %s" % template_path)
    template_raw = template_path.read_bytes()
    return {
        "suite": data.get("suite", suite),
        "path": str(cases_path),
        "sha256": sha256_bytes(raw),
        "template_path": str(template_path),
        "template_sha256": sha256_bytes(template_raw),
        "template": template_raw.decode("utf-8"),
        "cases": data.get("cases", []),
        "version": data.get("version"),
    }


def flatten_expect(expect):
    out = []
    for item in expect or []:
        if isinstance(item, list):
            out.extend(item)
        else:
            out.append(item)
    return out


def fixture_names(fx):
    names = set()
    for c in fx["cases"]:
        names.update(flatten_expect(c.get("expect")))
        names.update(c.get("allow") or [])
        names.update(c.get("forbid") or [])
        if c.get("skill"):
            names.add(c["skill"])
    return names


def select_cases(cases, ids, lanes, limit):
    out = cases
    if ids:
        wanted = set(ids)
        out = [c for c in out if c["id"] in wanted]
        missing = wanted - set(c["id"] for c in out)
        if missing:
            die("unknown case id(s): %s" % ", ".join(sorted(missing)))
    if lanes:
        out = [c for c in out if c.get("lane") in set(lanes)]
    if limit is not None:
        out = out[:limit]
    return out


# --------------------------------------------------------------------------
# model adapter (argv only; prompt via stdin unless a literal "{prompt}" argv slot exists)
# --------------------------------------------------------------------------
class ModelResult(object):
    def __init__(self):
        self.status = "ok"
        self.content = ""
        self.exit_code = None
        self.elapsed_s = None
        self.usage = None
        self.cost_usd = None
        self.harness_duration_ms = None
        self.models_used = None
        self.stdout_len = 0
        self.stderr_tail = ""
        self.error = None


def parse_claude_json(stdout):
    obj = json.loads(stdout)
    if isinstance(obj, list):
        results = [o for o in obj if isinstance(o, dict) and o.get("type") == "result"]
        obj = results[-1] if results else None
    if not isinstance(obj, dict) or "result" not in obj:
        raise ValueError("claude-json: no result object")
    meta = {
        "usage": obj.get("usage"),
        "cost_usd": obj.get("total_cost_usd"),
        "harness_duration_ms": obj.get("duration_ms"),
        "models_used": sorted((obj.get("modelUsage") or {}).keys()) or None,
        "is_error": bool(obj.get("is_error")),
    }
    return obj.get("result") or "", meta


def parse_codex_jsonl(stdout):
    texts, usage = [], None
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        item = ev.get("item") if isinstance(ev, dict) else None
        if isinstance(item, dict) and item.get("type") == "agent_message" and item.get("text"):
            texts.append(item["text"])
        if isinstance(ev, dict) and ev.get("type") == "turn.completed" and isinstance(ev.get("usage"), dict):
            usage = ev["usage"]
    if not texts:
        raise ValueError("codex-jsonl: no agent_message item")
    return "\n".join(texts), {"usage": usage, "cost_usd": None, "harness_duration_ms": None, "models_used": None}


def run_model(argv, prompt, timeout, output_mode, cwd=None):
    """cwd: run the model command from another directory. Harness CLIs (claude, codex) auto-load
    the working directory's project instructions and per-project memory even with a replaced
    system prompt; an empty directory keeps those out of the prompt (global config still loads)."""
    res = ModelResult()
    argv2 = [prompt if a == "{prompt}" else a for a in argv]
    via_stdin = "{prompt}" not in argv
    t0 = time.monotonic()
    try:
        proc = subprocess.run(argv2, input=(prompt.encode("utf-8") if via_stdin else b""),
                              capture_output=True, timeout=timeout, cwd=cwd)
    except subprocess.TimeoutExpired:
        res.status = "timeout"
        res.elapsed_s = round(time.monotonic() - t0, 3)
        res.error = "no reply within %ss" % timeout
        return res
    except (FileNotFoundError, PermissionError) as exc:
        res.status = "error"
        res.elapsed_s = round(time.monotonic() - t0, 3)
        res.error = "cannot execute %r: %s" % (argv2[0], exc)
        return res
    res.elapsed_s = round(time.monotonic() - t0, 3)
    res.exit_code = proc.returncode
    stdout = proc.stdout.decode("utf-8", "replace")
    stderr = proc.stderr.decode("utf-8", "replace")
    res.stdout_len = len(stdout)
    res.stderr_tail = stderr[-600:]
    if proc.returncode != 0:
        res.status = "exit:%d" % proc.returncode
        res.error = "model command exited %d" % proc.returncode
        res.content = stdout  # kept for diagnostics / stream parsing; never counted as a reply by `run`
        return res
    try:
        if output_mode == "claude-json":
            res.content, meta = parse_claude_json(stdout)
            if meta.get("is_error"):
                res.status = "error"
                res.error = "harness reported is_error"
        elif output_mode == "codex-jsonl":
            res.content, meta = parse_codex_jsonl(stdout)
        else:
            res.content, meta = stdout, {}
    except ValueError as exc:
        res.status = "malformed"
        res.error = str(exc)
        return res
    res.usage = meta.get("usage")
    res.cost_usd = meta.get("cost_usd")
    res.harness_duration_ms = meta.get("harness_duration_ms")
    res.models_used = meta.get("models_used")
    if not res.content.strip():
        res.status = "malformed"
        res.error = "empty reply"
    return res


def extract_selection(content):
    """Last JSON object in the text that carries a 'select' list of strings."""
    dec = json.JSONDecoder()
    starts = [i for i, ch in enumerate(content) if ch == "{"]
    for i in reversed(starts):
        try:
            obj, _ = dec.raw_decode(content[i:])
        except ValueError:
            continue
        if isinstance(obj, dict) and "select" in obj:
            sel = obj["select"]
            if not isinstance(sel, list) or not all(isinstance(s, str) for s in sel):
                return None, "'select' is not a list of strings"
            out = []
            for s in sel:
                s2 = s.strip().strip("`'\" ").lower()
                if s2 and s2 not in out:
                    out.append(s2)
            return out, None
    return None, "no JSON object with a 'select' list in reply"


def routing_verdict(selection, case, known_names):
    sel = set(selection)
    expect = case.get("expect") or []
    allow = set(case.get("allow") or [])
    forbid = set(case.get("forbid") or [])
    reasons = []
    for item in expect:
        options = item if isinstance(item, list) else [item]
        if not any(o in sel for o in options):
            reasons.append("missing: %s" % "|".join(options))
    hit = sorted(sel & forbid)
    if hit:
        reasons.append("forbidden: %s" % ", ".join(hit))
    universe = set(flatten_expect(expect)) | allow
    stray = sorted(sel - universe)
    if stray:
        unknown = [s for s in stray if s not in known_names]
        reasons.append("stray: %s" % ", ".join(stray) + (" (unknown: %s)" % ", ".join(unknown) if unknown else ""))
    return ("pass" if not reasons else "fail"), reasons


def extract_for_verify(content, spec):
    spec = spec or "all"
    if spec == "all":
        return content, None
    if spec.startswith("fence:"):
        lang = spec[len("fence:"):].lower()
        blocks = [m.group(2) for m in FENCE_RE.finditer(content)
                  if lang in ("", "*") or m.group(1).lower() == lang]
        if not blocks:
            return None, "no ```%s fence in reply" % lang
        return "\n".join(blocks), None
    return None, "unknown extract spec %r" % spec


def task_verdict(content, verify):
    reasons = []
    text, err = extract_for_verify(content, verify.get("extract"))
    if err:
        return "fail", [err], 0
    if verify.get("parse") == "python":
        try:
            ast.parse(text)
        except SyntaxError as exc:
            reasons.append("python does not parse: line %s: %s" % (exc.lineno, exc.msg))
    flags = re.M | re.S
    if "i" in (verify.get("flags") or ""):
        flags |= re.I
    for pat in verify.get("must") or []:
        if not re.search(pat, text, flags):
            reasons.append("must-miss: /%s/" % pat)
    for pat in verify.get("must_not") or []:
        m = re.search(pat, text, flags)
        if m:
            reasons.append("must-not-hit: /%s/ -> %r" % (pat, m.group(0)[:40]))
    return ("pass" if not reasons else "fail"), reasons, len(text)


# --------------------------------------------------------------------------
# prompt assembly
# --------------------------------------------------------------------------
def build_routing_prompt(template, catalog, case):
    return template.replace("{catalog}", catalog.text).replace("{prompt}", case["prompt"])


def skill_bundle(side, catalog, skill_name, include_globs, include_cap, public_ref, overlay_ref):
    entry = catalog.get(skill_name)
    if entry is None:
        return None, "skill %r not in %s catalog" % (skill_name, side)
    root = REPO_ROOT if entry.source == "public" else OVERLAY_DIR
    ref = public_ref if entry.source == "public" else overlay_ref
    skill_dir = str(Path(entry.path).parent.as_posix())
    body = entry.text
    files = []
    if include_globs:
        for rel in list_side_tree(side, root, ref, skill_dir):
            inner = rel[len(skill_dir) + 1:] if rel.startswith(skill_dir + "/") else rel
            if inner == "SKILL.md":
                continue
            if any(fnmatch.fnmatch(inner, g) for g in include_globs):
                text = read_side_file(side, root, ref, rel)
                if text is not None:
                    files.append((inner, text))
    parts = [body]
    used = len(body)
    included = []
    for inner, text in files:
        if used + len(text) > include_cap:
            included.append({"path": inner, "chars": len(text), "included": False})
            continue
        parts.append('\n<file path="%s">\n%s\n</file>' % (inner, text))
        used += len(text)
        included.append({"path": inner, "chars": len(text), "included": True})
    return {"body": "".join(parts), "source": entry.source, "path": entry.path,
            "skill_sha256": entry.sha256, "files": included, "chars": used}, None


def build_task_prompt(template, bundle, case):
    return (template.replace("{skill}", case["skill"])
            .replace("{skill_body}", bundle["body"])
            .replace("{prompt}", case["prompt"]))


# --------------------------------------------------------------------------
# model command metadata
# --------------------------------------------------------------------------
def harness_version(argv, timeout=20):
    if not argv:
        return None
    exe = argv[0]
    if exe.endswith(".py") or exe in ("python", "python3"):
        return "python %s" % platform.python_version()
    try:
        r = subprocess.run([exe, "--version"], capture_output=True, timeout=timeout)
        line = (r.stdout or r.stderr).decode("utf-8", "replace").strip().splitlines()
        return line[0][:120] if line else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def infer_model_label(argv):
    for i, a in enumerate(argv):
        if a in ("--model", "-m") and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--model="):
            return a.split("=", 1)[1]
    return None


def tool_name(argv):
    """Basename of the real tool: skips a leading interpreter (python3 fake_model.py -> fake_model.py)."""
    if not argv:
        return None
    base = os.path.basename(argv[0])
    if base.startswith("python") and len(argv) > 1:
        return os.path.basename(argv[1])
    return base


def infer_provider(argv):
    return PROVIDER_BY_TOOL.get(tool_name(argv) or "")


def model_meta(args, argv):
    return {
        "argv": argv,
        "prompt_via": "argv-slot" if "{prompt}" in argv else "stdin",
        "label": args.model_label or infer_model_label(argv) or "unknown",
        "provider": args.provider or infer_provider(argv) or "unknown",
        "harness": args.harness or tool_name(argv),
        "harness_version": harness_version(argv),
        "output_mode": getattr(args, "output_mode", None) or getattr(args, "mode", None),
        "timeout_s": args.timeout,
        "cwd": str(Path(args.model_cwd).resolve()) if getattr(args, "model_cwd", None) else None,
    }


# --------------------------------------------------------------------------
# subcommands
# --------------------------------------------------------------------------
def cmd_catalog(args):
    cat = load_catalog(args.side, overlay=not args.no_overlay, public_ref=args.public_ref, overlay_ref=args.overlay_ref)
    if args.json:
        print(json.dumps({"summary": cat.summary(), "entries": [e.as_dict() for e in cat.entries]}, indent=2))
    else:
        print(cat.text)
        sys.stderr.write("# %s: %d entries, %d description chars, %d catalog chars, sha256 %s\n" % (
            args.side, len(cat.entries), cat.summary()["description_chars_total"], len(cat.text), cat.sha256[:12]))
        for w in cat.warnings:
            sys.stderr.write("# WARN %s\n" % w)
    return 0


def yaml_crosscheck(catalogs):
    try:
        import yaml  # noqa: F401
    except ImportError:
        return {"available": False, "mismatches": [], "checked": 0}
    import yaml as _yaml
    mismatches, checked = [], 0
    for cat in catalogs:
        for e in cat.entries:
            fm, _ = split_frontmatter(e.text)
            if fm is None:
                continue
            try:
                data = _yaml.safe_load(fm)
            except _yaml.YAMLError as exc:
                mismatches.append("%s %s: PyYAML error %s" % (cat.side, e.path, exc))
                continue
            checked += 1
            ref = norm_ws(str((data or {}).get("description", "")))
            if ref != e.description:
                mismatches.append("%s %s: stdlib parse differs from PyYAML" % (cat.side, e.path))
    return {"available": True, "mismatches": mismatches, "checked": checked}


def cmd_check(args):
    problems = []
    cats = [load_catalog(s, overlay=not args.no_overlay, public_ref=args.public_ref, overlay_ref=args.overlay_ref)
            for s in ("head", "worktree")]
    for cat in cats:
        for w in cat.warnings:
            print("WARN catalog[%s]: %s" % (cat.side, w))
    fixtures = [load_fixture(s) for s in (args.suites or ["routing", "tasks"])]
    for fx in fixtures:
        ids = [c.get("id") for c in fx["cases"]]
        if len(ids) != len(set(ids)) or any(not i for i in ids):
            problems.append("%s: case ids must be unique and non-empty" % fx["path"])
        for c in fx["cases"]:
            if not isinstance(c.get("prompt"), str) or not c["prompt"].strip():
                problems.append("%s: case %s has no prompt" % (fx["suite"], c.get("id")))
            if fx["suite"] == "routing":
                for key in ("expect", "allow", "forbid"):
                    if key in c and not isinstance(c[key], list):
                        problems.append("routing %s: %s must be a list" % (c["id"], key))
                overlap = set(flatten_expect(c.get("expect"))) & set(c.get("forbid") or [])
                if overlap:
                    problems.append("routing %s: names both expected and forbidden: %s" % (c["id"], sorted(overlap)))
            else:
                v = c.get("verify") or {}
                unknown = set(v.keys()) - {"extract", "parse", "must", "must_not", "flags"}
                if unknown:
                    problems.append("tasks %s: unknown verify keys %s" % (c["id"], sorted(unknown)))
                if v.get("parse") not in (None, "python"):
                    problems.append("tasks %s: unsupported parse %r" % (c["id"], v.get("parse")))
                ex = v.get("extract", "all")
                if not (ex == "all" or ex.startswith("fence:")):
                    problems.append("tasks %s: unsupported extract %r" % (c["id"], ex))
                for pat in (v.get("must") or []) + (v.get("must_not") or []):
                    try:
                        re.compile(pat)
                    except re.error as exc:
                        problems.append("tasks %s: bad regex /%s/: %s" % (c["id"], pat, exc))
                if not c.get("skill"):
                    problems.append("tasks %s: missing skill" % c["id"])
        names = fixture_names(fx)
        for cat in cats:
            unknown = sorted(names - cat.names())
            if unknown:
                problems.append("%s: names not in %s catalog: %s" % (fx["suite"], cat.side, ", ".join(unknown)))
        print("fixture %s: %d cases, sha256 %s" % (fx["suite"], len(fx["cases"]), fx["sha256"][:12]))
    for cat in cats:
        s = cat.summary()
        print("catalog %s: %d entries (%d skills, %d agents), description chars %d, catalog chars %d" % (
            cat.side, s["entries"], s["skills"], s["agents"], s["description_chars_total"], s["catalog_text_chars"]))
    yc = yaml_crosscheck(cats)
    if yc["available"]:
        print("yaml crosscheck: %d frontmatters checked, %d mismatches" % (yc["checked"], len(yc["mismatches"])))
        for m in yc["mismatches"]:
            problems.append("yaml crosscheck: " + m)
    else:
        print("yaml crosscheck: skipped (PyYAML not importable by %s)" % sys.executable)
    for p in problems:
        print("ERROR " + p)
    print("check: %s" % ("OK" if not problems else "%d problem(s)" % len(problems)))
    return 0 if not problems else 1


def codex_native_block(timeout, env=None):
    """Codex startup skills block from `codex debug prompt-input`. With the real HOME this is the
    INSTALLED catalog (worktree symlinks + Codex system skills); with a temp HOME whose
    ~/.agents/skills holds a HEAD extract it is the HEAD counterpart (system skills absent)."""
    try:
        r = subprocess.run(["codex", "debug", "prompt-input", "eval-skills measure"], capture_output=True,
                           timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"available": False, "error": str(exc)}
    if r.returncode != 0:
        return {"available": False, "error": "exit %d: %s" % (r.returncode, r.stderr.decode("utf-8", "replace")[-300:])}
    try:
        data = json.loads(r.stdout.decode("utf-8", "replace"))
    except ValueError as exc:
        return {"available": False, "error": "not json: %s" % exc}
    block = None
    for msg in data if isinstance(data, list) else []:
        for part in (msg.get("content") or []) if isinstance(msg, dict) else []:
            text = part.get("text") if isinstance(part, dict) else None
            if isinstance(text, str) and text.lstrip().startswith("<skills_instructions>"):
                block = text
                break
        if block:
            break
    if block is None:
        return {"available": False, "error": "no <skills_instructions> block in prompt-input"}
    lines = [l for l in block.splitlines() if l.startswith("- ") and re.search(r"\(file: r\d+/", l)]
    roots = dict(re.findall(r"^- `(r\d+)` = `([^`]+)`", block, re.M))
    per_root = {}
    for l in lines:
        key = re.search(r"\(file: (r\d+)/", l).group(1)
        per_root.setdefault(key, {"count": 0, "chars": 0})
        per_root[key]["count"] += 1
        per_root[key]["chars"] += len(l)
    codex_version = harness_version(["codex"])
    return {"available": True, "chars": len(block), "est_tokens": len(block) // 4, "entries": len(lines),
            "roots": roots, "per_root": per_root, "codex_version": codex_version}


def codex_native_head_block(timeout, overlay, public_ref, overlay_ref):
    """Extract HEAD skills (git archive, stdlib tarfile) into a temp HOME's ~/.agents/skills and
    measure the block Codex renders for it. Touches neither tree; the temp dir is removed."""
    tmp = Path(tempfile.mkdtemp(prefix="eval-skills-codex-head-"))
    try:
        root = tmp / ".agents" / "skills"
        root.mkdir(parents=True)
        (tmp / ".codex").mkdir()
        (tmp / ".codex" / "config.toml").write_text('model = "gpt-5.6-luna"\n', encoding="utf-8")
        for label, repo, ref in _root_specs("head", overlay, public_ref, overlay_ref):
            r = subprocess.run(["git", "archive", "--format=tar", ref, "skills"], cwd=str(repo), capture_output=True)
            if r.returncode != 0:
                return {"available": False, "error": "git archive %s failed for %s" % (ref, label)}
            with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tf:
                for member in tf.getmembers():
                    parts = Path(member.name).parts
                    if len(parts) < 2 or parts[0] != "skills" or ".." in parts:
                        continue
                    target = root.joinpath(*parts[1:])
                    if member.isdir():
                        target.mkdir(parents=True, exist_ok=True)
                    elif member.isfile():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(tf.extractfile(member).read())
        env = {k: v for k, v in os.environ.items() if k not in ("CODEX_HOME",)}
        env["HOME"] = str(tmp)
        out = codex_native_block(timeout, env=env)
        out["temp_home"] = True
        out["skills_extracted"] = len([p for p in root.iterdir() if p.is_dir()])
        return out
    finally:
        shutil.rmtree(str(tmp), ignore_errors=True)


def codex_rendered_chars(cat, root_alias="r0"):
    """Same per-skill line shape Codex renders, so HEAD and worktree are comparable."""
    lines = ["- %s: %s (file: %s/%s/SKILL.md)" % (e.name, e.description, root_alias, e.name)
             for e in cat.entries if e.kind == "skill"]
    return {"skills": len(lines), "chars": sum(len(l) + 1 for l in lines)}


def cmd_measure(args):
    out = {"measured_at": utc_iso(), "refs": collect_refs(), "sides": {}, "notes": [
        "description_chars_total = sum of whitespace-normalized frontmatter descriptions (skills + agents).",
        "codex_rendered = dotfiles skills rendered in Codex's '- name: description (file: r0/name/SKILL.md)' line shape; comparable across sides.",
        "codex_native = live `codex debug prompt-input` <skills_instructions> block; reflects INSTALLED skills (worktree symlinks) plus Codex system skills, so it has no HEAD counterpart.",
    ]}
    for side in ("head", "worktree"):
        cat = load_catalog(side, overlay=not args.no_overlay, public_ref=args.public_ref, overlay_ref=args.overlay_ref)
        s = cat.summary()
        s["codex_rendered"] = codex_rendered_chars(cat)
        out["sides"][side] = s
    if args.codex_native:
        out["codex_native"] = codex_native_block(args.timeout)
        out["codex_native_head"] = codex_native_head_block(args.timeout, not args.no_overlay, args.public_ref, args.overlay_ref)
        out["notes"].append("codex_native_head = same measurement against a temp HOME whose ~/.agents/skills is a `git archive HEAD skills` extract of public + overlay (no Codex system skills there); compare per-root r0 chars, not totals.")
    if args.json:
        json_path = resolve_out(args.json, args.allow_outside_local)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    h, w = out["sides"]["head"], out["sides"]["worktree"]
    print("| metric | head | worktree | delta |")
    print("|---|---:|---:|---:|")
    for label, key in (("entries", "entries"), ("description chars (skills+agents)", "description_chars_total"),
                       ("description chars (skills only, lint INFO basis)", "description_chars_skills_only"),
                       ("catalog prompt chars", "catalog_text_chars"), ("catalog est. tokens", "catalog_text_est_tokens")):
        print("| %s | %d | %d | %+d |" % (label, h[key], w[key], w[key] - h[key]))
    print("| codex rendered chars (dotfiles skills) | %d | %d | %+d |" % (
        h["codex_rendered"]["chars"], w["codex_rendered"]["chars"], w["codex_rendered"]["chars"] - h["codex_rendered"]["chars"]))
    for src in sorted(set(h["by_source"]) | set(w["by_source"])):
        a = h["by_source"].get(src, {}).get("description_chars", 0)
        b = w["by_source"].get(src, {}).get("description_chars", 0)
        print("| description chars: %s | %d | %d | %+d |" % (src, a, b, b - a))
    cn = out.get("codex_native")
    ch = out.get("codex_native_head")
    if cn:
        def r0(block):
            if not block or not block.get("available"):
                return None
            roots = block.get("roots") or {}
            for alias, path in roots.items():
                if path.rstrip("/").endswith("/.agents/skills"):
                    return block.get("per_root", {}).get(alias)
            return None
        a, b = r0(ch), r0(cn)
        if cn.get("available"):
            print("| codex native skills block chars, total (HEAD via temp HOME / installed live) | %s | %d | %s |" % (
                ch.get("chars") if ch and ch.get("available") else "n/a", cn["chars"],
                ("%+d" % (cn["chars"] - ch["chars"])) if ch and ch.get("available") else "-"))
            print("| codex native entries (all roots) | %s | %d | - |" % (ch.get("entries") if ch and ch.get("available") else "n/a", cn["entries"]))
            if a and b:
                print("| codex native ~/.agents/skills lines: count | %d | %d | %+d |" % (a["count"], b["count"], b["count"] - a["count"]))
                print("| codex native ~/.agents/skills lines: chars | %d | %d | %+d |" % (a["chars"], b["chars"], b["chars"] - a["chars"]))
        else:
            print("| codex native skills block | - | unavailable: %s | - |" % cn.get("error"))
        if ch and not ch.get("available"):
            print("| codex native HEAD replica | unavailable: %s | - | - |" % ch.get("error"))
    return 0


def write_summary_md(run_dir, meta, records):
    lines = ["# eval-skills run %s" % meta["run_id"], "",
             "- side: **%s**, suite: **%s**, cases: %d" % (meta["side"], meta["suite"], len(records)),
             "- model: %s (%s) via %s %s, output mode %s, timeout %ss" % (
                 meta["model"]["label"], meta["model"]["provider"], meta["model"]["harness"],
                 meta["model"]["harness_version"], meta["model"]["output_mode"], meta["model"]["timeout_s"]),
             "- refs: public %s, overlay %s (gitlink %s)" % (
                 (meta["refs"]["public_head"] or "?")[:12], (meta["refs"]["overlay_head"] or "-")[:12],
                 (meta["refs"]["public_gitlink_overlay"] or "-")[:12]),
             "- catalog: %d entries, %d description chars, sha256 %s" % (
                 meta["catalog"]["entries"], meta["catalog"]["description_chars_total"], meta["catalog"]["sha256"][:12]),
             "- fixture: %s sha256 %s" % (meta["fixture"]["path"], meta["fixture"]["sha256"][:12]),
             "- totals: %(pass)d pass / %(fail)d fail / %(error)d error; %(elapsed_s).1fs; tokens in %(tokens_in)s out %(tokens_out)s; cost %(cost_usd)s" % meta["totals"],
             "", "Simulation note: `run` embeds the catalog in a prompt; it is not the harness's native routing.", "",
             "| case | lane | verdict | status | selection / reasons | s |", "|---|---|---|---|---|---:|"]
    for r in records:
        detail = ", ".join(r.get("selection") or []) if r["suite"] == "routing" else ""
        if r["reasons"]:
            detail = (detail + " ; " if detail else "") + "; ".join(r["reasons"])
        lines.append("| %s | %s | %s | %s | %s | %.1f |" % (
            r["id"], r.get("lane", ""), r["verdict"], r["status"], detail.replace("|", "\\|"), r["elapsed_s"] or 0))
    run_dir.joinpath("summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_run(args):
    argv = args.model_cmd
    if not argv and not args.dry_run:
        die("model command required after '--' (or use --dry-run)")
    out_root = resolve_out(args.out, args.allow_outside_local)
    if args.model_cwd and not Path(args.model_cwd).is_dir():
        die("--model-cwd %s is not a directory" % args.model_cwd)
    catalog = load_catalog(args.side, overlay=not args.no_overlay, public_ref=args.public_ref, overlay_ref=args.overlay_ref)
    fx = load_fixture(args.suite, args.cases)
    cases = select_cases(fx["cases"], args.case, args.lane, args.limit)
    if not cases:
        die("no cases selected")
    run_id = "%s-%s-%s" % (utc_stamp(), args.side, args.suite)
    run_dir = out_root / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    meta = {
        "run_id": run_id, "runner_version": RUNNER_VERSION, "status": "running",
        "started_at": utc_iso(), "finished_at": None,
        "side": args.side, "suite": args.suite, "dry_run": bool(args.dry_run),
        "refs": collect_refs(), "catalog": catalog.summary(),
        "fixture": {"path": os.path.relpath(fx["path"], str(REPO_ROOT)), "sha256": fx["sha256"],
                    "template_sha256": fx["template_sha256"], "cases_total": len(fx["cases"]),
                    "cases_selected": [c["id"] for c in cases]},
        "model": model_meta(args, argv) if argv else {"argv": [], "label": "dry-run", "provider": None,
                                                     "harness": None, "harness_version": None,
                                                     "output_mode": args.output_mode, "timeout_s": args.timeout,
                                                     "prompt_via": None},
        "python": platform.python_version(), "platform": platform.platform(),
        "simulation_note": "catalog-prompt simulation; not native harness routing",
        "totals": None,
    }
    if args.save_prompts or args.dry_run:
        (run_dir / "prompts").mkdir(exist_ok=True)
    meta_path = run_dir / "meta.json"
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    results_path = run_dir / "results.jsonl"
    known = catalog.names()
    records = []
    totals = {"pass": 0, "fail": 0, "error": 0, "elapsed_s": 0.0, "tokens_in": 0, "tokens_out": 0, "cost_usd": 0.0,
              "tokens_seen": False, "cost_seen": False}
    with results_path.open("w", encoding="utf-8") as fh:
        for case in cases:
            rec = {"run_id": run_id, "side": args.side, "suite": args.suite, "id": case["id"],
                   "lane": case.get("lane"), "status": "ok", "verdict": "error", "reasons": [],
                   "selection": None, "elapsed_s": None, "usage": None, "cost_usd": None,
                   "harness_duration_ms": None, "models_used": None, "content_len": 0, "stderr_tail": ""}
            if args.suite == "routing":
                prompt = build_routing_prompt(fx["template"], catalog, case)
                rec.update({"expect": case.get("expect") or [], "allow": case.get("allow") or [],
                            "forbid": case.get("forbid") or []})
            else:
                bundle, err = skill_bundle(args.side, catalog, case["skill"], case.get("include"),
                                           args.include_cap, args.public_ref, args.overlay_ref)
                if err:
                    rec["status"] = "error"
                    rec["reasons"] = [err]
                    records.append(rec)
                    fh.write(json.dumps(rec) + "\n")
                    totals["error"] += 1
                    continue
                prompt = build_task_prompt(fx["template"], bundle, case)
                rec.update({"skill": case["skill"], "skill_source": bundle["source"], "skill_path": bundle["path"],
                            "skill_sha256": bundle["skill_sha256"], "skill_bundle_chars": bundle["chars"],
                            "skill_files": bundle["files"], "verify": case.get("verify") or {}})
            rec["prompt_sha256"] = sha256_text(prompt)
            rec["prompt_chars"] = len(prompt)
            if args.save_prompts or args.dry_run:
                (run_dir / "prompts" / (case["id"] + ".txt")).write_text(prompt, encoding="utf-8")
            if args.dry_run:
                rec["status"] = "dry-run"
                rec["verdict"] = "skipped"
                records.append(rec)
                fh.write(json.dumps(rec) + "\n")
                sys.stderr.write("dry-run %-32s prompt %d chars\n" % (case["id"], len(prompt)))
                continue
            mr = run_model(argv, prompt, args.timeout, args.output_mode, cwd=args.model_cwd)
            rec.update({"status": mr.status, "elapsed_s": mr.elapsed_s, "usage": mr.usage, "cost_usd": mr.cost_usd,
                        "harness_duration_ms": mr.harness_duration_ms, "models_used": mr.models_used,
                        "content_len": len(mr.content), "stderr_tail": mr.stderr_tail, "exit_code": mr.exit_code})
            if mr.status != "ok":
                rec["reasons"] = [mr.error or mr.status]
            elif args.suite == "routing":
                sel, err = extract_selection(mr.content)
                if err:
                    rec["status"] = "malformed"
                    rec["reasons"] = [err]
                else:
                    rec["selection"] = sel
                    rec["verdict"], rec["reasons"] = routing_verdict(sel, case, known)
            else:
                rec["verdict"], rec["reasons"], rec["extracted_len"] = task_verdict(mr.content, case.get("verify") or {})
            if args.save_replies:
                (run_dir / "replies").mkdir(exist_ok=True)
                (run_dir / "replies" / (case["id"] + ".txt")).write_text(mr.content, encoding="utf-8")
            totals[rec["verdict"] if rec["verdict"] in ("pass", "fail") else "error"] += 1
            totals["elapsed_s"] += mr.elapsed_s or 0
            if isinstance(mr.usage, dict):
                tin = mr.usage.get("input_tokens")
                tout = mr.usage.get("output_tokens")
                if isinstance(tin, int):
                    totals["tokens_in"] += tin + int(mr.usage.get("cache_read_input_tokens") or 0) + int(mr.usage.get("cache_creation_input_tokens") or 0)
                    totals["tokens_seen"] = True
                if isinstance(tout, int):
                    totals["tokens_out"] += tout
            if isinstance(mr.cost_usd, (int, float)):
                totals["cost_usd"] += mr.cost_usd
                totals["cost_seen"] = True
            records.append(rec)
            fh.write(json.dumps(rec) + "\n")
            fh.flush()
            sys.stderr.write("%-5s %-32s %-9s %s\n" % (rec["verdict"], case["id"], rec["status"],
                                                      "; ".join(rec["reasons"])[:100]))
    if not totals["tokens_seen"]:
        totals["tokens_in"] = totals["tokens_out"] = None
    if not totals["cost_seen"]:
        totals["cost_usd"] = None
    else:
        totals["cost_usd"] = round(totals["cost_usd"], 6)
    totals.pop("tokens_seen")
    totals.pop("cost_seen")
    totals["elapsed_s"] = round(totals["elapsed_s"], 3)
    meta["totals"] = totals
    meta["status"] = "complete"
    meta["finished_at"] = utc_iso()
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    if not args.dry_run:
        write_summary_md(run_dir, meta, records)
    print("run %s: %d pass / %d fail / %d error -> %s" % (run_id, totals["pass"], totals["fail"], totals["error"], run_dir))
    if args.strict and (totals["fail"] or totals["error"]):
        return 1
    return 0


def load_run(path):
    d = Path(path)
    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    recs = [json.loads(l) for l in (d / "results.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    return meta, {r["id"]: r for r in recs}


UNKNOWN_LABELS = (None, "", "unknown", "dry-run")


def served_models(recs):
    """(exposed, set of model ids) from per-case modelUsage; empty when the harness exposes none."""
    seen = set()
    for r in recs.values():
        for m in r.get("models_used") or []:
            seen.add(m)
    return bool(seen), seen


def equivalence_problems(ma, mb, ra=None, rb=None):
    """A like-for-like comparison needs the same suite, fixture, model, provider, harness,
    harness version, output mode and argv on both runs, all of them known, and the same
    SERVED model set where the harness exposes it (a requested alias can fall back to another
    model; only modelUsage shows that). Sides may differ (that is the point); run ids and refs
    may differ. Returns (problems, gaps): problems invalidate, gaps are reported."""
    problems = []
    gaps = []
    if ra is not None and rb is not None:
        exp_a, mods_a = served_models(ra)
        exp_b, mods_b = served_models(rb)
        if exp_a and exp_b:
            if mods_a != mods_b:
                problems.append("served models differ: %s vs %s" % (sorted(mods_a), sorted(mods_b)))
        else:
            for name, exp in (("baseline", exp_a), ("candidate", exp_b)):
                if not exp:
                    gaps.append("%s: served model unverified (harness exposes no modelUsage; label/argv cannot detect an alias fallback)" % name)
    for label, get in (
        ("suite", lambda m: m.get("suite")),
        ("fixture sha256", lambda m: m["fixture"]["sha256"]),
        ("prompt template sha256", lambda m: m["fixture"].get("template_sha256")),
        ("model label", lambda m: m["model"].get("label")),
        ("provider", lambda m: m["model"].get("provider")),
        ("harness", lambda m: m["model"].get("harness")),
        ("harness version", lambda m: m["model"].get("harness_version")),
        ("output mode", lambda m: m["model"].get("output_mode")),
        ("argv", lambda m: json.dumps(m["model"].get("argv"))),
        ("model cwd", lambda m: m["model"].get("cwd")),
    ):
        a, b = get(ma), get(mb)
        if a != b:
            problems.append("%s differs: %r vs %r" % (label, a, b))
    for name, m in (("baseline", ma), ("candidate", mb)):
        if m.get("dry_run"):
            problems.append("%s is a dry run (no verdicts)" % name)
        if m["model"].get("label") in UNKNOWN_LABELS:
            problems.append("%s model label unknown (pass --model-label on run)" % name)
        if m["model"].get("provider") in UNKNOWN_LABELS:
            problems.append("%s provider unknown (pass --provider on run)" % name)
        if not m["model"].get("harness_version"):
            problems.append("%s harness version unknown (pass --harness / a tool that answers --version)" % name)
        if m.get("status") != "complete":
            problems.append("%s run is not complete" % name)
    return problems, gaps


def cmd_compare(args):
    ma, ra = load_run(args.baseline)
    mb, rb = load_run(args.candidate)
    problems, gaps = equivalence_problems(ma, mb, ra, rb)
    valid = not problems
    _, mods_a = served_models(ra)
    _, mods_b = served_models(rb)
    ids = sorted(set(ra) | set(rb), key=lambda i: (ra.get(i, rb.get(i)).get("lane") or "", i))
    lines = ["# eval-skills compare", "",
             "| | baseline | candidate |", "|---|---|---|",
             "| run | %s | %s |" % (ma["run_id"], mb["run_id"]),
             "| side | %s | %s |" % (ma["side"], mb["side"]),
             "| suite | %s | %s |" % (ma["suite"], mb["suite"]),
             "| model | %s (%s) %s %s | %s (%s) %s %s |" % (
                 ma["model"]["label"], ma["model"]["provider"], ma["model"]["harness"], ma["model"]["harness_version"],
                 mb["model"]["label"], mb["model"]["provider"], mb["model"]["harness"], mb["model"]["harness_version"]),
             "| public / overlay ref | %s / %s | %s / %s |" % (
                 (ma["refs"]["public_head"] or "?")[:12], (ma["refs"]["overlay_head"] or "-")[:12],
                 (mb["refs"]["public_head"] or "?")[:12], (mb["refs"]["overlay_head"] or "-")[:12]),
             "| served models (modelUsage) | %s | %s |" % (", ".join(sorted(mods_a)) or "not exposed", ", ".join(sorted(mods_b)) or "not exposed"),
             "| catalog sha256 | %s | %s |" % (ma["catalog"]["sha256"][:12], mb["catalog"]["sha256"][:12]),
             "| catalog entries / description chars | %d / %d | %d / %d |" % (
                 ma["catalog"]["entries"], ma["catalog"]["description_chars_total"],
                 mb["catalog"]["entries"], mb["catalog"]["description_chars_total"]),
             "| fixture sha256 | %s | %s |" % (ma["fixture"]["sha256"][:12], mb["fixture"]["sha256"][:12]),
             "| pass / fail / error | %(pass)d / %(fail)d / %(error)d |" % ma["totals"] + " %(pass)d / %(fail)d / %(error)d |" % mb["totals"],
             "| elapsed s | %.1f | %.1f |" % (ma["totals"]["elapsed_s"], mb["totals"]["elapsed_s"]),
             "| tokens in / out | %s / %s | %s / %s |" % (ma["totals"]["tokens_in"], ma["totals"]["tokens_out"],
                                                        mb["totals"]["tokens_in"], mb["totals"]["tokens_out"]),
             "| cost usd | %s | %s |" % (ma["totals"]["cost_usd"], mb["totals"]["cost_usd"]), ""]
    if valid:
        lines.append("comparison: **VALID** (same suite, fixture, template, model, provider, harness, version, output mode, argv%s)" % (
            ", served models" if mods_a and mods_b else ""))
    else:
        lines.append("comparison: **INVALID** — not like-for-like%s" % (" (shown anyway: --allow-mismatch)" if args.allow_mismatch else ""))
        for pr in problems:
            lines.append("- " + pr)
    for g in gaps:
        lines.append("- equivalence gap: " + g)
    lines.append("")
    lines += ["| case | lane | baseline | candidate | change | baseline detail | candidate detail |",
              "|---|---|---|---|---|---|---|"]
    counts = {"REGRESSION": 0, "FIXED": 0, "SAME": 0, "ERROR": 0, "MISSING": 0}
    per_lane = {}
    for i in ids:
        a, b = ra.get(i), rb.get(i)
        lane = (a or b).get("lane") or ""
        va = a["verdict"] if a else "-"
        vb = b["verdict"] if b else "-"
        if a is None or b is None:
            change = "MISSING"
        elif va == "error" or vb == "error":
            change = "ERROR"
        elif va == "pass" and vb == "fail":
            change = "REGRESSION"
        elif va == "fail" and vb == "pass":
            change = "FIXED"
        else:
            change = "SAME"
        counts[change] += 1
        pl = per_lane.setdefault(lane, {"baseline_pass": 0, "candidate_pass": 0, "cases": 0})
        pl["cases"] += 1
        pl["baseline_pass"] += 1 if va == "pass" else 0
        pl["candidate_pass"] += 1 if vb == "pass" else 0

        def detail(r):
            if not r:
                return "-"
            d = ", ".join(r.get("selection") or []) if r.get("suite") == "routing" else ""
            if r.get("reasons"):
                d = (d + " ; " if d else "") + "; ".join(r["reasons"])
            return d.replace("|", "\\|")
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (i, lane, va, vb, change, detail(a), detail(b)))
    lines += ["", "| lane | cases | baseline pass | candidate pass |", "|---|---:|---:|---:|"]
    for lane in sorted(per_lane):
        pl = per_lane[lane]
        lines.append("| %s | %d | %d | %d |" % (lane, pl["cases"], pl["baseline_pass"], pl["candidate_pass"]))
    lines += ["", "changes: " + ", ".join("%s %d" % (k, v) for k, v in counts.items() if v),
              "", "Simulation note: both runs are catalog-prompt simulations, not native harness routing."]
    text = "\n".join(lines) + "\n"
    if args.md:
        p = resolve_out(args.md, args.allow_outside_local)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    print(text, end="")
    if not valid and not args.allow_mismatch:
        sys.stderr.write("eval-skills: comparison INVALID (%d problem(s)); pass --allow-mismatch to view anyway\n" % len(problems))
        return 2
    return 0


def parse_claude_stream(stdout):
    """Observe Skill / subagent tool calls in `claude -p --output-format stream-json --verbose` output."""
    selection, init, usage, cost, final_text = [], None, None, None, ""
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        t = ev.get("type")
        if t == "system" and ev.get("subtype") == "init":
            init = {"model": ev.get("model"), "tools": ev.get("tools"),
                    "skills": ev.get("skills") or ev.get("slash_commands"), "version": ev.get("version")}
        elif t == "assistant":
            for block in (ev.get("message") or {}).get("content") or []:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                inp = block.get("input") or {}
                if name == "Skill":
                    selection.append(str(inp.get("skill") or inp.get("name") or "?").strip().lower())
                elif name in ("Task", "Agent"):
                    selection.append(str(inp.get("subagent_type") or "?").strip().lower())
        elif t == "result":
            usage, cost, final_text = ev.get("usage"), ev.get("total_cost_usd"), ev.get("result") or ""
    return selection, init, usage, cost, final_text


def cmd_native_check(args):
    argv = args.model_cmd
    if not argv:
        die("harness command required after '--'")
    out_root = resolve_out(args.out, args.allow_outside_local)
    fx = load_fixture("routing", args.cases)
    cases = select_cases(fx["cases"], args.case, args.lane, args.limit)
    if not cases:
        die("no cases selected")
    catalog = load_catalog("worktree", overlay=not args.no_overlay)
    run_id = "%s-native-routing" % utc_stamp()
    run_dir = out_root / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    meta = {"run_id": run_id, "runner_version": RUNNER_VERSION, "kind": "native-check",
            "evidence": "direction-only: real harness, installed (worktree) skills, raw user prompt; selection = observed Skill/subagent tool calls",
            "side": "installed", "suite": "routing", "started_at": utc_iso(), "refs": collect_refs(),
            "catalog_worktree": catalog.summary(), "fixture": {"path": os.path.relpath(fx["path"], str(REPO_ROOT)),
                                                               "sha256": fx["sha256"]},
            "model": model_meta(args, argv), "mode": args.mode, "totals": None}
    records = []
    totals = {"pass": 0, "fail": 0, "error": 0, "elapsed_s": 0.0}
    with (run_dir / "results.jsonl").open("w", encoding="utf-8") as fh:
        for case in cases:
            mr = run_model(argv, case["prompt"], args.timeout, "text", cwd=args.model_cwd)
            rec = {"run_id": run_id, "suite": "routing", "id": case["id"], "lane": case.get("lane"),
                   "status": mr.status, "verdict": "error", "reasons": [], "selection": None,
                   "elapsed_s": mr.elapsed_s, "usage": None, "cost_usd": None, "stderr_tail": mr.stderr_tail,
                   "expect": case.get("expect") or [], "allow": case.get("allow") or [], "forbid": case.get("forbid") or [],
                   "evidence": "native-direction-only"}
            # `claude -p --max-turns 1` exits 1 (error_max_turns) after the first tool call by design:
            # the stream is still complete, so parse it and keep the exit code as a note.
            if mr.status == "ok" or (mr.status.startswith("exit:") and mr.content.strip()):
                rec["exit_code"] = mr.exit_code
                if args.mode == "claude-stream":
                    sel, init, usage, cost, final_text = parse_claude_stream(mr.content)
                    rec.update({"selection": sel, "usage": usage, "cost_usd": cost, "harness_init": init,
                                "final_text_head": final_text[:200]})
                    if init is None and not sel:
                        rec["status"] = "malformed"
                        rec["reasons"] = ["no stream-json events found"]
                    else:
                        rec["status"] = "ok" if mr.status == "ok" else "ok(%s)" % mr.status
                        rec["verdict"], rec["reasons"] = routing_verdict(sel, case, catalog.names())
                else:
                    rec["status"] = "unobservable"
                    rec["reasons"] = ["mode %s exposes no observable selection" % args.mode]
            else:
                rec["reasons"] = [mr.error or mr.status]
            if args.save_replies:
                (run_dir / "replies").mkdir(exist_ok=True)
                (run_dir / "replies" / (case["id"] + ".jsonl")).write_text(mr.content, encoding="utf-8")
            totals[rec["verdict"] if rec["verdict"] in ("pass", "fail") else "error"] += 1
            totals["elapsed_s"] += mr.elapsed_s or 0
            records.append(rec)
            fh.write(json.dumps(rec) + "\n")
            fh.flush()
            sys.stderr.write("%-5s %-32s %-9s sel=%s %s\n" % (rec["verdict"], case["id"], rec["status"],
                                                             rec.get("selection"), "; ".join(rec["reasons"])[:80]))
    totals["elapsed_s"] = round(totals["elapsed_s"], 3)
    meta["totals"] = totals
    meta["finished_at"] = utc_iso()
    (run_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print("native-check %s: %d pass / %d fail / %d error (direction-only) -> %s" % (
        run_id, totals["pass"], totals["fail"], totals["error"], run_dir))
    return 0


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def add_side_args(p, with_side=True):
    if with_side:
        p.add_argument("--side", choices=("head", "worktree"), required=True)
    p.add_argument("--no-overlay", action="store_true", help="ignore dotfiles-mic even if present")
    p.add_argument("--public-ref", default="HEAD")
    p.add_argument("--overlay-ref", default="HEAD", help="overlay ref for side=head (default: the overlay's own HEAD)")


def add_model_args(p):
    p.add_argument("--timeout", type=float, default=120.0, help="seconds per model call")
    p.add_argument("--model-label", help="override inferred model name for the record")
    p.add_argument("--provider", help="override inferred provider (Anthropic/OpenAI/xAI/Google/...)")
    p.add_argument("--harness", help="override inferred harness name")
    p.add_argument("--out", default=str(DEFAULT_OUT), help="results root (default .local/eval-skills)")
    p.add_argument("--allow-outside-local", action="store_true")
    p.add_argument("--case", action="append", help="run only this case id (repeatable)")
    p.add_argument("--lane", action="append", help="run only this lane (repeatable)")
    p.add_argument("--limit", type=int, help="run at most N cases")
    p.add_argument("--cases", help="alternate cases.json path")
    p.add_argument("--save-replies", action="store_true", help="store raw model replies in the run dir")
    p.add_argument("--model-cwd", help="run the model command from this directory (use an empty dir to keep "
                                       "the harness from loading project instructions and per-project memory)")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    model_cmd = []
    if "--" in argv:
        i = argv.index("--")
        model_cmd = argv[i + 1:]
        argv = argv[:i]
    ap = argparse.ArgumentParser(prog="eval-skills.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("catalog", help="print a side's catalog text")
    add_side_args(p)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_catalog)

    p = sub.add_parser("check", help="validate fixtures against both catalogs")
    add_side_args(p, with_side=False)
    p.add_argument("--suite", dest="suites", action="append", choices=("routing", "tasks"))
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("measure", help="catalog budget numbers per side")
    add_side_args(p, with_side=False)
    p.add_argument("--codex-native", action="store_true", help="also measure the live Codex skills block")
    p.add_argument("--timeout", type=float, default=90.0)
    p.add_argument("--json", help="write full numbers to this path (under .local unless --allow-outside-local)")
    p.add_argument("--allow-outside-local", action="store_true")
    p.set_defaults(func=cmd_measure)

    p = sub.add_parser("run", help="evaluate one side through a model command: run ... -- <argv>")
    add_side_args(p)
    p.add_argument("--suite", choices=("routing", "tasks"), default="routing")
    p.add_argument("--output-mode", choices=("text", "claude-json", "codex-jsonl"), default="text")
    p.add_argument("--include-cap", type=int, default=60000, help="max chars of skill body + included files per task prompt")
    p.add_argument("--dry-run", action="store_true", help="write prompts only, call no model")
    p.add_argument("--save-prompts", action="store_true")
    p.add_argument("--strict", action="store_true", help="exit 1 when any case fails or errors")
    add_model_args(p)
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("compare", help="diff two run directories")
    p.add_argument("baseline")
    p.add_argument("candidate")
    p.add_argument("--md", help="also write the markdown report here (under .local unless allowed)")
    p.add_argument("--allow-outside-local", action="store_true")
    p.add_argument("--allow-mismatch", action="store_true",
                   help="render an INVALID (non like-for-like) comparison anyway and exit 0")
    p.set_defaults(func=cmd_compare)

    p = sub.add_parser("native-check", help="observe real harness skill selection (direction-only)")
    p.add_argument("--no-overlay", action="store_true")
    p.add_argument("--mode", choices=("claude-stream", "text"), default="claude-stream")
    add_model_args(p)
    p.set_defaults(func=cmd_native_check)

    args = ap.parse_args(argv)
    args.model_cmd = model_cmd
    try:
        return args.func(args)
    except RuntimeError as exc:
        die(str(exc))


if __name__ == "__main__":
    sys.exit(main())
