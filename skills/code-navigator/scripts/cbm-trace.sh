#!/usr/bin/env bash
# Usage: cbm-trace.sh <exact-function-name> [in|out|both] [depth]
set -euo pipefail; source "$(dirname "$0")/_project.sh"
NAME="$1"; DIRRAW="${2:-both}"; DEPTH="${3:-3}"
case "$DIRRAW" in in) DIR=inbound;; out) DIR=outbound;; *) DIR=both;; esac
# NOTE: depth param name per current schema; confirm via `cli get_graph_schema` if a release renames it.
ARGS=$(jq -n --arg p "$PROJECT" --arg n "$NAME" --arg d "$DIR" --argjson dep "$DEPTH" \
  '{project:$p, function_name:$n, direction:$d, depth:$dep}')
OUT=$(cbm_call trace_path "$ARGS")
echo "$OUT" | jq '. + {hint: (if ((.paths // .results // [])|length)==0
  then "0 paths — the name must be EXACT: run cbm-find.sh first and copy the exact name (official troubleshooting guidance)"
  else null end)}'
