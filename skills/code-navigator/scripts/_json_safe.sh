#!/usr/bin/env bash
# Shared by _gate.sh's cg_call() and _project.sh's cbm_call() -- the exact
# predicate for "is this captured stdout a real, parseable JSON answer", plus
# a small arg-validation helper reused by scripts that take numeric
# positional/flag args (limit, depth, offset).
#
# Code-review consolidation (2026-07-21): `jq empty` on a completely empty
# string exits 0 (field-verified) -- an explicit non-empty check is required
# or a nonzero-exit-with-no-stdout failure would be silently treated as a
# valid (blank) success. This exact fix had to be applied twice in two
# separate rounds (cg_call first, cbm_call much later) because the logic was
# duplicated instead of shared -- centralized here so a future fix only has
# to happen once.
_is_valid_json_answer() {
  [ -n "$1" ] && printf '%s' "$1" | jq empty >/dev/null 2>&1
}

# Fails fast with a structured error instead of letting a non-numeric value
# reach --argjson later and crash the calling script with a raw,
# unstructured jq parse error.
#
# Regression audit (2026-07-19): this used to write its error to STDERR only,
# with no `hint` field -- leaving STDOUT completely empty on a bad arg. Any
# caller following this skill's own "capture stdout, jq empty it" convention
# (the exact pattern cbm_call()/cg_call() had to harden against, see this
# file's own comment above) would see a blank, successfully-parsing empty
# string instead of a structured error -- the identical failure shape the
# rest of this file exists to prevent, just reintroduced at the one arg-
# validation helper every numeric-flag script shares. Fixed to print on
# STDOUT with a hint, matching every other error path in this skill.
_require_positive_int() {
  local value="$1" label="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "{\"error\":\"invalid value for $label: '$value' is not a positive integer\",\"hint\":\"pass a positive integer for $label\"}"
      exit 2
      ;;
  esac
}
