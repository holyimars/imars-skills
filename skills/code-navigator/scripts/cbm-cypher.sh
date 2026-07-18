#!/usr/bin/env bash
# Usage: cbm-cypher.sh dead-code|dead-code-methods|cross-layer|hubs|routes  [arg1] [arg2]
#
# Field-verified 2026-07-17 on RuoYi-Vue-Plus. This template set had 6 real
# issues found this pass (see references/cbm-blindspots.md for full repro) — 5
# fixed, 1 documented because it can't be fixed at the query level:
#
# 1. `hubs`: FIXED. The original query ordered by `c.degree`, a property
#    that DOES NOT EXIST on Class nodes (confirmed via `keys(c)` — schema is
#    name/qualified_name/label/file_path/start_line/end_line, no degree) —
#    so the old ORDER BY was a silent no-op and the "top 20 hubs" were
#    effectively return-order noise (a plain domain VO and a test-only class
#    outranked every real utility class). Fixed by aggregating real inbound
#    CALLS across each class's methods instead of querying a nonexistent
#    property or counting constructor calls only (the naive
#    `(c:Class)<-[:CALLS]-()` rewrite undercounts badly: CALLS edges into a
#    Class node are constructor invocations only, `obj.method()` calls
#    attach to the Method node, not the Class). Verified: this fixed query
#    surfaces StringUtils/R/LoginHelper/BaseMapperPlus/StreamUtils — the
#    actual most-used utility/base classes in this codebase, a highly
#    plausible top-20 versus the old query's arbitrary-looking list.
# 2. `cross-layer`: FIXED. The default (zero-arg) invocation hard-failed
#    with `unexpected operator at pos 38` on EVERY call — this Cypher
#    engine rejects `coalesce(...)` used inside a `WHERE ... CONTAINS`
#    clause (confirmed: coalesce works fine in RETURN, and a plain
#    `a.file_path CONTAINS '...'` WHERE clause works fine — the combination
#    of the two is what breaks the parser). Fixed by dropping coalesce()
#    from WHERE only (kept in RETURN for display); also confirmed via a
#    NULL-check that `file_path` is populated on 100% of Method/Function
#    nodes in this repo, so coalesce's fallback to `.file` was dead weight
#    there anyway. The fixed query returns exactly 4 real controller→mapper
#    layer violations on RuoYi-Vue-Plus.
# 3. `dead-code` (Function label): DOCUMENTED, not fixable at the query
#    level. For Java, every INTERFACE method declaration is
#    double-registered as both a `Method` node AND a `Function` node at the
#    same file/line — but real CALLS edges from callers only attach to the
#    `Method`-labeled twin (per the interface/impl blind spot). The
#    `Function`-labeled twin can never have an inbound edge, so this
#    template reports EVERY interface method as dead code regardless of
#    real usage. No query-side fix exists (same 2-hop EXISTS limitation as
#    dead-code-methods). Genuinely correct for non-interface functions
#    (confirmed: a truly-unused enum method was correctly flagged and had
#    zero grep hits repo-wide) — just treat any *Service-interface-shaped
#    hit as unverified until cross-checked with cbm-trace.sh.
# 4. Silent truncation on every fixed-LIMIT template: FIXED, newly found
#    during a code review pass. None of these templates ever compared their
#    row count to their own LIMIT, so a result set larger than the cap was
#    returned as if it were complete, with zero signal — this directly
#    contradicts this skill's "accuracy first" priority. Confirmed on live
#    data: `routes` LIMIT 200 vs a true count of 303 (103 hidden); `dead-code`
#    LIMIT 100 vs a true count of 348 (248 hidden); `dead-code-methods`
#    LIMIT 100 vs a true count of 1159 (1059 hidden — over 90%). A prior
#    verification pass had called `routes` "already accurate, no change
#    needed" — that only checked individual row correctness, never the
#    total count against the cap. Fixed generically below: when a
#    template's row count equals its LIMIT, a cheap follow-up count(*)
#    query runs and a stderr warning reports the real total and how many
#    rows are hidden. `hubs` is exempt on purpose — it is an intentional
#    top-20 ranking, not a truncated "list all" result.
# 5. `cross-layer`'s layerA/layerB args: FIXED, newly found during a code
#    review pass. They were spliced raw into the Cypher string with no
#    escaping — an argument containing a single quote crashes the parser
#    with a raw, unhandled error (confirmed live: `expected token type 85,
#    got 86`), an injection-shaped input-handling defect. Fixed by
#    stripping `'` and `\` from both args before interpolation (these are
#    meant to be plain path-fragment filters like `/controller/`; neither
#    character has a legitimate use there).
# 6. Every query_graph call in this script: FIXED, newly found during a code
#    review pass. This script's underlying `cbm_call` (in `_project.sh`) had
#    no JSON-validation safety net at the time — unlike this skill's
#    codegraph-side `cg_call()`, a raw Cypher-engine crash (bad syntax, an
#    unsupported construct, item 2/5 above before they were fixed)
#    propagated straight to the caller as non-JSON output instead of the
#    structured `{"error", "hint"}` shape every script in this ecosystem is
#    supposed to guarantee. Originally patched LOCALLY here (a `run_query`
#    wrapper duplicating `cg_call()`'s tempfile + `jq empty` pattern) with
#    the shared `_project.sh::cbm_call` flagged as an out-of-scope followup.
# 7. That followup landed (2026-07-21: `cbm_call` itself now guarantees
#    valid JSON via the shared `_is_valid_json_answer()`, see `_project.sh`/
#    `_json_safe.sh`) but this script's local `run_query` was never revisited
#    — it kept re-validating output `cbm_call` already guarantees is valid,
#    via a bare `jq empty` with NO non-empty guard, i.e. the exact bug
#    `_json_safe.sh` centralizes a fix for, reintroduced here by not sharing
#    it. Found during a codebase-memory-mcp/codegraph parity audit
#    (2026-07-19) and simplified: `run_query` now only builds the request
#    and defers entirely to `cbm_call` for the JSON guarantee, same as every
#    other cbm-* script, keeping just the Cypher-specific hint text on error.
set -euo pipefail; source "$(dirname "$0")/_project.sh"

