#!/usr/bin/env bash
set -euo pipefail; source "$(dirname "$0")/_project.sh"
cbm_call get_architecture "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq '{languages, packages: (.packages[:15] // null), entry_points: (.entry_points[:10] // null),
         routes: (.routes[:20] // null), hotspots: (.hotspots[:10] // null), clusters: (.clusters[:10] // null)}'
