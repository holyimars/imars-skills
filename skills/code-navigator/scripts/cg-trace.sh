#!/usr/bin/env bash
# Usage: cg-trace.sh <exact-symbol> [in|out|both] [limit]
#
# Bridges the Java interface->impl gap on the inbound direction (field-
# verified, see references/codegraph-blindspots.md): codegraph's `callers` is a single
# hop, so querying callers of an *Impl method surfaces only the interface's
# own declaration line, not the real business callers. When that exact shape
# is detected — a direct caller whose name equals the queried method's own
# short name — this script re-queries callers of that bridge symbol and
# unions the results, flagging bridged:true so the union can still be
# spot-checked (it is a heuristic, not a proof).
# Outbound (callees) is NOT affected by this gap and is passed through as-is.
#
# Limit handling (field-verified 2026-07-18, see references/codegraph-blindspots.md):
# `codegraph callers`/`callees` themselves default to -l 20 with NO total/hasMore
# field in their JSON — a symbol with >20 real callers silently returns only 20,
# indistinguishable from "there are exactly 20". This script used to call both
# with no -l at all, inheriting that cap unconditionally. On a Laravel repo, a
# frequently-injected repository interface method returned 20 callers by default
# and 43 with -l 200 — the missing 23 were real production call sites, not noise.
# Fixed by defaulting to a much higher cap here, and by flagging when a fetch
# returns exactly LIMIT results (the one observable signal that more may exist).
#
# Regression audit (2026-07-19): $1 was referenced with no guard -- confirmed
# live to crash with `set -u`'s unbound-variable error and zero stdout on a
# no-args call, the same defect class fixed this session on the cbm-* side.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
[ "$#" -ge 1 ] || { echo '{"error":"exact-symbol (positional arg) is required","hint":"usage: cg-trace.sh <exact-symbol> [in|out|both] [limit]"}'; exit 2; }
NAME="$1"; DIRRAW="${2:-both}"; LIMIT="${3:-200}"
_require_positive_int "$LIMIT" "limit (3rd arg)"
case "$DIRRAW" in in) DIR=in;; out) DIR=out;; *) DIR=both;; esac
# Bridge fingerprint = the bare method short name. Prefer splitting on the
# LAST "::" (codegraph's own qualifiedName separator) so this still works
# when NAME is a full qualifiedName whose namespace segment contains dots
# (e.g. "org.dromara.x.impl::FooServiceImpl::bar" — splitting on "." alone
# would cut inside "org.dromara.x.impl" instead of at the "::"). Only fall
# back to splitting on "." for the plain "Class.method" shorthand that has
# no "::" at all.
case "$NAME" in
  *::*) SHORTNAME="${NAME##*::}" ;;
  *)    SHORTNAME="${NAME##*.}" ;;
esac

fetch_callers() { cg_call callers "$1" -j -l "$LIMIT"; }
fetch_callees() { cg_call callees "$1" -j -l "$LIMIT"; }
at_cap() { [ "$(echo "$1" | jq --arg k "$2" '(.[$k] // [])|length')" -ge "$LIMIT" ]; }

trace_in() {
  local direct merged bridge_via candidates count i cand fp sl qn bridged_result any_at_cap
  direct=$(fetch_callers "$NAME")
  any_at_cap=false; at_cap "$direct" callers && any_at_cap=true
  merged="$direct"
  bridge_via='[]'

  candidates=$(echo "$direct" | jq -c --arg sn "$SHORTNAME" '[(.callers // [])[] | select(.name == $sn)]')
  count=$(echo "$candidates" | jq 'length')
  i=0
  while [ "$i" -lt "$count" ]; do
    cand=$(echo "$candidates" | jq -c ".[$i]")
    fp=$(echo "$cand" | jq -r '.filePath')
    sl=$(echo "$cand" | jq -r '.startLine')
    qn=$(cg_call query "$SHORTNAME" -k method -j -l 50 \
      | jq -r --arg fp "$fp" --argjson sl "$sl" \
        'if type=="array" then ([.[] | select(.node.filePath == $fp and .node.startLine == $sl)][0].node.qualifiedName // empty) else empty end')
    if [ -n "${qn:-}" ]; then
      bridged_result=$(fetch_callers "$qn")
      at_cap "$bridged_result" callers && any_at_cap=true
      merged=$(jq -n --argjson a "$merged" --argjson b "$bridged_result" '
        { symbol: $a.symbol,
          callers: (($a.callers // []) + ($b.callers // []) | unique_by(.filePath + ":" + (.startLine|tostring))) }')
      bridge_via=$(echo "$bridge_via" | jq --arg qn "$qn" '. + [$qn]')
    fi
    i=$((i+1))
  done

  echo "$merged" | jq --argjson via "$bridge_via" --argjson cap "$any_at_cap" \
    '. + {bridgedVia: $via, bridged: (($via|length) > 0), possiblyTruncated: $cap}'
}

trace_out() {
  local out at_cap_flag
  out=$(fetch_callees "$NAME")
  at_cap_flag=false; at_cap "$out" callees && at_cap_flag=true
  echo "$out" | jq --argjson cap "$at_cap_flag" '. + {bridged: false, bridgedVia: [], possiblyTruncated: $cap}'
}

case "$DIR" in
  in)   RESULT=$(trace_in | jq --arg name "$NAME" '{symbol: $name, direction: "in", callers: (.callers // []), bridged, bridgedVia, possiblyTruncated, error}');;
  out)  RESULT=$(trace_out | jq --arg name "$NAME" '{symbol: $name, direction: "out", callees: (.callees // []), bridged, bridgedVia, possiblyTruncated, error}');;
  both) IN=$(trace_in); OUT=$(trace_out)
        RESULT=$(jq -n --arg name "$NAME" --argjson i "$IN" --argjson o "$OUT" \
          '{symbol: $name, direction: "both", callers: ($i.callers // []), callees: ($o.callees // []), bridged: $i.bridged, bridgedVia: $i.bridgedVia, possiblyTruncated: (($i.possiblyTruncated // false) or ($o.possiblyTruncated // false)), error: ($i.error // $o.error)}');;
esac

# Code-review finding (2026-07-21): possiblyTruncated and bridged are NOT
# mutually exclusive — a result can be both auto-bridged through an
# interface hop AND truncated at the limit — but the elif chain used to
# treat them as if only one could be true at a time, silently dropping
# whichever warning lost the elif race. Now collects whichever apply via
# join_warnings(), shared with cbm-find.sh's semantic branch in _hint.jq.
HINTDEFS=$(cat "$(dirname "$0")/_hint.jq")
echo "$RESULT" | jq --arg limit "$LIMIT" "$HINTDEFS"'. + {hint: (
  if (.error != null) then ("codegraph error: " + .error)
  elif (((.callers // []) + (.callees // []))|length) == 0
    then "0 results — the name must be EXACT: run cg-find.sh first and copy the exact name"
  else join_warnings([
      (if (.possiblyTruncated // false) then ("hit the query limit (" + $limit + ") — there may be MORE real callers/callees beyond what is shown; re-run with a higher limit as the 3rd arg, e.g. cg-trace.sh <symbol> " + (.direction // "both") + " 500, before treating this count as complete") else empty end),
      (if (.bridged // false) then "auto-bridged through an interface declaration hop — verify the union with cg-node.sh or cg-explore.sh before concluding a caller count" else empty end)
    ])
  end)}'
