#!/usr/bin/env bash
# Optional non-blocking PreToolUse hook: augments Grep/Glob AND Bash-run
# grep/git-grep/rg/ag/find/ls/tree calls with knowledge-graph symbol matches
# as additionalContext. Replaces the old cbm-augment.sh + codegraph-augment.sh
# pair (0.0.27) -- this is now ONE process querying both index products
# (whichever are present) and merging their results into a single
# injection, tagged by which tool(s) found each hit. Self-contained except
# for jq (plus mktemp/git, both near-universal on any dev box). EVERY
# failure path exits 0.
#
# 0.0.28 widened the Bash-command surface from grep/git-grep/rg/ag to also
# cover `find` (-name/-iname/-path/-wholename/-ipath/-iwholename) and
# pattern-bearing `ls`/`tree` (tree's -P flag, or a bare positional argument
# containing a shell-glob wildcard). Bare ls/tree invocations with no
# extractable pattern are DELIBERATELY not covered -- see extract_bash_lstree
# below.
#
# 0.0.29 added an intent guard to the find branch: a matched -name/-iname/...
# value is discarded (no PATTERN, silent) if the same clause later reveals
# it's actually a cleanup/exclusion target rather than a lookup -- `-delete`,
# `-exec`/`-execdir`/`-ok`/`-okdir` invoking rm/rmdir/unlink/shred, a
# `| xargs rm`-style pipeline continuation, or `-prune`. See
# extract_bash_find below for the correctness argument (a conservative
# approximation, not a proof) and known gaps (`mv`, `-exec sudo rm`,
# `ls --ignore=`).
#
# 0.0.30 stopped ROOT from being hard-locked to wherever the hook process
# itself happens to run -- field-verified against a real indexed repo
# (RuoYi-Vue-Plus): grepping a real, richly-indexed symbol via an absolute
# path into a DIFFERENT repo produced zero augmentation, because
# `git rev-parse --show-toplevel` only ever sees the hook's own inherited
# cwd, never whatever directory the search command's own arguments point
# at. Two independent layers now feed ROOT, tried in order of trust:
# (1) the hook JSON's own top-level `cwd` field (Claude Code's own
# authoritative, cd-drift-tracking value -- see PreToolUse docs -- zero
# regex involved, applies to every branch below); (2) SEARCH_DIR, an
# explicit same-clause target directory extracted from the command/tool
# call itself (Grep/Glob's own `path` field, find's search-root argument,
# ls/tree's already-captured token's own dirname) -- see the SEARCH_DIR
# sanitization and ROOT-resolution blocks near the bottom for the full
# safety argument. In short, the four review-mandated constraints: (1)
# only an absolute SEARCH_DIR is trusted (0.0.31 later relaxed this to a
# cd-gated, existence-gated HOOK_CWD join); (2) a SEARCH_DIR-resolved ROOT
# keeps cbm project matching exact-only (0.0.31 relaxed: dropped on
# equality with the session's own root); (3) every resolution git call is
# $TMO-bounded; (4) an explicit target that fails to resolve exits rather
# than falling back to the session repo. grep/rg/ag deliberately do NOT
# get layer (2) this
# round -- their path argument can land before OR after the pattern token
# and after trailing flags, which needs array+loop handling this script's
# other branches don't -- see `skills/code-navigator/SKILL.md` for the
# operational workaround (cd into the target repo first, rather than
# passing it an absolute path).
#
# 0.0.31 is a structured code-review pass over the 0.0.28-0.0.30 work; every
# finding was field-verified (reproduced via bash -x on this script) before
# being fixed. (P1) the file->parent-dir trim before `git -C` only cut at
# `/`, so a backslash-form Windows file path -- which the absolute-path
# trust check deliberately ACCEPTS -- fed the untrimmed FILE to `git -C`,
# failed, and took the explicit-target `exit 0` with it, silently killing
# augmentation for same-repo Grep-with-path calls that worked before
# 0.0.30; the trim now cuts at either separator ([/\\]), which also fixes
# mixed-separator paths cutting at the wrong depth. (P2) a SEARCH_DIR still
# carrying shell wildcards (`ls /repo/**/*X*`, `find src* -name ...`) can
# never survive `git -C`; it is now truncated to its longest literal prefix
# centrally, once, for every branch that feeds SEARCH_DIR. (P2) the
# exact-match-only cbm rule for dynamically-resolved ROOTs was over-strict
# when the resolved target IS the session's own repo (a Grep path into a
# subdirectory of the current project); ROOT is now compared against the
# session's own toplevel and the restriction dropped on equality. (P3) a
# relative dir token is no longer discarded outright: when HOOK_CWD is
# present it is joined and resolved (with an existence gate) -- see the
# sanitization block. (P3) UNC paths are documented as a deliberate
# non-target there too. (P3) the three Bash extraction branches moved into
# functions (extract_bash_grep/find/lstree) -- logic byte-identical,
# re-verified by the full regression matrix.
#
# A second, independent adversarial pass (Fable 5) over those fixes caught
# four more real defects, fixed here too: (P2) the relative join
# mis-anchors when the command itself changes directory -- this hook fires
# BEFORE the command runs, so HOOK_CWD is the PRE-cd directory, and
# `cd src && find .. -name ...` joined onto the wrong parent (the [ -e ]
# gate can't catch it: the mis-joined path often EXISTS, it's just not
# what the command will search) -- any cd/pushd/popd at a command boundary
# now disables the relative join for that call (conservative: costs only
# the new relative-join coverage, never a wrong-repo resolution; absolute
# roots are unaffected, cd doesn't move them). (P3) the file->parent trim
# could emit a bare drive letter (`D:` from a file at a drive root), and
# `git -C "D:"` means DRIVE-RELATIVE on Windows -- it resolves the hook
# process's own per-drive cwd, i.e. a real-but-WRONG repo, instead of
# failing; bare drive letters are normalized to `D:/` so they resolve (or
# take the explicit-target exit) honestly. (P3) the SESSION_ROOT legacy
# fallback was missing $TMO (the pre-existing legacy ROOT fallback now
# gets it too, since TMO is computed earlier these days). (P3)
# forward-slash UNC (`//server/share` -- the spelling Git Bash users
# actually type, since backslashes get eaten) slipped past the `/*`
# absolute branch straight into a ~2s network probe per call; now
# discarded like its backslash twin. Plus two hygiene fixes from the same
# pass: GIT_DIR/GIT_WORK_TREE are unset around every resolution git call
# (an exported GIT_DIR overrides -C entirely and would silently collapse
# every resolution to one repo), and LSTREE_DIR is explicitly initialized
# (it was the one conditionally-assigned global, inheritable from the
# process environment into SEARCH_DIR). One pre-existing (0.0.28-era) gap
# the same pass surfaced is documented in README instead of fixed here: a
# search command on the SECOND line of a multi-line Bash command never
# matches any extraction regex (the clause-boundary class has no newline).
#
# 0.0.32 is a two-axis review pass (/code-review xhigh: standards axis
# against this repo's own documented invariants plus a code-smell
# baseline, spec axis against the 0.0.30 plan file and each entry's own
# CHANGELOG claims) over the whole 0.0.28-0.0.31 body of work. Standards:
# the three duplicated shapes the review flagged became shared helpers
# (strip_quotes x4 sites, the basename/wildcard/quality-guard tail x2,
# the bare quality guard x3, the session-root ladder x2 -- see
# strip_quotes/pattern_ok/qualify_glob_candidate/resolve_session_root)
# and the clause-boundary prefix all four recognition regexes repeat now
# has ONE definition (BOUNDARY_RE); GITRP was renamed GIT_CLEANENV; the
# time-budget model is stated explicitly at the TMO block instead of
# implied. Spec: CD_RE is now matched against "$CMD " (sentinel space,
# same engine-portability idiom as INTENT_RE) so a directory-changing
# verb at the very END of the command also sets CMD_HAS_CD, making the
# documented "ANY cd/pushd/popd disables the join" claim literally true;
# and the 0.0.31 "never a wrong-repo resolution" claim is qualified where
# it appears -- it covers the JOIN itself; a command that cd's into a
# DIFFERENT repo still falls back to querying the session repo, which is
# the pre-0.0.30 status-quo noise, now a documented known boundary (README)
# with the operational fix in SKILL.md: make the cd its own earlier Bash
# call. Logic otherwise byte-identical; full regression matrix re-run.
#
# Field-verified fixes carried over from the two predecessor scripts:
# no --raw flag on codebase-memory-mcp v0.9.0; its results use file_path
# (no line); codegraph query on an unindexed dir prints an ANSI "[ERR] ..."
# line to STDOUT with exit 0 (the .codegraph/ existence check below keeps
# normal operation off that path); macOS has no `timeout` (gtimeout probed).
#
# Regexes are kept in variables, never inlined into `[[ =~ ]]` -- macOS's
# bundled bash 3.2 silently treats an inline quoted regex as a literal
# string instead of a pattern.

