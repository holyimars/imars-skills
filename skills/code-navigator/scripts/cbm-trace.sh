#!/usr/bin/env bash
# Usage: cbm-trace.sh <exact-function-name> [in|out|both] [depth] [include-tests]
#
# Field-verified 2026-07-20 on RuoYi-Vue-Plus: trace_path's real response
# keys are `callers` (inbound) / `callees` (outbound) -- NEVER `paths` or
# `results`. The hint below used to test those two nonexistent keys, so it
# unconditionally reported "0 paths" on EVERY call regardless of the real
# result -- confirmed live: `isNotEmpty` inbound returned 83 real callers and
# this script's own hint still said "0 paths — the name must be EXACT".
# Fixed to count the fields that actually exist.
#
# `include_tests` defaults to false per the CLI's own documented default
# (test files are filtered out of callers/callees unless asked for) -- pass
# `true` as the 4th arg to include them. If a hand-derived grep ground truth
# counts test-file callers too, this default will look like an under-recall
# that isn't really the tool's fault; the hint below flags this whenever the
# default is in effect and the result is non-empty.
#
# Regression audit (2026-07-19): this script referenced $1 directly with no
# guard, the exact bug already fixed this session in cbm-grep.sh/cbm-find.sh/
# cbm-snippet.sh but missed here -- confirmed live: calling with no args hit
# `set -u`'s unbound-variable trap and killed the script with zero stdout,
# not even a hint, before cbm_call() ever got a chance to run.
set -euo pipefail; source "$(dirname "$0")/_project.sh"
[ "$#" -ge 1 ] || { echo '{"error":"exact-function-name (positional arg) is required","hint":"usage: cbm-trace.sh <exact-function-name> [in|out|both] [depth] [include-tests]"}'; exit 2; }
NAME="$1"; DIRRAW="${2:-both}"; DEPTH="${3:-3}"; INCLUDE_TESTS="${4:-false}"
_require_positive_int "$DEPTH" "depth (3rd arg)"
case "$INCLUDE_TESTS" in
  true|false) ;;
  *) echo "{\"error\":\"include-tests (4th arg) must be 'true' or 'false', got '$INCLUDE_TESTS'\"}" >&2; exit 2 ;;
esac
case "$DIRRAW" in in) DIR=inbound;; out) DIR=outbound;; *) DIR=both;; esac
# NOTE: depth param name per current schema; confirm via `cli get_graph_schema` if a release renames it.
ARGS=$(jq -n --arg p "$PROJECT" --arg n "$NAME" --arg d "$DIR" --argjson dep "$DEPTH" --argjson t "$INCLUDE_TESTS" \
  '{project:$p, function_name:$n, direction:$d, depth:$dep, include_tests:$t}')
OUT=$(cbm_call trace_path "$ARGS")
# Code-review finding (2026-07-21): this used to unconditionally overwrite
# `.hint` via `. + {hint: ...}` even when cbm_call() had already recovered a
# real, specific error+hint from the CLI (e.g. a bad depth value, a downed
# backend) -- replacing it with the generic "name must be EXACT" text no
# matter what actually failed. `.error` itself survived (this merges with
# `.+`, it doesn't reconstruct the object), but the hint actively misled
# troubleshooting toward the wrong cause. Now short-circuits on `.error`.
echo "$OUT" | jq --argjson t "$INCLUDE_TESTS" 'if (.error != null) then . else . + {hint: (
  if (((.callers // []) + (.callees // []))|length)==0
    then "0 results — the name must be EXACT: run cbm-find.sh first and copy the exact name (official troubleshooting guidance)"
  elif ($t|not)
    then "include_tests=false (default): test-file callers/callees are excluded from this count. If comparing against a repo-wide grep that includes test files, re-run with `true` as the 4th arg (cbm-trace.sh <name> <dir> <depth> true) before concluding this is a recall gap"
  else null end)} end'
