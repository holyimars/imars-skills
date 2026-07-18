#!/usr/bin/env bash
# Usage: cg-impact.sh <exact-symbol> [depth]
# Multi-hop traversal (default depth 2) — unlike cg-trace.sh's single-hop
# callers, this already walks through the Java interface/impl bridge on its
# own (field-verified), so no extra bridging logic is needed here.
#
# Regression audit (2026-07-19): $1 was referenced with no guard -- confirmed
# live to crash with `set -u`'s unbound-variable error and zero stdout on a
# no-args call, the same defect class fixed this session on the cbm-* side.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
[ "$#" -ge 1 ] || { echo '{"error":"exact-symbol (positional arg) is required","hint":"usage: cg-impact.sh <exact-symbol> [depth]"}'; exit 2; }
NAME="$1"; DEPTH="${2:-2}"
OUT=$(cg_call impact "$NAME" -j -d "$DEPTH")
echo "$OUT" | jq --arg name "$NAME" 'if has("error") then
    {symbol: $name, affected: [], hint: ("codegraph error: " + .error)}
  else . + {hint: (if ((.affected // [])|length)<=1
    then "only the symbol itself came back — the name must be EXACT (run cg-find.sh first), or raise depth, or this really has no dependents"
    else null end)}
  end'