INPUT=$(cat) || exit 0

# Step 0 -- zero-subprocess coarse filter, before any jq call. Must let
# through BOTH native Grep/Glob calls (tool_name is capitalized JSON text,
# e.g. "tool_name":"Grep") and Bash commands that mention a target command
# in lowercase. Checking only the lowercase forms here would silently drop
# every native Grep/Glob call (case-sensitive match), which is why both
# cases are listed explicitly.
case "$INPUT" in
  *'"Grep"'*|*'"Glob"'*|*grep*|*'rg '*|*'ag '*|*'find '*|*'ls '*|*'tree '*) ;;
  *) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

# HOOK_CWD is Claude Code's own authoritative "cwd when this hook fired"
# field (tracks cd drift during the session, per the PreToolUse docs) --
# not the same thing as this process's own inherited OS cwd, which is what
# `git rev-parse --show-toplevel` below would otherwise silently use.
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# --- Shared extraction helpers (0.0.32: the two-axis review's standards
# pass flagged the same shapes appearing verbatim across extractors --
# quote stripping at 4 sites, the basename/wildcard/quality-guard tail in
# both find and ls/tree, the bare quality guard in all three). Transfer
# convention: bash 3.2 has no namerefs and this script deliberately uses
# no `local`, so helpers read/write fixed shared globals (SQV, CANDIDATE)
# named at each call site. HARD RULE: none of these helpers may ever use
# `[[ =~ ]]` -- extract_bash_find computes TAIL from BASH_REMATCH[0]
# AFTER calling them, and a regex match inside a helper would silently
# clobber it. ---

