#!/usr/bin/env bash
# Field-verified 2026-07-20 on RuoYi-Vue-Plus: get_architecture's real
# response has NO `entry_points` key at all -- the previous version of this
# script asked for it anyway, so it was always null (a dead field indistinguishable
# from "this repo has none", not "this field doesn't exist"). Real keys also
# include `layers`/`boundaries` (directly relevant to architecture questions,
# never surfaced here before) and `edge_types`/`node_labels`/`total_nodes`/
# `total_edges` (index-wide stats, left out on purpose here — same shape of
# info `cg-arch.sh` gives on the codegraph side via `codegraph status`).
# Also confirmed live: `routes` here is capped well below the real count (20
# shown vs a real 303 routes on this repo, cross-checked against `cg-find.sh
# -k route`/`cbm-cypher.sh routes`) — this endpoint is an OVERVIEW, not an
# exhaustive listing, for any of its array fields; say so in the hint rather
# than let a short list look like the whole picture.
# Code-review finding (2026-07-21): same error-swallowing defect as
# cbm-impact.sh — a cbm_call() error object used to be silently replaced by
# an all-null "architecture overview", indistinguishable from a real tiny
# repo. Now passes `.error` through untouched instead of reshaping it away.
set -euo pipefail; source "$(dirname "$0")/_project.sh"
cbm_call get_architecture "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq 'if (.error != null) then . else {languages, packages: (.packages[:15] // null),
         layers: (.layers // null), boundaries: (.boundaries[:10] // null),
         routes: (.routes[:20] // null), hotspots: (.hotspots[:10] // null), clusters: (.clusters[:10] // null),
         hint: "routes/hotspots/clusters/packages/boundaries above are an OVERVIEW SLICE, not guaranteed exhaustive (field-verified: routes showed 20 of a real 303 on a mid-size repo) — for an exhaustive list of one specific kind, use cg-find.sh -k <kind> or cbm-cypher.sh routes instead"} end'
