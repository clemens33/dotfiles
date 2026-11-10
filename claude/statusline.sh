#!/usr/bin/env bash
# Claude Code status line. Reads session JSON on stdin, prints one footer line.
# Fields: https://code.claude.com/docs/en/statusline
#
# Cost per render: exactly one jq process, plus one git process only when the
# per-cwd branch cache is missing, unreadable or older than 5 s, plus the
# backgrounded ae quota feed. Everything else is bash builtins (bash 3.2 is
# enough: /bin/bash on macOS), so no cat, basename, stat or date process starts.
# Claude Code renders this often per session, and with dozens of sessions every
# extra process start is scanned by the endpoint-security agent.
set -euo pipefail

# No cat process; trailing newlines are dropped as $(cat) dropped them.
IFS= read -r -d '' input || true
while [[ $input == *$'\n' ]]; do input=${input%$'\n'}; done

# Hand the payload to ae's Claude quota cache (CLAUDE_CONFIG_DIR picks the account).
# Backgrounded and silenced so a slow or missing ae never delays or breaks the footer.
if command -v ae >/dev/null 2>&1; then
  { printf '%s' "$input" | ae _quota-feed || true; } >/dev/null 2>&1 &
fi

# One jq call extracts every field. Fields are joined with the ASCII unit
# separator (a non-whitespace IFS character, so an empty field survives the
# split below). An absent, null or false value yields an empty field, which the
# line builder omits. rate_limits: Claude.ai Pro/Max, or a Claude apps gateway
# that sets a spend limit, and only after the first API response. Each window is
# dropped once its resets_at passes, so absence is handled per window rather than
# once. The gateway-only spend_limit window is deliberately not rendered.
# Extra fields feed the branch cache: the epoch second (jq `now`, so no date
# process) and a djb2 hash of the cwd (no cksum process). The final "." keeps
# the cwd, which may contain anything, from being the last field.
fields=$(printf '%s' "$input" | jq -r '
  def pct: if . == null or . == false then "" else floor | tostring end;
  (.workspace.current_dir // .cwd // "") as $cwd
  | [ (.model.display_name // "?"),
      (.effort.level // ""),
      (.context_window.used_percentage | pct),
      ((.cost.total_cost_usd // "") | tostring),
      ((.prompt_cache // {}) | if .warm == true then "warm" elif .warm == false then "cold" else "" end),
      (.rate_limits.five_hour.used_percentage | pct),
      (.rate_limits.seven_day.used_percentage | pct),
      (now | floor | tostring),
      ($cwd | explode | reduce .[] as $c (5381; (. * 33 + $c) % 4294967296) | tostring),
      $cwd,
      "." ]
  | join("\u001f")')

IFS=$'\037'
set -f
# shellcheck disable=SC2086  # the split on the unit separator is the point
set -- $fields
set +f
unset IFS
model=${1-} effort=${2-} context=${3-} cost=${4-} cache=${5-} five_h=${6-} seven_d=${7-}
now=${8-0} hash=${9-0} cwd=${10-}

# basename without the process: drop trailing slashes (a lone "/" stays "/").
dir=$cwd
while [[ ${#dir} -gt 1 && $dir == */ ]]; do dir=${dir%/}; done
[[ $dir == / ]] || dir=${dir##*/}

# Branch: `git rev-parse --abbrev-ref HEAD`, exactly as before (a detached HEAD
# and an unborn branch both print HEAD, a non-git cwd prints nothing). The result
# is cached for 5 s per cwd in ${TMPDIR:-/tmp}, so most renders start no git
# process. The cache file holds the epoch second, the cwd and the branch, one per
# line; the cwd line guards against a hash collision. A missing, unreadable,
# foreign, malformed or stale file falls back to the git call, and the fresh
# result replaces it through a temp file and a rename, so a reader never sees a
# partial file. An empty cwd makes git use the process directory, so it is not cached.
branch=
if [ -z "$cwd" ]; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
else
  cache_dir=${TMPDIR:-/tmp}
  cache_file=${cache_dir%/}/claude-statusline-$UID-$hash
  hit=
  if [ -O "$cache_file" ] && [ ! -L "$cache_file" ] && { IFS= read -r c_time && IFS= read -r c_cwd && IFS= read -r c_branch; } 2>/dev/null <"$cache_file"; then
    case $c_time in
      '' | *[!0-9]* | ????????????*) ;;
      *)
        age=$((10#$now - 10#$c_time))  # 10#: a leading zero would parse as octal
        if [ "$c_cwd" = "$cwd" ] && [ "$age" -ge 0 ] && [ "$age" -lt 5 ]; then
          branch=$c_branch
          hit=1
        fi
        ;;
    esac
  fi
  if [ -z "$hit" ]; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    # noclobber: the temp file is created exclusively (O_EXCL), so a file or symlink
    # that already sits at the predictable name makes the write fail instead of
    # being followed (shared /tmp fallback); the render then just skips the cache.
    tmp=$cache_file.$$
    set -C
    if printf '%s\n%s\n%s\n' "$now" "$cwd" "$branch" 2>/dev/null >"$tmp"; then
      mv "$tmp" "$cache_file" 2>/dev/null || rm "$tmp" 2>/dev/null || true
    fi
    set +C
  fi
fi

line="🧠 ${model}"
[ -n "$effort" ] && line="${line} (${effort})"
line="${line}  📁 ${dir}"
[ -n "$branch" ] && line="${line}  🌿 ${branch}"
[ -n "$context" ] && line="${line}  ctx ${context}%"
if [ -n "$cost" ]; then
  LC_NUMERIC=C printf -v cost '$%.2f' "$cost"
  line="${line}  ${cost}"
fi
[ -n "$cache" ] && line="${line}  cache ${cache}"
[ -n "$five_h" ] && line="${line}  5h ${five_h}%"
[ -n "$seven_d" ] && line="${line}  7d ${seven_d}%"

printf '%s' "$line"
