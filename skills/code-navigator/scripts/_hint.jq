# Shared by cbm-find.sh's semantic branch and cg-trace.sh's final hint block:
# both collect whichever of several NON-mutually-exclusive warnings apply
# (e.g. a result can be both truncated AND low-scoring, or both truncated
# AND auto-bridged) -- an elif chain can only ever report one, silently
# dropping the other. Centralized here so this idiom is defined once instead
# of hand-copied at each call site (code-review finding 2026-07-21).
def join_warnings(msgs): (msgs | if length == 0 then null else join(" | ") end);
