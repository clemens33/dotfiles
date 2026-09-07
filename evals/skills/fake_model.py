#!/usr/bin/env python3
"""Deterministic fake model for the eval-skills self-test.

Reads the full prompt on stdin, prints a reply on stdout. It proves the
PIPELINE (prompt assembly, argv safety, timeouts, output parsing, verdicts,
result files) and nothing about any real model: keyword lookup is not
routing quality. Never use its output as evidence about a catalog.

Modes (env EVAL_FAKE_MODE, default "route"):
  route        keyword table -> {"select": [...]}; task prompts get canned answers
  malformed    prose without any JSON object
  empty        no output at all
  hang         sleep 30s (exercise --timeout)
  exit3        exit with status 3 after printing a valid reply
  claude-json  wrap the reply in a `claude -p --output-format json` envelope
  codex-jsonl  wrap the reply in `codex exec --json` event lines
  bad-python   task reply carries a python fence that does not parse
  gnu-date     task reply carries a bash fence using GNU-only `date -d`
  claude-stream emit `claude -p --output-format stream-json` events with one Skill tool call (native-check parser)

EVAL_FAKE_DUMP=<path>  also write the received prompt to <path> verbatim.
EVAL_FAKE_MODEL_ID=<id> served model id reported in the claude-json envelope (default fake-model-1);
                       simulates an alias fallback that argv alone cannot detect.
"""
import json
import os
import re
import sys
import time

ROUTE_TABLE = [
    # (regex over the user request, names to add). Order = output order.
    (r"\badr\b", ["adr"]),
    (r"mermaid|\.md\b|renders on github|docs/", ["viz"]),
    (r"\.drawio|gantt|org chart|slides|deck", ["drawio-diagrams-enhanced"]),
    (r"grafana|loki|otel|error rate", ["grafana-agent"]),
    (r"langfuse", ["langfuse-debug"]),
    (r"smoke test", ["assistant-test"]),
    (r"mcp server|fastmcp", ["mcp-server"]),
    (r"promote .* skill|as a reusable skill|save .* skill", ["manage-skills"]),
    (r"split it|lint body budget|compress", ["skill-reducer"]),
    (r"failing|slower|find the cause", ["diagnose"]),
    (r"create an issue|needs-triage", ["triage"]),
    (r"agent skills", ["setup-matt-pocock-skills"]),
    (r"FAKE_STRAY", ["caveman"]),
    (r"FAKE_FORBIDDEN", ["grafana-agent"]),
]

PY_OK = '''```python
from fastmcp import FastMCP

mcp = FastMCP("demo")


@mcp.tool
def ping() -> str:
    """Liveness check."""
    return "pong"


if __name__ == "__main__":
    mcp.run()
```'''

PY_BAD = '''```python
from fastmcp import FastMCP
mcp = FastMCP("demo"
def ping(:
    return "pong"
```'''

BASH_PORTABLE = '''```bash
END=$(date +%s)
START=$((END - 7200))
curl -sS -H "Authorization: Bearer $GRAFANA_TOKEN" \\
  "$GRAFANA_URL/api/datasources/proxy/uid/ds-emea-prod-loki/loki/api/v1/query_range?query=%7Bnamespace%3D%22ai-shared-prod%22%7D&start=${START}000000000&end=${END}000000000&limit=20"
```'''

BASH_GNU = '''```bash
START=$(date -d '2 hours ago' +%s)000000000
curl -sS "$GRAFANA_URL/api/datasources/proxy/uid/ds-emea-prod-loki/loki/api/v1/query_range?query=LOGQL&start=$START&limit=20"
```'''


def user_request(prompt):
    m = re.search(r"User request:\n(.*?)\n\nReply with", prompt, re.S)
    return m.group(1) if m else ""


def task_text(prompt):
    m = re.search(r"\nTask:\n(.*)\Z", prompt, re.S)
    return m.group(1) if m else None


def route_reply(prompt):
    req = user_request(prompt)
    picks = []
    for pattern, names in ROUTE_TABLE:
        if re.search(pattern, req, re.I):
            for n in names:
                if n not in picks:
                    picks.append(n)
    return "Routing decision follows.\n" + json.dumps({"select": picks})


def task_reply(task, mode):
    low = task.lower()
    if "fastmcp" in low or "mcp server" in low:
        return "Here is the module.\n\n" + (PY_BAD if mode == "bad-python" else PY_OK)
    if "frontmatter" in low or "lint" in low:
        return ("A new skill needs `metadata.category` (capability or preference) in the "
                "frontmatter besides name and description, and the per-skill symlink is "
                "declared in install.conf.yaml.")
    if "loki" in low or "grafana" in low:
        return "Portable window:\n\n" + (BASH_GNU if mode == "gnu-date" else BASH_PORTABLE)
    return "I do not know this task."


def main():
    mode = os.environ.get("EVAL_FAKE_MODE", "route")
    prompt = sys.stdin.read()
    dump = os.environ.get("EVAL_FAKE_DUMP")
    if dump:
        with open(dump, "w", encoding="utf-8") as fh:
            fh.write(prompt)
    if mode == "hang":
        time.sleep(30)
        return 0
    if mode == "empty":
        return 0
    if mode == "malformed":
        sys.stdout.write("I would probably load viz here, but I am not sure.\n")
        return 0
    if mode == "claude-stream":
        picks = []
        for pattern, names in ROUTE_TABLE:
            if re.search(pattern, prompt, re.I):
                picks.extend(n for n in names if n not in picks)
        events = [{"type": "system", "subtype": "init", "model": "fake-model-1", "tools": ["Skill"],
                   "skills": ["viz", "adr"], "version": "0.0.0"}]
        events.append({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Skill", "input": {"skill": n}} for n in picks]}})
        events.append({"type": "result", "subtype": "success", "result": "ok", "total_cost_usd": 0.0001,
                       "usage": {"input_tokens": 500, "output_tokens": 9}})
        sys.stdout.write("".join(json.dumps(e) + "\n" for e in events))
        return 0
    task = task_text(prompt)
    reply = task_reply(task, mode) if task is not None else route_reply(prompt)
    if mode == "claude-json":
        envelope = {
            "type": "result", "subtype": "success", "is_error": False,
            "duration_ms": 7, "num_turns": 1, "result": reply,
            "total_cost_usd": 0.000123,
            "usage": {"input_tokens": 1234, "output_tokens": 21,
                      "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            "modelUsage": {os.environ.get("EVAL_FAKE_MODEL_ID", "fake-model-1"): {"inputTokens": 1234, "outputTokens": 21}},
        }
        sys.stdout.write(json.dumps(envelope) + "\n")
    elif mode == "codex-jsonl":
        lines = [
            {"type": "thread.started", "thread_id": "fake-thread"},
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"id": "item_0", "type": "agent_message", "text": reply}},
            {"type": "turn.completed", "usage": {"input_tokens": 1234, "cached_input_tokens": 0, "output_tokens": 21}},
        ]
        sys.stdout.write("".join(json.dumps(l) + "\n" for l in lines))
    else:
        sys.stdout.write(reply + "\n")
    sys.stdout.flush()
    if mode == "exit3":
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
