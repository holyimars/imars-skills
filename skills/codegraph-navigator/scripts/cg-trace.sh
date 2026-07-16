#!/usr/bin/env bash
# Usage: cg-trace.sh <exact-symbol> [in|out|both]
#
# Bridges the Java interface->impl gap on the inbound direction (field-
# verified, see references/blindspots.md): codegraph's `callers` is a single
# hop, so querying callers of an *Impl method surfaces only the interface's
# own declaration line, not the real business callers. When that exact shape
# is detected — a direct caller whose name equals the queried method's own
# short name — this script re-queries callers of that bridge symbol and
# unions the results, flagging bridged:true so the union can still be
# spot-checked (it is a heuristic, not a proof).
# Outbound (callees) is NOT affected by this gap and is passed through as-is.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
NAME="$1"; DIRRAW="${2:-both}"
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

fetch_callers() { cg_call callers "$1" -j; }
fetch_callees() { cg_call callees "$1" -j; }

trace_in() {
  local direct merged bridge_via candidates count i cand fp sl qn bridged_result
  direct=$(fetch_callers "$NAME")
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
      merged=$(jq -n --argjson a "$merged" --argjson b "$bridged_result" '
        { symbol: $a.symbol,
          callers: (($a.callers // []) + ($b.callers // []) | unique_by(.filePath + ":" + (.startLine|tostring))) }')
      bridge_via=$(echo "$bridge_via" | jq --arg qn "$qn" '. + [$qn]')
    fi
    i=$((i+1))
  done

  echo "$merged" | jq --argjson via "$bridge_via" '. + {bridgedVia: $via, bridged: (($via|length) > 0)}'
}

trace_out() {
  fetch_callees "$NAME" | jq '. + {bridged: false, bridgedVia: []}'
}

case "$DIR" in
  in)   RESULT=$(trace_in | jq --arg name "$NAME" '{symbol: $name, direction: "in", callers: (.callers // []), bridged, bridgedVia, error}');;
  out)  RESULT=$(trace_out | jq --arg name "$NAME" '{symbol: $name, direction: "out", callees: (.callees // []), bridged, bridgedVia, error}');;
  both) IN=$(trace_in); OUT=$(trace_out)
        RESULT=$(jq -n --arg name "$NAME" --argjson i "$IN" --argjson o "$OUT" \
          '{symbol: $name, direction: "both", callers: ($i.callers // []), callees: ($o.callees // []), bridged: $i.bridged, bridgedVia: $i.bridgedVia, error: ($i.error // $o.error)}');;
esac

echo "$RESULT" | jq '. + {hint: (
  if (.error != null) then ("codegraph error: " + .error)
  elif (((.callers // []) + (.callees // []))|length) == 0
    then "0 results — the name must be EXACT: run cg-find.sh first and copy the exact name"
  elif (.bridged // false)
    then "auto-bridged through an interface declaration hop — verify the union with cg-node.sh or cg-explore.sh before concluding a caller count"
  else null end)}'
