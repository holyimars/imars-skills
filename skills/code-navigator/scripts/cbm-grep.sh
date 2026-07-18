#!/usr/bin/env bash
# Graph-scoped text search (indexed files only). Usage: cbm-grep.sh '<text>'
set -euo pipefail; source "$(dirname "$0")/_project.sh"
cbm_call search_code "$(jq -n --arg p "$PROJECT" --arg q "$1" '{project:$p, pattern:$q, limit:20}')"
