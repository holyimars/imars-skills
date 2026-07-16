---
name: cbm-navigator
description: >
  Query this repo's pre-built code knowledge graph (codebase-memory CLI) for structural questions: where a symbol is defined, who calls it, call chains (调用链/调用关系), change impact / blast radius (影响面/改动影响), architecture overview (架构/模块划分), dead code (死代码/无用代码), cross-layer violations, API routes, and "which module handles X" (哪个模块/哪里实现).
  One graph call replaces dozens of grep/read rounds.
  Do NOT use for tiny repos (under ~1,000 lines of code), MyBatis XML, Laravel Eloquent/facade/Blade magic, comments/docs, or single-line questions — use native grep/read there.
---

# CBM Navigator — accurate & efficient calling protocol

## Gate check (before ANY graph call — installed globally ≠ applicable everywhere)
1. **Tiny repo? Skip this skill entirely.**
   If the current repo is under ~1,000 lines of code (a handful of source files; `list_projects` shows a node count in the low hundreds), do NOT use the graph — native grep/read is just as accurate and faster at this scale.
   Answer with native tools.
2. **Effort awareness (team-measured fact).**
   Retrieval quality is capped by the reasoning/output token budget: at low/medium effort, accuracy is LOWER than at high/xhigh/max — the graph does not lift this cap.
   Weigh this when stating conclusions, and see Quality rules for when to delegate or recommend higher effort.

All scripts auto-resolve the project name; never pass or guess it.
All scripts print compact JSON; never re-run with higher limits — paginate.

## Decision table (question type → ONE script, in one shot)

| Question shape | Script | Notes |
|---|---|---|
| "Where is X / list all X" | `scripts/cbm-find.sh 'X'` | regex ok: `'.*Handler'`; add label: `-l Class\|Function\|Method\|Interface\|Route` |
| business-language question(业务词) | `scripts/cbm-find.sh -s '退款审核'` | semantic vector search |
| "Who calls X / what does X call / call chain" | `scripts/cbm-trace.sh <exact-name> [in\|out\|both]` | needs EXACT name → run cbm-find first if unsure |
| "What breaks if I change ..." (uncommitted diff) | `scripts/cbm-impact.sh` | maps git diff → impacted symbols + risk |
| "Show me the code of X" | `scripts/cbm-snippet.sh <qualified-name>` | qualified name comes from cbm-find output; CHEAPER than Read on whole file |
| "Architecture / modules / entry points / routes overview" | `scripts/cbm-arch.sh` | one call, cache mentally for the session |
| whole-graph patterns: dead code, controller→mapper violations, god classes, route list | `scripts/cbm-cypher.sh dead-code\|cross-layer\|hubs\|routes` | one scan beats N searches |
| literal text / string / SQL fragment | `scripts/cbm-grep.sh '<text>'` | graph-scoped grep |

## Mandatory sequences (accuracy protocol)
1. trace/snippet need exact names.
   Unknown name → `cbm-find.sh` FIRST, copy the exact `name` / `qualified_name` from its output.
   Never invent names.
2. First structural question in a session on an unfamiliar area → `cbm-arch.sh` once to ground yourself, then targeted calls.
3. If any script returns `{"results": []}` or an error, follow the `hint` field it prints (e.g. broaden pattern, or fall back to native grep).
   Do not retry the same call unchanged.

## Quality rules (non-negotiable)
- Team-measured: answer accuracy is capped by the reasoning/output token budget — low/medium effort limits retrieval quality REGARDLESS of the graph.
  For impact analysis, change decisions, or anything the user will act on: DELEGATE to the `cbm-deep-analyst` subagent — it runs at elevated effort in an isolated context, verifies via source reads, and returns only conclusions.
  If that agent is unavailable, recommend the user re-run at high effort (/effort) and verify conclusions with native Read/LSP on the key code paths.
- The graph LOCATES and STRUCTURES; it does not conclude.
  Before stating any business-logic conclusion, read the actual source: `cbm-snippet.sh` for a function, or Read on the file path the graph returned.
- **Java: querying callers/impact/dead-code on an `*Impl` class method (field-verified, MANDATORY, not an edge case)**: the call edge attaches to the INTERFACE method, never the impl method — reproduces on plain single-impl `IFoo`→`FooImpl` pairs, not just multi-impl cases.
  A "0 callers" result on an impl method proves nothing by itself.
  ALWAYS also query the interface's copy of the method and take the union before reporting a count, "unused", or "safe to remove".
  See `references/blindspots.md` for the confirmed repro.
- Route paths: class-level `@RequestMapping` prefixes were field-verified PRESENT (not dropped) across 3 real controllers on the currently installed version — do not assume prefix-loss by default.
  Upstream issue #734 (prefix dropped) is real but open/unfixed upstream as of this writing; if a route path looks truncated or wrong, spot-check the one controller in question against source rather than assuming it's systemic.
- Code changed after the last sync may be missing: if the user references a change from minutes ago, prefer reading the working tree.

## Fall back to native grep/glob/read (do NOT use the graph)
- Framework magic (see references/blindspots.md for how to grep these instead): MyBatis mapper XML / dynamic SQL; Laravel facades, Eloquent magic methods/scopes, Blade logic; Django dynamic URLconf / signals; reflection-driven dispatch; runtime bean-name lookups (`getBean(computedName)`).
- Vue/React route-level lazy loading (`() => import('...')`): dynamically-imported route components produce NO graph edge (field-verified).
  Grep the router config directly for "who routes to this component" instead.
- Comments, docstrings, README semantics; single-file line-level questions.

## Cross-repo questions (frontend + backend split, or any multi-repo project pair)
- Each repo is indexed as its own independent graph — there is no aggregated multi-root graph.
  A question spanning both repos (e.g. "which frontend page calls this backend API") needs one graph call per project (pass the right `--name`/project) plus manual correlation of the results; the graph will not join across repos for you.

## Token discipline
- Keep default limits (20); paginate with `-o <offset>` when truly needed.
- Trace depth defaults to 3; raise to 5 only when the user asks for the full chain.
- Summarize graph JSON in prose; never paste raw tool output to the user.