# `cbm_call` (see _project.sh) already guarantees valid JSON out of every
# call — no local re-validation needed here anymore (see item 7 above). Only
# job left for this wrapper: attach a Cypher-specific hint on top of
# whatever error cbm_call recovered, without reshaping or discarding it.
run_query() {
  local q="$1"
  cbm_call query_graph "$(jq -n --arg p "$PROJECT" --arg q "$q" '{project:$p, query:$q}')" \
    | jq 'if (.error != null) then . + {hint: "Cypher template hit a parser/engine error — this is a template bug, not a data answer; do not retry unchanged, report it."} else . end'
}

[ "$#" -ge 1 ] || { echo '{"error":"template (positional arg) is required","hint":"usage: cbm-cypher.sh dead-code|dead-code-methods|cross-layer|hubs|routes [arg1] [arg2]"}'; exit 2; }
LIM=""; CQ=""
case "$1" in
  dead-code)   Q='MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() } RETURN f.name, coalesce(f.file_path, f.file) LIMIT 100'
               CQ='MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() } RETURN count(f) AS c'; LIM=100
               echo '{"warning":"Java: EVERY interface method is reported as dead here regardless of real usage — interface declarations are double-registered as Function+Method nodes and only the Method twin ever receives CALLS edges (field-verified, see references/cbm-blindspots.md). Cross-check any *Service/I*-interface hit with cbm-trace.sh before concluding dead code; genuinely reliable for non-interface functions."}' >&2
               ;;
  dead-code-methods)
               Q='MATCH (m:Method) WHERE NOT EXISTS { (m)<-[:CALLS]-() } RETURN m.name, coalesce(m.file_path, m.file), m.parent_class LIMIT 100'
               CQ='MATCH (m:Method) WHERE NOT EXISTS { (m)<-[:CALLS]-() } RETURN count(m) AS c'; LIM=100
               echo '{"warning":"Java: results for classes implementing an interface are UNRELIABLE — calls through the interface never attach to the impl method (field-verified, see references/cbm-blindspots.md). For any *Impl-suffixed class in this list, re-run cbm-trace.sh on the matching interface method before concluding dead code."}' >&2
               ;;
  cross-layer) A="${2:-/controller/}"; B="${3:-/mapper/}"
               A="${A//\'/}"; A="${A//\\/}"; B="${B//\'/}"; B="${B//\\/}"
               Q="MATCH (a)-[:CALLS]->(b) WHERE a.file_path CONTAINS '$A' AND b.file_path CONTAINS '$B' RETURN a.name, coalesce(a.file_path, a.file), b.name LIMIT 200"
               CQ="MATCH (a)-[:CALLS]->(b) WHERE a.file_path CONTAINS '$A' AND b.file_path CONTAINS '$B' RETURN count(*) AS c"; LIM=200
               ;;
  hubs)        Q='MATCH (m:Method)<-[:CALLS]-() WHERE m.parent_class IS NOT NULL RETURN m.parent_class AS class, count(*) AS callers ORDER BY callers DESC LIMIT 20'
               echo '{"warning":"Counts DIRECT inbound calls per class only (not transitive/multi-hop) and is subject to the same interface/impl split as everything else in this skill — a heavily-used *Impl class can undercount versus its interface. Treat as a strong signal, not a certified ranking. This is an intentional top-20, not a full list — do not treat classes outside it as having zero callers."}' >&2
               ;;
  routes)      Q='MATCH (r:Route) RETURN r.name, coalesce(r.file_path, r.file) LIMIT 200'
               CQ='MATCH (r:Route) RETURN count(r) AS c'; LIM=200
               ;;
  *) echo '{"error":"unknown template","hint":"use: dead-code | dead-code-methods | cross-layer [layerA] [layerB] | hubs | routes"}'; exit 1;;
esac

RESULT=$(run_query "$Q")
if [ -n "$CQ" ]; then
  N=$(printf '%s' "$RESULT" | jq '.rows | length' 2>/dev/null || echo 0)
  if [ "$N" = "$LIM" ]; then
    TOTAL=$(run_query "$CQ" | jq -r '.rows[0][0] // "unknown"' 2>/dev/null || echo unknown)
    if [[ "$TOTAL" =~ ^[0-9]+$ ]]; then
      HIDDEN=$((TOTAL - LIM))
      echo "{\"warning\":\"results capped at $LIM of $TOTAL total ($HIDDEN rows hidden) — narrow the query (e.g. cross-layer's layerA/layerB args) or run cbm_call query_graph directly with a higher LIMIT for the full list. Do not report the $LIM shown rows as a complete list.\"}" >&2
    else
      echo "{\"warning\":\"results capped at $LIM — could not confirm the true total (count query failed), treat this as a PARTIAL list, not a complete one.\"}" >&2
    fi
  fi
fi
printf '%s' "$RESULT"
