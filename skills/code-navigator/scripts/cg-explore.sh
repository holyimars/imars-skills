#!/usr/bin/env bash
# Usage: cg-explore.sh [-m max-files] '<natural-language question...>'
# Flagship command: relevant symbols' source + call paths + blast radius in
# one shot, including the interface/impl "[dynamic: ...]" synthesis. Prefer
# this over chaining cg-find + cg-trace + cg-node for any compound question.
# Output is markdown (verbatim source included) — do not re-Read files it
# already printed.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
MAXFILES=3
if [ "${1:-}" = "-m" ]; then MAXFILES="$2"; shift 2; fi
codegraph explore "$@" --max-files "$MAXFILES"
