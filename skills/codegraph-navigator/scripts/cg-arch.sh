#!/usr/bin/env bash
# Usage: cg-arch.sh [max-depth]
# codegraph has no single "architecture summary" endpoint (unlike
# get_architecture on codebase-memory-mcp) — this merges index stats
# (codegraph status) with the file tree (codegraph files) into one call.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
DEPTH="${1:-2}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cg_call status "$CG_ROOT" -j >"$TMP/status.json"
cg_call files -j --max-depth "$DEPTH" >"$TMP/files.json"
# large repos can make `files -j` exceed the shell's argv size limit if piped
# through --argjson — read both from disk via --slurpfile instead.
jq -n --slurpfile s "$TMP/status.json" --slurpfile f "$TMP/files.json" \
  'if ($s[0]|type)=="object" and ($s[0]|has("error")) then {error: $s[0].error, hint: ("codegraph status failed: " + $s[0].error)}
   elif ($f[0]|type)=="object" and ($f[0]|has("error")) then {error: $f[0].error, hint: ("codegraph files failed: " + $f[0].error)}
   else {languages: $s[0].languages, fileCount: $s[0].fileCount, nodeCount: $s[0].nodeCount,
     edgeCount: $s[0].edgeCount, nodesByKind: $s[0].nodesByKind,
     tree: ($f[0][:60]),
     treeTruncated: (($f[0]|length) > 60),
     hint: (if ($f[0]|length) > 60 then "tree truncated to 60/\($f[0]|length) files — narrow with: codegraph files --filter <dir> -j" else null end)}
   end'
