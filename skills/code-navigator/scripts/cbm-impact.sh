#!/usr/bin/env bash
# Maps the current uncommitted git diff to impacted symbols.
# Run from a normal clone (NOT a git worktree — known upstream bug).
#
# Field-verified 2026-07-20 on RuoYi-Vue-Plus: detect_changes's real response
# keys are `changed_files`/`changed_count`/`depth`/`impacted_symbols` -- there
# is no `summary` field and no per-symbol `risk` field (this endpoint has no
# --risk-labels flag at all, unlike trace_path, which does). The previous
# version of this script asked for both anyway, so they were always null --
# looked like a feature that silently never worked, rather than a field that
# was never there. Fixed to report only what actually exists.
# Code-review finding (2026-07-21): this used to reconstruct a brand-new
# output object unconditionally, so a cbm_call() error object (backend down,
# malformed request) was silently discarded and replaced with an
# empty-looking "no impacted symbols" result — indistinguishable from a real
# "no uncommitted changes" answer. Now passes `.error` through untouched.
set -euo pipefail; source "$(dirname "$0")/_project.sh"
cbm_call detect_changes "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq 'if (.error != null) then . else {changedFiles: (.changed_files // []), changedCount: (.changed_count // 0),
         impacted: [(.impacted_symbols // [])[] | {name, label: (.label // null), file: (.file_path // .file // null)}][:30],
         hint: (if ((.impacted_symbols // [])|length)==0 then "empty — are you in a git worktree? (upstream bug) or no uncommitted changes; use cbm-trace.sh inbound on the touched function instead" else null end)} end'