# The clause-boundary prefix every command-recognition regex starts with:
# start of string, or right after ;/&/| plus optional whitespace. ONE
# definition on purpose -- the README known boundary about multi-line
# commands (no newline in this class) lives exactly here, and widening it
# someday is a one-place change followed by the full regression matrix,
# instead of four scattered copies drifting apart. Interpolating this
# variable does not change any regex's group numbering: it contributes
# the same single group `(^|[;&|])` the inline copies did.
BOUNDARY_RE="(^|[;&|])[[:space:]]*"

# Strip one layer of matching quotes from $SQV.
strip_quotes() {
  case "$SQV" in
    \"*\") SQV="${SQV#\"}"; SQV="${SQV%\"}" ;;
    \'*\') SQV="${SQV#\'}"; SQV="${SQV%\'}" ;;
  esac
}

# The shared quality guard: a candidate shorter than 3 chars or with no
# letter is far more likely a misparsed flag value than a symbol (see the
# grep extractor's comment for the accepted `-t typescript` gap). Reads
# $CANDIDATE; the exit status is the verdict.
pattern_ok() {
  [ "${#CANDIDATE}" -ge 3 ] && [[ "$CANDIDATE" == *[A-Za-z]* ]]
}

# Shared tail of the find and ls/tree extractors: reduce a glob-ish token
# to its symbol-ish core -- basename (a -path/-wholename value or ls token
# often carries a path prefix), minus one leading and one trailing shell
# wildcard -- then apply the quality guard. Reads/writes $CANDIDATE; the
# exit status is the verdict.
qualify_glob_candidate() {
  CANDIDATE="${CANDIDATE##*/}"
  CANDIDATE="${CANDIDATE#[*?]}"
  CANDIDATE="${CANDIDATE%[*?]}"
  pattern_ok
}

# --- Bash-command extraction functions (0.0.31: moved out of the dispatch
# case into named functions -- one per command family -- purely for
# readability as the branch count grew; bodies are logic-identical to the
# inline 0.0.30 blocks and share globals: they read CMD and set PATTERN /
# SEARCH_DIR. Called in priority order by the Bash dispatch arm below,
# each gated on PATTERN still being empty. ---

# grep/git-grep/rg/ag -- a single regex doing three jobs at once: (a)
# confirm one of the target command names occurs at a real command
# boundary -- start of string, or right after `;`/`&`/`|` plus optional
# whitespace -- so a bare word like "grep" inside an unrelated sentence
# ("ls my grep folder && ...") can't be mistaken for an invocation; (b)
# skip zero-or-more leading `-flag` tokens; (c) capture the first
# positional argument, quoted or bare, in left-to-right order. Doing this
# as ONE combined regex (rather than a separate boundary check + a
# separate extraction search) matters: two independent regexes can each
# report success while anchoring to DIFFERENT occurrences of the command
# name in the string, which would silently extract from an invalid
# occurrence even though a valid one exists elsewhere in the same command
# line.
extract_bash_grep() {
  RE="${BOUNDARY_RE}(git[[:space:]]+grep|grep|rg|ag)[[:space:]]+((-[^[:space:]]+[[:space:]]+)*)(\"[^\"]*\"|'[^']*'|[^[:space:]\"'-][^[:space:]]*)"
  if [[ "$CMD" =~ $RE ]]; then
    SQV="${BASH_REMATCH[5]}"; strip_quotes; CANDIDATE="$SQV"
    # Quality guard (pattern_ok): flags that consume a separate value
    # (rg -t ts, grep -m 1) can still be misparsed as the pattern above --
    # a short and/or all-numeric result is the cheap tell. This doesn't
    # catch every case (e.g. `-t typescript`), which is a documented,
    # accepted gap: worst case is a wrong symbol lookup that degrades to a
    # clean empty result, same cost as the existing "nothing found" path.
    if pattern_ok; then
      PATTERN="$CANDIDATE"
    fi
  fi
}

# find: matches the value carried by -name/-iname/-path/-wholename/
# -ipath/-iwholename, NOT "the first positional argument" the way
# extract_bash_grep above does -- find's first positional argument is
# normally the search root, not the query pattern. [^;&|]* keeps the
# scan inside the same command clause (never crosses a ;/&/| boundary),
# same boundary discipline as the grep branch. Multiple -name/-iname in
# one clause (an `-o`-joined OR, e.g. `-iname "*.py" -o -iname "*.ts"`)
# end up capturing the LAST one, not the first, because [^;&|]* is
# greedy -- an accepted, documented gap, same cost tier as the grep
# branch's own `-t typescript` gap above. -regex/-iregex are
# deliberately NOT in the flag alias list: their value is a regex, not a
# shell glob, and the wildcard-stripping step below assumes glob syntax
# -- excluding them means a clean non-match instead of a semantically
# wrong PATTERN.
extract_bash_find() {
  # Group numbering (ERE has no non-capturing groups, so every `(...)`
  # counts): 1=boundary, 2=leading -H/-L/-P global flags (consumed, not
  # read), 3=dir-token-plus-mandatory-space wrapper, 4=the dir token
  # itself (this is SEARCH_DIR, find's own search-root argument -- takes
  # the FIRST one when find is given several, same accepted-approximation
  # tier as "takes the LAST -name/-iname value" below), 5=the -name/...
  # flag name, 6=the value (was BASH_REMATCH[3] before 0.0.30).
  # Group 4 is all-or-nothing by construction: its token class excludes
  # whitespace/;&|, so it either captures the complete first token right
  # after `find`+flags or doesn't participate at all -- there is no
  # partial-token or wrong-token outcome, on any POSIX-ish regex engine,
  # because group 3's mandatory trailing [[:space:]]+ forces group 4 to
  # start at a real token boundary and its own whitespace-free class
  # forces it to end at the next one. Field-verified across 9 shapes
  # (absolute/relative/`.`/multi-path/`-L`-prefixed/no-path/quoted-with-
  # space/flag-between-path-and--name/`-o`-joined) plus the full 0.0.29
  # intent-guard regression suite with the new indices -- zero deviation
  # from pre-0.0.30 PATTERN values in every case.
  FIND_RE="${BOUNDARY_RE}find[[:space:]]+(-[HLP][[:space:]]+)*((\"[^\"]*\"|'[^']*'|[^[:space:];&|-][^[:space:];&|]*)[[:space:]]+)?[^;&|]*(-name|-iname|-path|-wholename|-ipath|-iwholename)[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
  if [[ "$CMD" =~ $FIND_RE ]]; then
    # Both captures are read out up front; the helpers below use only
    # glob-style matching (never `[[ =~ ]]`, see the helper section's hard
    # rule), so BASH_REMATCH[0] is still intact for the TAIL computation
    # further down.
    FIND_DIR="${BASH_REMATCH[4]}"
    SQV="${BASH_REMATCH[6]}"; strip_quotes; CANDIDATE="$SQV"
    SQV="$FIND_DIR"; strip_quotes; FIND_DIR="$SQV"
    if qualify_glob_candidate; then
      # Intent guard (0.0.29): a -name/-iname/... value only becomes
      # PATTERN if nothing LATER in the same clause reveals it's being
      # deleted or excluded rather than looked up. Because the greedy
      # scan above always captures the LAST name-family flag in the
      # clause, anything past this match's end can only be describing
      # THIS candidate (a later -name/-iname would already have been
      # captured instead of this one) -- so it's safe to inspect without
      # a second independently-anchored regex that could latch onto a
      # different find clause. This is a conservative approximation, not
      # a proof: quoted values containing ;/&/| can interrupt the greedy
      # scan, and a trailing -prune can also be modifying a later
      # non-name test (e.g. `-type l -prune`) rather than this candidate
      # -- both failure modes only cause an extra, otherwise-valid match
      # to go silent, never the reverse.
      #
      # BASH_REMATCH[0] is the whole match, clause-start through the
      # captured value -- stripping it via a double-quoted parameter
      # expansion (so */? inside it are treated literally, never as
      # glob operators) isolates "what's left of this same clause".
      # First truncate at a newline (multi-line compound commands are
      # common; an unrelated command on the next line must not leak in),
      # then at the next ;/& -- deliberately NOT at |, so a `| xargs rm`
      # pipeline continuation of THIS find is still visible below.
      TAIL="${CMD#*"${BASH_REMATCH[0]}"}"
      if [ "$TAIL" != "$CMD" ]; then
        TAIL="${TAIL%%$'\n'*}"
        TAIL="${TAIL%%[;&]*}"
        # Every alternative requires [[:space:]] on both sides (via the
        # sentinel-padded " $TAIL " below) rather than a bare substring
        # or a `$` anchor -- `--prune`/`rsync --delete` contain `-prune`/
        # `-delete` as a substring but aren't find's own flags, and `$`
        # inside a `[[ =~ ]]` alternation is unspecified behavior in
        # strict POSIX ERE even though every regex engine this project
        # targets happens to support it.
        INTENT_RE="[[:space:]]-delete[[:space:]]|[[:space:]]-(exec|ok)(dir)?[[:space:]]+([^[:space:];&|]*/)?(rm|rmdir|unlink|shred)[[:space:]]|[[:space:]]-prune[[:space:]]|\|[[:space:]]*xargs([[:space:]]+-[^[:space:]]+)*[[:space:]]+([^[:space:];&|]*/)?(rm|rmdir|unlink|shred)[[:space:]]"
        if ! [[ " $TAIL " =~ $INTENT_RE ]]; then
          PATTERN="$CANDIDATE"
          SEARCH_DIR="$FIND_DIR"
        fi
      fi
    fi
  fi
}

# ls/tree: only recognized when the command carries an actual lookup
# pattern -- tree's -P flag, or a bare positional argument containing a
# shell-glob wildcard (the hook sees the raw command text at
# PreToolUse time, before the shell expands it, so a literal `*`/`?` is
# still there to match against). A bare invocation (plain directory
# listing, no pattern anywhere) has nothing to extract, so the regex
# below simply doesn't match and nothing fires -- this is the
# deliberate design for this tool pair, not an oversight: ls/tree are
# called far more often than grep for routine directory browsing, and
# firing on every bare call would meaningfully raise this hook's noise
# floor in a way grep/find can't (those self-limit via "query comes back
# empty -> exit 0").
#
# The optional whitespace-terminated prefix group before the wildcard
# token is NOT decorative -- omitting it lets the greedy [^;&|]* prefix
# overlap the unanchored capture group's own character class under
# POSIX ERE's leftmost-longest semantics, hollowing the capture out to
# a bare, isolated `*` (field-verified: `ls -la src/*Controller*`, the
# single most common shape this branch targets, captured only `*`;
# `tree -P "*.vue"` captured `*.vue"` with the closing quote stuck on,
# which the quote-stripping step below can't clean up since it doesn't
# start with a quote). Anchoring the token to a whitespace boundary
# fixes both. This is the same "boundary check and value extraction
# must be ONE regex, not two" principle the grep branch already follows
# (0.0.27 fixed a bug from splitting those into independent regexes) --
# here the equivalent trap was inside a single regex rather than across
# two.
extract_bash_lstree() {
  LSTREE_RE="${BOUNDARY_RE}(ls|tree)[[:space:]]+([^;&|]*[[:space:]])?([^[:space:];&|]*[*?][^[:space:];&|]*)"
  if [[ "$CMD" =~ $LSTREE_RE ]]; then
    SQV="${BASH_REMATCH[4]}"; strip_quotes; CANDIDATE="$SQV"
    # 0.0.30: the raw (quote-stripped, not yet basename-trimmed) token
    # already carries its own directory when one is present (e.g.
    # `src/*Controller*` or a cross-repo absolute `/d/data/repo/*.java`)
    # -- pure parameter expansion on already-captured text, no new regex.
    # Wildcards that survive into the dir part (`/repo/**` from
    # `/repo/**/*.java`) are handled by the central SEARCH_DIR
    # sanitization below, not here.
    [[ "$CANDIDATE" == */* ]] && LSTREE_DIR="${CANDIDATE%/*}"
    if qualify_glob_candidate; then
      PATTERN="$CANDIDATE"
      SEARCH_DIR="$LSTREE_DIR"
    fi
  fi
}

PATTERN=""
SEARCH_DIR=""
# LSTREE_DIR is the one conditionally-assigned shared global (only set when
# the ls/tree token carries a `/`) -- without this init an exported
# LSTREE_DIR from the user's environment would leak straight into
# SEARCH_DIR on every slash-less `ls *foo*` (0.0.31 adversarial review).
LSTREE_DIR=""
CMD_HAS_CD=""
case "$TOOL" in
  Grep|Glob)
    PATTERN=$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || exit 0
    SEARCH_DIR=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -z "$CMD" ] && exit 0
    # 0.0.31 (adversarial review): this hook fires BEFORE the command runs,
    # so HOOK_CWD is the PRE-cd directory. If the command itself changes
    # directory (`cd src && find .. -name ...` -- an extremely common
    # Claude Code shape), joining a relative search root onto HOOK_CWD
    # anchors it wrong, and the [ -e ] existence gate can't catch it: the
    # mis-joined path often EXISTS, it's just not what the command will
    # search -- worst case it's a real-but-WRONG repo. Any
    # directory-changing verb at a command boundary disables the relative
    # join in the sanitization block below. Conservative by construction:
    # a cd anywhere in the command line (even after the search clause)
    # only costs that call the 0.0.31 relative-join coverage -- the call
    # falls back to the session-repo layer, so (0.0.32 review
    # qualification) for a command that cd's into a DIFFERENT repo the
    # query still targets the session repo, which is the pre-0.0.30
    # status-quo noise, documented as a known boundary (README; SKILL.md's
    # operational fix: make the cd its own earlier Bash call) -- but the
    # join itself never ADDS a wrong-repo resolution. Absolute search
    # roots are unaffected (cd doesn't move them).
    # 0.0.32: matched against "$CMD " (one sentinel space appended -- the
    # same engine-portability idiom INTENT_RE uses instead of a `$`
    # anchor) so a directory-changing verb at the very END of the command
    # line (`find src -name X && popd`) also sets the flag; before this,
    # the documented "ANY cd/pushd/popd disables the join" claim was
    # slightly stronger than the code. Only more conservative: the flag
    # can only fire in MORE cases, never fewer.
    CD_RE="${BOUNDARY_RE}(cd|pushd|popd)[[:space:];&|]"
    [[ "$CMD " =~ $CD_RE ]] && CMD_HAS_CD=1
    extract_bash_grep
    [ -z "$PATTERN" ] && extract_bash_find
    [ -z "$PATTERN" ] && extract_bash_lstree
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$PATTERN" ] && exit 0

# --- SEARCH_DIR sanitization (0.0.30, reworked by the 0.0.31 review):
# one central pass for every branch that feeds SEARCH_DIR -- the review
# found that per-branch half-sanitization left gaps. Order matters:
# wildcard truncation first, then the trust decision, then file->parent.
#
# (1) A token still carrying shell wildcards (`/repo/**` cut from
#     `ls /repo/**/*X*`, `src*` from `find src* -name ...`) can never be a
#     literal directory `git -C` could resolve -- before 0.0.31 such a
#     value always failed resolution and took the explicit-target exit
#     with it, silently killing even same-repo augmentation. Keep the
#     longest wildcard-free prefix, cut back to a path-separator boundary
#     (the component holding the wildcard is partial -- never keep it);
#     if no separator survives, the whole token was one glob component and
#     carries no directory information -> discard.
case "$SEARCH_DIR" in
  *[*?]*)
    SEARCH_DIR="${SEARCH_DIR%%[*?]*}"
    case "$SEARCH_DIR" in
      *[/\\]*) SEARCH_DIR="${SEARCH_DIR%[/\\]*}" ;;
      *) SEARCH_DIR="" ;;
    esac
    ;;
esac
# (2) Trust decision. An absolute value (`/...`, or Windows drive-letter
#     `D:/...` / `D:\...`) is taken as-is. UNC paths are deliberately NOT
#     recognized -- they'd point augmentation at a network mount, a
#     per-call ~2s-timeout stall for a shape with no known real usage --
#     and that now covers BOTH spellings: `\\server\share` (never matched
#     an absolute form; its join in the ?* branch fails [ -e ] locally and
#     fast) AND `//server/share`, the spelling Git Bash users actually
#     type since backslashes get eaten -- the adversarial review caught
#     the latter slipping through the `/*` branch into a real, measured
#     ~2s network probe per call. `///...` (3+ slashes) is NOT treated as
#     UNC -- POSIX collapses it to `/...`, so the plain absolute branch is
#     correct for it.
#     0.0.31: a relative value is no longer discarded outright. The old
#     rationale (it would resolve against this hook process's own cwd, not
#     the Bash tool's possibly-drifted shell cwd) doesn't apply when
#     HOOK_CWD is present -- that IS the authoritative shell cwd, so
#     HOOK_CWD/<token> is exactly where the command will actually search
#     (`find ../other-repo -name ...` now resolves to the right repo
#     instead of silently querying the current one) -- UNLESS the command
#     itself changes directory first; see CMD_HAS_CD above. The [ -e ]
#     existence gate keeps non-path tokens the find regex can legitimately
#     capture (`!`, `\(` -- both valid find operators in the search-root
#     position of the regex) from poisoning resolution: they don't exist
#     under HOOK_CWD, so they fall back to the plain HOOK_CWD layer below,
#     which is exactly the pre-0.0.31 behavior for every discarded token.
case "$SEARCH_DIR" in
  //[!/]*) SEARCH_DIR="" ;;
  /*|[A-Za-z]:[/\\]*) ;;
  ?*)
    if [ -z "$CMD_HAS_CD" ] && [ -n "$HOOK_CWD" ] && [ -e "$HOOK_CWD/$SEARCH_DIR" ]; then
      SEARCH_DIR="$HOOK_CWD/$SEARCH_DIR"
    else
      SEARCH_DIR=""
    fi
    ;;
esac
# (3) Grep/Glob's `path` may name a file, not a directory (both tools
#     accept either) -- `git -C` needs a directory. Trim at EITHER
#     separator ([/\\]), not just `/`: the 0.0.31 review's P1 finding was
#     that a backslash-form Windows file path -- accepted as absolute by
#     step (2) -- slipped through a `/`-only trim, fed the untrimmed FILE
#     to `git -C`, and killed the whole resolution; [/\\] also cuts
#     mixed-separator paths at the true last component instead of a
#     shallower `/`.
[ -n "$SEARCH_DIR" ] && [ -f "$SEARCH_DIR" ] && SEARCH_DIR="${SEARCH_DIR%[/\\]*}"
# (3b) The trim above is the one step whose OUTPUT bypasses step (2)'s
#     classification, and it can emit a bare drive letter (`D:` from a
#     file at a drive root). `git -C "D:"` does NOT mean the drive root
#     on Windows -- it's DRIVE-RELATIVE, resolving to this hook process's
#     own per-drive cwd, i.e. a real-but-WRONG repo (adversarial review,
#     field-verified). Normalize to the actual drive root so resolution
#     either succeeds honestly or takes the explicit-target exit below.
case "$SEARCH_DIR" in
  [A-Za-z]:) SEARCH_DIR="$SEARCH_DIR/" ;;
esac

TMO=""
command -v timeout  >/dev/null 2>&1 && TMO="timeout 2"
command -v gtimeout >/dev/null 2>&1 && TMO="gtimeout 2"
# Time-budget model (made explicit by the 0.0.32 review): $TMO bounds each
# individual external call at 2s -- it does NOT bound their sum. The
# theoretical worst case (every resolution git call plus cbm's two
# foreground calls each burning its full slice) exceeds the hook-level
# `timeout: 5` the README/settings templates document. That
# over-subscription is deliberate, not an oversight: locally these calls
# are milliseconds (only a hung network mount ever spends a full slice),
# the external kill is the real ceiling, its cost is one lost augmentation
# (never a blocked tool call), and sizing the hook timeout to the
# theoretical sum would instead make every pathological call stall the
# user's command for that much longer.

# ROOT resolution, most-trusted source first:
#   1. SEARCH_DIR -- an explicit target the command/tool call itself named
#      (absolute, or relative resolved against HOOK_CWD above). If it
#      doesn't resolve to a real git repo, exit here rather than falling
#      through to query the WRONG (session) repo for a pattern the command
#      demonstrably meant for somewhere else -- that would just
#      reintroduce the exact wrong-repo noise this layer exists to remove.
#      ROOT_DYNAMIC marks this source for the cbm exact-match-only rule
#      below (see the PROJECT resolution comment) -- EXCEPT when the
#      resolved target turns out to be the session's own repo (0.0.31
#      review: a Grep path into a subdirectory of the current project,
#      `ls src/*X*` after the relative join): the "guessed target" risk
#      the flag exists for is gone there, and keeping it would only cost
#      coverage. String equality is enough for the comparison: git for
#      Windows normalizes every input form (`D:\...`, `D:/...`, `/d/...`)
#      to one canonical `D:/...` output -- field-verified on all forms --
#      and a mismatch merely leaves fuzzy off, the conservative direction.
#   2. HOOK_CWD -- Claude Code's own authoritative "cwd right now" (tracks
#      cd drift; see the header comment). Same trust tier as today's
#      session-cwd assumption, so the existing cbm fuzzy fallback stays
#      allowed for it -- it isn't a text-parsed guess, it's a fact Claude
#      Code itself reports.
#   3. The pre-0.0.30 fallback: whatever repo this hook process's own
#      inherited cwd happens to sit in (unchanged legacy behavior, e.g. for
#      older Claude Code builds that don't send `cwd`).
# Every resolution call strips GIT_DIR/GIT_WORK_TREE (0.0.31 adversarial
# review, field-verified): an exported GIT_DIR overrides `-C` entirely --
# every rev-parse below would silently collapse to that one repo, making
# ROOT wrong AND the ROOT==SESSION_ROOT comparison trivially true. All
# calls carry $TMO, including the plain legacy fallbacks (TMO is computed
# early enough since 0.0.30; the review caught the SESSION_ROOT fallback
# missing it).
# GIT_CLEANENV (0.0.32: renamed from the opaque GITRP -- the name now says
# what it does): git with the two environment overrides stripped.
GIT_CLEANENV="env -u GIT_DIR -u GIT_WORK_TREE git"

# The session's own repo toplevel: HOOK_CWD first (authoritative,
# cd-drift-tracking), then the hook process's own inherited cwd (legacy,
# for builds that don't send `cwd`). Sets SESSION_ROOT; empty means "no
# session repo resolvable". One function because the ROOT_DYNAMIC
# comparison and the non-dynamic ROOT fallback below need the exact same
# ladder (0.0.32: they were two shape-identical copies).
resolve_session_root() {
  SESSION_ROOT=""
  [ -n "$HOOK_CWD" ] && SESSION_ROOT=$($TMO $GIT_CLEANENV -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$SESSION_ROOT" ] && SESSION_ROOT=$($TMO $GIT_CLEANENV rev-parse --show-toplevel 2>/dev/null)
}

ROOT=""
ROOT_DYNAMIC=""
if [ -n "$SEARCH_DIR" ]; then
  ROOT=$($TMO $GIT_CLEANENV -C "$SEARCH_DIR" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$ROOT" ]; then
    ROOT_DYNAMIC=1
    resolve_session_root
    [ "$ROOT" = "$SESSION_ROOT" ] && ROOT_DYNAMIC=""
  else
    exit 0
  fi
fi
if [ -z "$ROOT" ]; then
  resolve_session_root
  ROOT="$SESSION_ROOT"
fi
[ -z "$ROOT" ] && exit 0

# codegraph branch: kicked off in the background first since it has no
# dependency on cbm's project-name resolution, so it runs concurrently
# with cbm's two sequential calls below instead of adding its own time on
# top of them (merging two previously-parallel hook processes into one
# sequential script would otherwise roughly double the worst-case wall
# time against the same hook-level timeout).
# Requires $TMO to be non-empty (a real `timeout`/`gtimeout` wrapper) --
# unlike the old two-script layout, where the single CLI call was the
# whole script's foreground blocking work (so an external hook-timeout
# kill of the parent basically took it down too), this call is now
# backgrounded: with no internal time bound of its own, a hang could in
# theory outlive a killed parent as an orphaned process. Skipping this
# branch entirely when neither timeout binary is available -- rather than
# running it unbounded -- avoids introducing that risk; the repo already
# treats a missing `codegraph` binary or missing `.codegraph/` dir as "this
# side just doesn't run," so treating "can't bound its runtime" the same
# way is consistent, not a loss of coverage beyond what those cases already
# accept.
CGTMP=""
CG_PID=""
if [ -d "$ROOT/.codegraph" ] && command -v codegraph >/dev/null 2>&1 && [ -n "$TMO" ]; then
  CGTMP=$(mktemp 2>/dev/null) || CGTMP=""
  if [ -n "$CGTMP" ]; then
    trap 'rm -f "$CGTMP"' EXIT
    (
      RAW=$($TMO codegraph query "$PATTERN" -j -l 5 -p "$ROOT" 2>/dev/null)
      printf '%s' "$RAW" | jq -c '[.[] | {name: .node.name, kind: .node.kind, file: .node.filePath}]' 2>/dev/null > "$CGTMP"
    ) &
    CG_PID=$!
  fi
fi

# cbm branch: runs in the foreground, unchanged two-step shape (project
# name resolution, then search_graph) -- these two steps are sequentially
# dependent and can't be parallelized against each other.
# Deliberately NOT `|| exit 0` after PROJECT=/MATCH= like the old standalone
# cbm-augment.sh did: an empty PROJECT/MATCH just falls through the `if
# [ -n ... ]` guards below and leaves CBM_JSON at its "[]" default -- no
# `set -e` in this script, so that's safe. An early `exit 0` here would be a
# real bug in the merged script: it would abandon the codegraph query
# already running in the background (CG_PID never waited/merged) even
# though it may already have a usable result. Keep it this way even if it
# looks less "defensive" than the old per-branch fail-fast style.
CBM_JSON="[]"
if command -v codebase-memory-mcp >/dev/null 2>&1; then
  BASE=$(basename "$ROOT")
  FLAT=$(printf '%s' "$ROOT" | sed 's|^[/\\]||; s|[/\\]|-|g')
  # 0.0.30: the endswith() fuzzy fallback below is only safe when ROOT is
  # the hook's own trusted default (today's assumption, or HOOK_CWD -- an
  # authoritative fact from Claude Code, not a guess). When ROOT instead
  # came from SEARCH_DIR (parsed out of the command/tool-call text), a
  # fuzzy name match can confidently return a REAL but WRONG project (e.g.
  # `find /d/data/Vue -name '*Controller*'` resolving correctly to
  # `/d/data/Vue`, then `endswith("Vue")` matching an unrelated indexed
  # `d-data-RuoYi-Vue`) -- same failure tier as the 0.0.29 `-prune`/
  # node_modules case: real-looking, wrong. Require exact FLAT/BASE
  # equality only in that case. (0.0.31: ROOT_DYNAMIC is cleared upstream
  # when the dynamic target resolved to the session's own repo -- see the
  # ROOT resolution comment.)
  PROJECT=$($TMO codebase-memory-mcp cli list_projects 2>/dev/null \
    | jq -r --arg f "$FLAT" --arg b "$BASE" \
        --argjson fuzzy "$([ -n "$ROOT_DYNAMIC" ] && printf false || printf true)" '
        [.projects[]?.name // empty] as $n
        | ( ([$n[] | select(.==$f)] + [$n[] | select(.==$b)])[0]
          // (if $fuzzy then ([$n[] | select(endswith($b))] | first) else empty end)
          // empty )' 2>/dev/null)
  if [ -n "$PROJECT" ]; then
    MATCH=$(jq -n --arg p "$PROJECT" --arg q "$PATTERN" '{project:$p, name_pattern:$q, limit:5}' \
      | $TMO codebase-memory-mcp cli search_graph 2>/dev/null \
      | jq -c '[.results[]? | {name, file: (.file_path // .file // null)}]' 2>/dev/null)
    [ -n "$MATCH" ] && CBM_JSON="$MATCH"
  fi
fi

CG_JSON="[]"
if [ -n "$CG_PID" ]; then
  wait "$CG_PID" 2>/dev/null
  FROM_FILE=$(cat "$CGTMP" 2>/dev/null)
  [ -n "$FROM_FILE" ] && CG_JSON="$FROM_FILE"
fi

{ [ "$CBM_JSON" = "[]" ] || [ -z "$CBM_JSON" ]; } && { [ "$CG_JSON" = "[]" ] || [ -z "$CG_JSON" ]; } && exit 0

# Merge: dedupe on (name, file), tag each hit with which tool(s) found it.
# A "both" tag -- codegraph's fuzzy full-text match and cbm's exact/regex
# name match independently agreeing on the same symbol -- is a stronger
# signal than either tool alone can produce, and only exists because this
# is now one process able to compare both result sets directly. Ordering:
# "both" first, then codegraph-only and cbm-only interleaved preserving
# each side's own original order, capped at 8 total (below today's worst-
# case 10-row two-injection total, above either tool's solo 5-row cap so
# genuinely complementary recall isn't clipped).
MERGED=$(jq -n --argjson cbm "$CBM_JSON" --argjson cg "$CG_JSON" '
  def key: [.name, .file];
  ($cbm // []) as $cbm |
  ($cg  // []) as $cg  |
  ($cbm | map(key)) as $cbmKeys |
  ($cg  | map(key)) as $cgKeys  |
  ($cg  | map(. + {src: (if (key | IN($cbmKeys[])) then "both" else "cg" end)})) as $cgTagged |
  ($cbm | map(. + {src: "cbm"}) | map(select((key | IN($cgKeys[])) | not))) as $cbmOnly |
  ([$cgTagged[] | select(.src=="both")]) as $both |
  ([$cgTagged[] | select(.src=="cg")]) as $cgOnly |
  ( [range(0; ([$cgOnly, $cbmOnly] | map(length) | max))]
    | map( [ $cgOnly[.], $cbmOnly[.] ] | map(select(. != null)) )
    | add // []
  ) as $interleaved |
  ($both + $interleaved)[0:8]
' 2>/dev/null)

{ [ -z "$MERGED" ] || [ "$MERGED" = "[]" ]; } && exit 0

jq -n --argjson m "$MERGED" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  additionalContext: ("Knowledge-graph symbol matches for this pattern: " + ($m|tostring) + " (src: both = confirmed by exact-name AND full-text matching independently, cg = codegraph only, cbm = codebase-memory-mcp only) — consider the code-navigator skill for structural follow-ups.")}}'
exit 0
