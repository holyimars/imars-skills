#!/usr/bin/env bash
# Shared checks sourced by every cg-* script:
# 1. the codegraph CLI must be installed.
# 2. the repo root must already have a .codegraph/ index (codegraph resolves
#    per-directory via -p/cwd — there is no named project registry like
#    codebase-memory-mcp's, so "not indexed" is a hard stop, not a lookup miss).
# 3. tiny-repo reminder via `codegraph status` nodeCount (skill gate rule).
set -euo pipefail
source "$(dirname "$0")/_json_safe.sh"

command -v codegraph >/dev/null || {
  echo '{"error":"codegraph CLI not found","hint":"install: npm i -g @colbymchenry/codegraph — do NOT run \"codegraph install\" unless you intend to write MCP config into this agent"}' >&2
  exit 2
}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [ ! -d "$ROOT/.codegraph" ]; then
  echo "{\"error\":\"repo not indexed for codegraph\",\"hint\":\"run: codegraph init '$ROOT' — or if this repo has a .codebase-memory/ directory instead, use this skill's cbm-* scripts instead (same skill, different index)\"}" >&2
  exit 2
fi

STATUS=$(codegraph status "$ROOT" -j 2>/dev/null || echo '{}')
NODES=$(echo "$STATUS" | jq -r '.nodeCount // empty' 2>/dev/null || true)
if [ -n "${NODES:-}" ] && [ "$NODES" -lt 500 ] 2>/dev/null; then
  echo "warning: this repo has only $NODES graph nodes (likely <1k LOC) — per skill gate, prefer native grep/read" >&2
fi

ADDED=$(echo "$STATUS" | jq -r '.pendingChanges.added // 0' 2>/dev/null || echo 0)
MODIFIED=$(echo "$STATUS" | jq -r '.pendingChanges.modified // 0' 2>/dev/null || echo 0)
REMOVED=$(echo "$STATUS" | jq -r '.pendingChanges.removed // 0' 2>/dev/null || echo 0)
if [ "$((ADDED + MODIFIED + REMOVED))" -gt 0 ] 2>/dev/null; then
  echo "warning: index is stale ($ADDED added, $MODIFIED modified, $REMOVED removed files pending) — run 'codegraph sync' first if the question is about recent changes" >&2
fi

export CG_ROOT="$ROOT"

# Unified CLI invocation that always returns valid JSON. Field-verified gap:
# `codegraph callers/callees/impact` report "symbol not found" via EXIT CODE
# 0 plus a human-readable, ANSI-colored line on STDOUT (not stderr, not
# JSON) -- unlike `query`/`files`/`status`/`affected`, which return valid
# JSON (or a valid empty `[]`/`{}`) even on no-match. A bare
# `2>/dev/null || echo fallback` never catches this (exit code is 0), so
# that stray text used to reach jq directly and crash it. This wrapper
# actually PARSES stdout with `jq empty` rather than eyeballing the first
# character (that "not found" text starts with a literal "[i]" info-icon
# prefix, which would false-positive a naive '['*/'{'* prefix check): valid
# JSON passes through untouched, anything else (that message, or a genuine
# crash) becomes a structured `{"error": "...", "exitCode": N}` object so
# callers can always safely pipe the result into jq.
# Plausible (NOT independently confirmed) reason this gap exists: upstream's
# CLAUDE.md documents a "return a SUCCESS-shaped response with guidance
# instead of isError" design principle using MCP-protocol terms
# (ToolHandler.execute, tools/list, textResult) -- read as scoped to the MCP
# server path, not the standalone CLI this skill calls (`codegraph install`
# is deliberately never run here). We could not test an actual MCP session
# to confirm the CLI truly falls outside that guarantee, so treat this as
# background context, not the basis for the fix -- the fix rests entirely on
# the byte-verified CLI behavior above. See references/codegraph-blindspots.md.
cg_call() {
  local out err status msg
  err=$(mktemp)
  set +e
  out=$(codegraph "$@" 2>"$err")
  status=$?
  set -e
  # Validate by actually parsing, not by eyeballing the first character:
  # codegraph's own "not found" text starts with a literal "[i]" prefix
  # (its info-icon, not an ANSI bracket), which would false-positive a
  # naive '['*/'{'* prefix check into looking like valid JSON. The
  # non-empty-then-jq-empty predicate itself lives in _json_safe.sh, shared
  # with cbm_call() (_project.sh) -- see that file for why it must be a
  # separate non-empty check rather than `jq empty` alone.
  if _is_valid_json_answer "$out"; then
    printf '%s' "$out"
  else
    msg=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')
    [ -z "$msg" ] && msg=$(sed 's/\x1b\[[0-9;]*m//g' "$err")
    [ -z "$msg" ] && msg="codegraph $* exited $status with no output"
    jq -cn --arg m "$msg" --argjson s "$status" '{error: $m, exitCode: $s}'
  fi
  rm -f "$err"
}
