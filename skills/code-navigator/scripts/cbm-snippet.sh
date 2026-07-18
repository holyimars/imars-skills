#!/usr/bin/env bash
# Usage: cbm-snippet.sh <qualified-name>   (format: <project>.<path_parts>.<name>, from cbm-find output)
set -euo pipefail; source "$(dirname "$0")/_project.sh"
[ "$#" -ge 1 ] || { echo '{"error":"qualified-name (positional arg) is required","hint":"usage: cbm-snippet.sh <qualified-name>"}'; exit 2; }
cbm_call get_code_snippet \
  "$(jq -n --arg p "$PROJECT" --arg q "$1" '{project:$p, qualified_name:$q}')"
