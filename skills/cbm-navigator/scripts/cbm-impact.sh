#!/usr/bin/env bash
# Maps the current uncommitted git diff to impacted symbols + risk.
# Run from a normal clone (NOT a git worktree — known upstream bug).
set -euo pipefail; source "$(dirname "$0")/_project.sh"
cbm_call detect_changes "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq '{summary: (.summary // null), impacted: [((.impacted_symbols // .results // [])[]) | {name, file: (.file_path // .file // null), risk: (.risk // null)}][:30],
         hint: (if ((.impacted_symbols // .results // [])|length)==0 then "empty — are you in a git worktree? (upstream bug) or no uncommitted changes; use cbm-trace.sh inbound on the touched function instead" else null end)}'
