#!/usr/bin/env bash
# MessageDisplay hook — prepends local [HH:MM] to each assistant message.
# Display-only: never touches the transcript or what the model sees.
#
# MessageDisplay fires once per streamed batch with a zero-based `index`;
# stamp only the first batch so the marker appears once per message.
# Contract: stdin JSON {index, delta, ...} ->
#   {hookSpecificOutput: {hookEventName, displayContent}}
set -euo pipefail

# Fail safe: without jq, emit nothing — Claude Code shows the original text.
command -v jq >/dev/null 2>&1 || exit 0

ts="$(date '+%H:%M')"
jq --arg ts "$ts" '
  if .index == 0 then
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: ("[" + $ts + "] " + .delta)}}
  else
    {hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: .delta}}
  end
'
