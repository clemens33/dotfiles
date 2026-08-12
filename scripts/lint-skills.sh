#!/usr/bin/env bash
# Lint SKILL.md files against the skill spec + repo conventions.
#
# Usage: lint-skills.sh <skill-parent-dir> [<skill-parent-dir> ...]
#                        [--waivers <path>] [--conf <path>]...
#
# --waivers <path>  Waivers file (default: <this script's repo root>/scripts/lint-skills.waivers)
# --conf <path>     install.conf.yaml source for gate-6 cross-refs. Repeatable.
#                    Default (only when no --conf given at all): this script's
#                    repo root's install.conf.yaml + dotfiles-mic/install.conf.yaml.
#
# All defaults resolve relative to THIS SCRIPT's own location, never the
# caller's cwd — the overlay repo invokes a checked-out copy of this script
# from a sibling directory and must get the same defaults it would get run
# from its "home" repo. Pass --waivers/--conf explicitly to point at a
# different layout (see .github/workflows/lint-skills.yml in the overlay).
#
# Fail-closed rule: a --waivers/--conf path given EXPLICITLY on the command
# line that does not exist is a fatal (unwaivable) error — a typo'd flag
# must never silently degrade to "no waivers"/"no cross-refs". The
# warn-and-continue behavior applies ONLY to the auto-detected DEFAULT
# overlay conf path when no --conf was given at all (public CI without the
# private overlay submodule checked out).
#
# Spec-validity path taken: no tagged release exists on
# github.com/agentskills/agentskills (verified: `git ls-remote --tags` is
# empty), so a pinned `uvx`/`npx` invocation of skills-ref cannot be run
# cleanly. This script mirrors the spec checks inline instead (see gate 1
# below).
#
# Deliberate narrowings (decided, not oversights):
#   - Gate 3 requires the exact-case substring "Use when" — house grammar by
#     design, not a general NLP check.
#   - Gate 6 (backticked skill cross-refs) only fires on this repo's
#     "Boundary with other skills" bullet convention (`- **`name`**: ...`),
#     never on a bare backticked hyphenated token anywhere in the body.
#     A body-wide heuristic was tried and false-positived on real content:
#     `flowchart`, `qa`, `needs-triage`, `graph-token`, `mcp-sonarqube`,
#     `simplify`, `tracer-bullets`, `prd-to-plan`, `plan-from-prd` — none of
#     those are skill references, they're diagram types, label strings, a
#     script name, an external repo name, and upstream-only skill names
#     explicitly documented as "not vendored here".
#   - The total-description-char-count line is informational only, by
#     decision (Clemens dropped enforcing a repo-wide catalog budget).
#   - Descriptions under 80 chars are a WARN, never a gate, by decision.
#
# Waivers: <waivers-file>, one "<skill-name> <gate-id> # reason" per line.
# A waived (skill, gate) failure prints as "WAIVED: ..." and does not affect
# the exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DIRS=()
WAIVERS_ARG=""
WAIVERS_EXPLICIT=0
CONF_ARGS=()
CONF_EXPLICIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --waivers)
      WAIVERS_ARG="$2"
      WAIVERS_EXPLICIT=1
      shift 2
      ;;
    --waivers=*)
      WAIVERS_ARG="${1#--waivers=}"
      WAIVERS_EXPLICIT=1
      shift
      ;;
    --conf)
      CONF_ARGS+=("$2")
      CONF_EXPLICIT=1
      shift 2
      ;;
    --conf=*)
      CONF_ARGS+=("${1#--conf=}")
      CONF_EXPLICIT=1
      shift
      ;;
    *)
      DIRS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#DIRS[@]} -eq 0 ]]; then
  echo "usage: $0 <skill-parent-dir> [<skill-parent-dir> ...] [--waivers <path>] [--conf <path>]..." >&2
  exit 1
fi

if [[ "$WAIVERS_EXPLICIT" -eq 0 ]]; then
  WAIVERS_ARG="${SCRIPT_REPO_ROOT}/scripts/lint-skills.waivers"
fi

