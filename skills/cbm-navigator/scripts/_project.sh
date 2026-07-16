#!/usr/bin/env bash
# Shared helpers: cbm_call (single place that knows HOW to invoke the CLI)
# and project-name auto-resolution (cached per repo root).
set -euo pipefail

# Unified CLI invocation. Field-verified on v0.9.0:
# - raw-JSON positional args are deprecated -> we pipe JSON via stdin;
# - the --raw flag does NOT exist in v0.9.0 ("unknown tool: --raw") even
#   though the main-branch README shows it; default output is jq-parseable.
# If a future release changes the interface, fix it HERE and only here.
cbm_call() {
  local tool="$1"; local body="${2:-}"
  if [ -n "$body" ]; then
    printf '%s' "$body" | codebase-memory-mcp cli "$tool"
  else
    codebase-memory-mcp cli "$tool"
  fi
}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE="/tmp/cbm-project-$(echo -n "$ROOT" | md5sum | cut -c1-12)"
if [ -f "$CACHE" ]; then PROJECT=$(cat "$CACHE"); else
  BASE=$(basename "$ROOT")
  # Field-verified naming rule: project name is the FLATTENED absolute path
  # (leading separator dropped, separators -> hyphens), e.g.
  # /Users/me/www/my-service -> Users-me-www-my-service
  FLAT=$(printf '%s' "$ROOT" | sed 's|^[/\\]||; s|[/\\]|-|g')
  PROJECT=$(cbm_call list_projects | jq -r --arg flat "$FLAT" --arg base "$BASE" '
    [.projects[]?.name // empty] as $n
    | ( [$n[] | select(. == $flat)]
      + [$n[] | select(ascii_downcase == ($flat|ascii_downcase))]
      + [$n[] | select(endswith($base))]
      + [$n[] | select(ascii_downcase | endswith($base|ascii_downcase))] )
    | first // empty')
  if [ -z "$PROJECT" ]; then
    echo "{\"error\":\"repo not indexed\",\"hint\":\"run: codebase-memory-mcp cli index_repository --repo-path '$ROOT' --name '$BASE' --persistence true — or fall back to native grep\"}" >&2
    exit 2
  fi
  # Soft gate (first resolution only): tiny project -> remind the skill's gate rule
  NODES=$(cbm_call list_projects | jq -r --arg n "$PROJECT" \
    '.projects[]? | select(.name==$n) | (.nodes // .node_count // empty)' 2>/dev/null || true)
  if [ -n "${NODES:-}" ] && [ "$NODES" -lt 500 ] 2>/dev/null; then
    echo "warning: '$PROJECT' has only $NODES graph nodes (likely <1k LOC) — per skill gate, prefer native grep/read" >&2
  fi
  echo "$PROJECT" > "$CACHE"
fi
export PROJECT
