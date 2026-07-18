#!/usr/bin/env bash
# Shared helpers: cbm_call (single place that knows HOW to invoke the CLI)
# and project-name auto-resolution (cached per repo root).
set -euo pipefail
source "$(dirname "$0")/_json_safe.sh"

# Unified CLI invocation. Field-verified on v0.9.0:
# - raw-JSON positional args are deprecated -> we pipe JSON via stdin;
# - the --raw flag does NOT exist in v0.9.0 ("unknown tool: --raw") even
#   though the main-branch README shows it; default output is jq-parseable.
# If a future release changes the interface, fix it HERE and only here.
#
# Field-verified 2026-07-20: unlike search_graph/get_architecture/
# detect_changes (which return a valid `{"error":...}` JSON object with exit
# code 0 on a soft failure), trace_path exits NONZERO with its error JSON
# written to STDERR (after an unrelated `level=info msg=mem.init...` log
# line) and NOTHING on stdout -- confirmed live: an unknown function name
# exits 1, stdout empty, `{"error":"function not found",...,"hint":"..."}`
# on stderr only. Before this fix, cbm_call had no safety net: the calling
# script's `set -euo pipefail` aborted the whole script right at that line,
# so the well-formed error+hint the CLI already produced was thrown away and
# the caller saw nothing at all -- silent and hint-less, not the "every
# script always returns valid JSON with a hint" guarantee this skill's own
# scripts are supposed to uphold (the exact defect class this shared helper
# was flagged, but not yet fixed, for in an earlier pass -- see
# cbm-blindspots.md's `cbm-cypher.sh` section, item 6). Recovers the real
# error/hint from stderr when it's there; only falls back to a generic
# wrapper if stderr isn't parseable JSON either. Mirrors cg_call()
# (scripts/_gate.sh) and cbm-cypher.sh's local run_query(), now as the
# shared default for every cbm-* script instead of a per-script opt-in.
cbm_call() {
  local tool="$1"; local body="${2:-}"
  local out err status errtail
  err=$(mktemp)
  set +e
  if [ -n "$body" ]; then
    out=$(printf '%s' "$body" | codebase-memory-mcp cli "$tool" 2>"$err")
  else
    out=$(codebase-memory-mcp cli "$tool" 2>"$err")
  fi
  status=$?
  set -e
  # The non-empty-then-jq-empty predicate lives in _json_safe.sh, shared with
  # cg_call() (_gate.sh) -- see that file for why it must be a separate
  # non-empty check rather than `jq empty` alone.
  if _is_valid_json_answer "$out"; then
    printf '%s' "$out"
  else
    errtail=$(tail -n1 "$err" 2>/dev/null || true)
    if _is_valid_json_answer "$errtail"; then
      printf '%s' "$errtail"
    else
      jq -cn --arg m "$(cat "$err")$out" --argjson s "$status" \
        '{error: $m, exitCode: $s, hint: "codebase-memory-mcp call failed with no parseable JSON on stdout or stderr — this is a tool/wrapper bug, not a data answer; report it rather than retrying unchanged"}'
    fi
  fi
  rm -f "$err"
}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE="/tmp/cbm-project-$(echo -n "$ROOT" | md5sum | cut -c1-12)"
if [ -f "$CACHE" ]; then PROJECT=$(cat "$CACHE"); else
  BASE=$(basename "$ROOT")
  # Field-verified naming rule: project name is the FLATTENED absolute path
  # (leading separator dropped, separators -> hyphens), e.g.
  # /Users/me/www/my-service -> Users-me-www-my-service
  FLAT=$(printf '%s' "$ROOT" | sed 's|^[/\\]||; s|[/\\]|-|g')
  LISTING=$(cbm_call list_projects)
  # Exact tiers (flattened path, then the plain basename used by the
  # documented --name override) must win over the fuzzy suffix fallback:
  # field-verified collision where a stale, unrelated indexed project
  # happened to end with the same basename (e.g. a benchmark clone named
  # "...-RuoYi-Vue-Plus") silently outranked the real "RuoYi-Vue-Plus"
  # project via endswith() and every query answered from the wrong graph.
  RESOLVED=$(echo "$LISTING" | jq -r --arg flat "$FLAT" --arg base "$BASE" '
    [.projects[]?.name // empty] as $n
    | ( [$n[] | select(. == $flat)]
      + [$n[] | select(ascii_downcase == ($flat|ascii_downcase))]
      + [$n[] | select(. == $base)]
      + [$n[] | select(ascii_downcase == ($base|ascii_downcase))] ) as $exact
    | ( [$n[] | select(endswith($base))]
      + [$n[] | select(ascii_downcase | endswith($base|ascii_downcase))] ) as $fuzzy
    | { project: ($exact[0] // $fuzzy[0] // ""),
        ambiguous: (($exact | length) == 0 and (($fuzzy | unique | length) > 1)) }
    | @json')
  PROJECT=$(echo "$RESOLVED" | jq -r '.project')
  if [ "$(echo "$RESOLVED" | jq -r '.ambiguous')" = "true" ]; then
    echo "warning: '$PROJECT' picked by ambiguous suffix match — multiple indexed projects end with '$BASE'; run 'codebase-memory-mcp cli list_projects' and delete stale/duplicate indexes, or re-index this repo with a more specific --name" >&2
  fi
  if [ -z "$PROJECT" ]; then
    echo "{\"error\":\"repo not indexed\",\"hint\":\"run: codebase-memory-mcp cli index_repository --repo-path '$ROOT' --name '$BASE' --persistence true — or fall back to native grep\"}" >&2
    exit 2
  fi
  # Soft gate (first resolution only): tiny project -> remind the skill's gate rule
  NODES=$(echo "$LISTING" | jq -r --arg n "$PROJECT" \
    '.projects[]? | select(.name==$n) | (.nodes // .node_count // empty)' 2>/dev/null || true)
  if [ -n "${NODES:-}" ] && [ "$NODES" -lt 500 ] 2>/dev/null; then
    echo "warning: '$PROJECT' has only $NODES graph nodes (likely <1k LOC) — per skill gate, prefer native grep/read" >&2
  fi
  echo "$PROJECT" > "$CACHE"
fi
export PROJECT
