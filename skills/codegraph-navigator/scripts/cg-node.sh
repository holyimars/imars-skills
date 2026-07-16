#!/usr/bin/env bash
# Usage: cg-node.sh <exact-symbol>
#    or: cg-node.sh -f <file> [--offset N] [--limit N] [--symbols-only]
# One symbol's source + caller/callee trail in one call (cheaper than Read on
# a whole file), or file mode to read a file with line numbers + dependents.
# Interface method calls show a "[dynamic: interface -> impl]" label on the
# trail — that label IS the cross-reference, follow it with another
# cg-node.sh call rather than assuming a short trail means "no more callers".
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
codegraph node "$@"