if [[ ${#CONF_ARGS[@]} -eq 0 ]]; then
  CONF_ARGS=(
    "${SCRIPT_REPO_ROOT}/install.conf.yaml"
    "${SCRIPT_REPO_ROOT}/dotfiles-mic/install.conf.yaml"
  )
fi

python3 - "$WAIVERS_EXPLICIT" "$WAIVERS_ARG" "$CONF_EXPLICIT" "${#CONF_ARGS[@]}" "${CONF_ARGS[@]}" "${DIRS[@]}" <<'PYEOF'
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

waivers_explicit = sys.argv[1] == "1"
waivers_file = sys.argv[2]
conf_explicit = sys.argv[3] == "1"
n_conf = int(sys.argv[4])
conf_paths = sys.argv[5:5 + n_conf]
parent_dirs = sys.argv[5 + n_conf:]

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
LINK_RE = re.compile(r"~/\.(?:claude|codex)/skills/([A-Za-z0-9_-]+)\s*:")
DESC_LITERAL_RE = re.compile(r"^description:\s*\|", re.MULTILINE)
REL_REF_RE = re.compile(r"(?<![\w/])(?:references|scripts|assets)/[A-Za-z0-9_./-]+")
MD_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
FENCE_OPEN_RE = re.compile(r"^(`{3,}|~{3,})")
SKILL_BULLET_RE = re.compile(r"^-\s*\*\*`([a-z0-9]+(?:-[a-z0-9]+)*)`\*\*:")
USE_WHEN_RE = re.compile(r"Use when")


def load_conf_names(path_str):
    path = Path(path_str)
    if not path.is_file():
        return None
    names = set()
    for m in LINK_RE.finditer(path.read_text(encoding="utf-8")):
        names.add(m.group(1))
    return names


def load_waivers(path_str):
    path = Path(path_str)
    if not path.is_file():
        return set()
    waived = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        parts = stripped.split()
        if len(parts) != 2:
            continue
        waived.add((parts[0], parts[1]))
    return waived


def scan_fences(text):
    """Blank out fenced code-block lines (inclusive of the fence markers) so
    file-reference gates only see prose/markdown, never template examples
    living inside a fence. Follows CommonMark: a fence opens with 3+ of the
    same character (backtick or tilde) and closes only on a line containing
    just that same character repeated at least as many times. Returns
    (stripped_text, ended_inside_an_open_fence)."""
    out_lines = []
    fence_char = None
    fence_len = 0
    for line in text.splitlines():
        stripped = line.strip()
        if fence_char is None:
            m = FENCE_OPEN_RE.match(stripped)
            if m:
                fence_char = m.group(1)[0]
                fence_len = len(m.group(1))
                out_lines.append("")
                continue
            out_lines.append(line)
        else:
            m = re.match(r"^(`{3,}|~{3,})\s*$", stripped)
            if m and stripped[0] == fence_char and len(m.group(1)) >= fence_len:
                fence_char = None
                fence_len = 0
            out_lines.append("")
    return "\n".join(out_lines), fence_char is not None


findings = []  # (skill_name, gate_id, message)
global_errors = []  # not associated with a single skill; never waivable
warnings = []
total_desc_chars = 0
linted_count = 0

if waivers_explicit and not Path(waivers_file).is_file():
    global_errors.append(f"ERROR: --waivers path '{waivers_file}' does not exist")
    waivers = set()
else:
    waivers = load_waivers(waivers_file)

conf_name_sets = []  # (path, names)
for conf_path in conf_paths:
    names = load_conf_names(conf_path)
    if names is None:
        if conf_explicit:
            global_errors.append(f"ERROR: --conf path '{conf_path}' does not exist")
        else:
            warnings.append(f"WARN: install.conf.yaml not found at {conf_path}; skill cross-refs against it are skipped")
        continue
    conf_name_sets.append((conf_path, names))

known_names = set()
for i, (path_a, names_a) in enumerate(conf_name_sets):
    known_names |= names_a
    for path_b, names_b in conf_name_sets[i + 1:]:
        dup = names_a & names_b
        if dup:
            global_errors.append(
                f"ERROR: duplicate skill name(s) declared in both {path_a} and {path_b}: {sorted(dup)}"
            )

for parent in parent_dirs:
    parent_path = Path(parent)
    if not parent_path.is_dir():
        global_errors.append(f"ERROR: {parent}: not a directory")
        continue

    for skill_dir in sorted(p for p in parent_path.iterdir() if p.is_dir()):
        dirname = skill_dir.name
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue

        linted_count += 1
        rel = str(skill_md)
        text = skill_md.read_text(encoding="utf-8")

        def err(gate_id, msg):
            findings.append((dirname, gate_id, f"ERROR: {rel}: {msg}"))

        if not text.startswith("---\n"):
            err("gate1", "missing frontmatter (must start with '---')")
            continue

        parts = text.split("\n---\n", 1)
        if len(parts) != 2:
            err("gate1", "frontmatter not terminated with '---'")
            continue

        fm_text = parts[0][4:]
        body = parts[1]

        try:
            fm = yaml.safe_load(fm_text)
        except yaml.YAMLError as exc:
            err("gate1", f"frontmatter does not parse as YAML: {exc}")
            continue

        if not isinstance(fm, dict):
            err("gate1", "frontmatter is not a mapping")
            continue

        # --- gate 1: spec validity -----------------------------------
        name = fm.get("name")
        if not isinstance(name, str) or not name:
            err("gate1", "frontmatter.name missing or not a string")
            name = ""
        if name != dirname:
            err("gate1", f"frontmatter.name '{name}' != directory name '{dirname}'")
        if name and not (1 <= len(name) <= 64):
            err("gate1", f"name length {len(name)} outside 1-64 chars")
        if name and not NAME_RE.match(name):
            err("gate1", f"name '{name}' must be lowercase alnum+hyphen, no leading/trailing/consecutive hyphens")

        description = fm.get("description")
        if not isinstance(description, str) or not description.strip():
            err("gate1", "frontmatter.description missing or empty")
            description = ""
        else:
            # YAML block scalars (">"/"|") commonly add a single trailing
            # newline via clip chomping; that's not an "embedded" newline.
            description = description.strip()
        if len(description) > 1024:
            err("gate1", f"description longer than 1024 chars ({len(description)})")

        metadata = fm.get("metadata")
        if metadata is not None:
            if not isinstance(metadata, dict) or not all(
                isinstance(k, str) and isinstance(v, str) for k, v in metadata.items()
            ):
                err("gate1", "metadata must be a string->string map")
                metadata = {}
        else:
            metadata = {}

        compatibility = fm.get("compatibility")
        if compatibility is not None and (not isinstance(compatibility, str) or not (1 <= len(compatibility) <= 500)):
            err("gate1", "compatibility must be a string 1-500 chars if present")

        allowed_tools = fm.get("allowed-tools")
        if allowed_tools is not None and not isinstance(allowed_tools, str):
            err("gate1", "allowed-tools must be a string if present")

        license_field = fm.get("license")
        if license_field is not None and not isinstance(license_field, str):
            err("gate1", "license must be a string if present")

        # --- gate 2: description length + no embedded newlines -------
        desc_len = len(description)
        total_desc_chars += desc_len
        if desc_len > 500:
            err("gate2", f"description {desc_len} chars, exceeds 500")
        if "\n" in description:
            err("gate2", "parsed description contains embedded newline(s)")

        # --- gate 3: 'Use when' sentence ------------------------------
        if not USE_WHEN_RE.search(description):
            err("gate3", "description has no 'Use when ...' sentence")

        # --- gate 4: body size ----------------------------------------
        body_lines = body.count("\n") + (1 if body and not body.endswith("\n") else 0)
        if body_lines > 500:
            err("gate4", f"body is {body_lines} lines, exceeds 500")
        est_tokens = len(body) / 4
        if est_tokens > 5000:
            err("gate4", f"body ~{int(est_tokens)} est. tokens, exceeds 5000")

        # --- gate 5: relative file refs + balanced code fences --------
        # Only markdown links [x](path) and references/scripts/assets paths
        # OUTSIDE fenced code blocks are checkable file references. Content
        # inside a fence is template/example material, not a real
        # same-skill-dir file reference.
        body_no_fences, unterminated_fence = scan_fences(body)
        refs = set(REL_REF_RE.findall(body_no_fences))
        for link_target in MD_LINK_RE.findall(body_no_fences):
            if link_target.startswith(("http://", "https://", "#")):
                continue
            refs.add(link_target)

        for ref in sorted(refs):
            ref_clean = ref.split("#", 1)[0]
            if not ref_clean:
                continue
            if not (skill_dir / ref_clean).exists():
                err("gate5", f"referenced file '{ref_clean}' does not exist")

        if unterminated_fence:
            err("gate5", "unterminated code fence (opening fence never closed)")

        # --- gate 6: backticked skill-name cross-refs ------------------
        # Only the repo's "Boundary with other skills" bullet convention
        # (`- **`name`**: ...`) is treated as a skill cross-reference; see
        # the deliberate-narrowings note at the top of this file.
        if known_names:
            for line in body.splitlines():
                m = SKILL_BULLET_RE.match(line.strip())
                if not m:
                    continue
                candidate = m.group(1)
                if candidate == name or candidate in known_names:
                    continue
                err(
                    "gate6",
                    f"backticked skill reference `{candidate}` does not resolve "
                    "against install.conf.yaml skill names",
                )

        # --- gate 7: metadata.category ----------------------------------
        category = metadata.get("category")
        if category not in ("capability", "preference"):
            err("gate7", f"metadata.category must be 'capability' or 'preference' (got {category!r})")

        # --- warnings -----------------------------------------------------
        if 0 < desc_len < 80:
            warnings.append(f"WARN: {rel}: description is short ({desc_len} chars, <80)")
        if DESC_LITERAL_RE.search(fm_text):
            warnings.append(f"WARN: {rel}: description uses literal '|' block scalar; prefer folded '>'")

        other_files = [p for p in skill_dir.rglob("*") if p.is_file() and p != skill_md]
        for f in other_files:
            relpath = f.relative_to(skill_dir).as_posix()
            if relpath not in body and f.name not in body:
                warnings.append(f"WARN: {rel}: file '{relpath}' is never referenced from SKILL.md")

for w in warnings:
    print(w, file=sys.stderr)

hard_errors = 0
for skill_name, gate_id, message in findings:
    if (skill_name, gate_id) in waivers:
        print(f"WAIVED: {message[len('ERROR: '):]}")
    else:
        print(message)
        hard_errors += 1

for e in global_errors:
    print(e)
    hard_errors += 1

print(f"INFO: linted {linted_count} skill(s); total description chars = {total_desc_chars}")

if hard_errors:
    sys.exit(1)
sys.exit(0)
PYEOF
