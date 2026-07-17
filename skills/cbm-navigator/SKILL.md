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
3. **Both `.codebase-memory/` and `.codegraph/` present in the same repo?**
   Priority order for picking between the two tools: **accuracy first, then tokens, then speed** — never pick by habit.
   For single-symbol questions (who calls X, show me X, what breaks if I change X, interface→impl): prefer `codegraph-navigator` — its `node`/`explore` synthesize the Java interface/impl edge automatically in ONE call (`[dynamic: interface → impl]`), where this skill needs a mandatory 2-call union (interface + impl) every time to reach the same accuracy — same accuracy ceiling, fewer tokens and one round-trip faster on codegraph's side.
   For whole-graph AGGREGATE questions (dead code, hubs/god-classes, cross-layer violations): prefer THIS skill's `cbm-cypher.sh` — codegraph has no raw graph-query equivalent and its `explore` command is field-verified to produce confidently-wrong answers for these three shapes (see `codegraph-navigator/references/blindspots.md`).
   `cbm-cypher.sh`'s templates are field-verified accurate as of 2026-07-17 (2 of the 5 had real bugs, now fixed — see this skill's own `references/blindspots.md`), with documented per-template caveats (see Quality rules and the Decision table below).
   For "list all routes": codegraph's `cg-find.sh -k route` is field-verified to be an exact enumeration AND includes the HTTP verb in the name (`cbm-cypher.sh routes`'s Cypher schema does not model the verb) — prefer codegraph's when both are available.
   If the user names a tool explicitly, use that one.

All scripts auto-resolve the project name; never pass or guess it.
All scripts print compact JSON; never re-run with higher limits — paginate.

## Decision table (question type → ONE script, in one shot)

| Question shape | Script | Notes |
|---|---|---|
| "Where is X / list all X" | `scripts/cbm-find.sh 'X'` | regex ok: `'.*Handler'`; add label: `-l Class\|Function\|Method\|Interface\|Route` |
| business-language question, Chinese term(业务词) | `scripts/cbm-grep.sh '退款审核'` | literal text match over source incl. Chinese Javadoc — field-verified 2026-07-17: `-s` semantic search does NOT work for Chinese query text (scores in the same near-random range regardless of phrasing), this is the correct tool instead |
| business-language question, English term | `scripts/cbm-find.sh -s 'refund approval'` | semantic vector search — field-verified reliable for English keyword queries (had 2 real bugs, now fixed, see references/blindspots.md); ALWAYS check the returned `hint` — a top score below 0.3 means the match is unreliable, fall back to `cbm-grep.sh` |
| "Who calls X / what does X call / call chain" | `scripts/cbm-trace.sh <exact-name> [in\|out\|both]` | needs EXACT name → run cbm-find first if unsure |
| "What breaks if I change ..." (uncommitted diff) | `scripts/cbm-impact.sh` | maps git diff → impacted symbols + risk |
| "Show me the code of X" | `scripts/cbm-snippet.sh <qualified-name>` | qualified name comes from cbm-find output; CHEAPER than Read on whole file |
| "Architecture / modules / entry points / routes overview" | `scripts/cbm-arch.sh` | one call, cache mentally for the session |
| "Dead/unused code" — plain functions, non-OOP code | `scripts/cbm-cypher.sh dead-code` | field-verified (2026-07-17) reliable EXCEPT every Java interface method false-positives here (separate bug from the Impl-side one below, see references/blindspots.md) — do not trust a `*Service`/`I*`-shaped hit without cross-checking `cbm-trace.sh` first; capped at 100 rows, script warns on stderr if the true total is higher (verified: 348 on RuoYi-Vue-Plus) — do not report the shown rows as the complete list when that warning fires |
| "Dead/unused code" — Java class methods | `scripts/cbm-cypher.sh dead-code-methods` | ALWAYS union with the matching interface method via `cbm-trace.sh` before reporting any `*Impl` hit as dead — see Quality rules; capped at 100 rows, script warns if truncated (verified: 1159 on RuoYi-Vue-Plus, over 90% hidden by the cap — expect this warning to fire often on real repos) |
| "Which classes/god-classes have the most callers" (hubs) | `scripts/cbm-cypher.sh hubs` | field-verified fixed 2026-07-17 (was completely non-functional — ordered by a property that doesn't exist); now aggregates real inbound calls per class. Java/class-oriented repos only — returns empty on function-oriented JS/TS/Vue repos, that's a real modeling gap, not a query bug. Top-20 by design, not subject to the truncation warning below |
| "Controller calling Mapper directly" (layer violations) | `scripts/cbm-cypher.sh cross-layer [layerA] [layerB]` | field-verified fixed 2026-07-17 (the zero-arg default used to hard-crash the Cypher parser); `layerA`/`layerB` args are sanitized before use, capped at 200 rows with the same truncation warning as above |
| "List all routes" | `scripts/cbm-cypher.sh routes` | field-verified accurate per-row, but WAS silently capped at 200 against a true count of 303 on RuoYi-Vue-Plus (34% hidden) until a 2026-07-17 review caught it — now warns on truncation; if `.codegraph/` is ALSO present, prefer `cg-find.sh -k route` instead — same accuracy, no cap at this repo's scale, includes the HTTP verb, cheaper (no Cypher round-trip) |
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
- **`cbm-cypher.sh dead-code` (the `Function`-label template) has a DIFFERENT, also-mandatory caveat (field-verified 2026-07-17): every Java interface method is reported dead regardless of real usage** — interface declarations are double-registered as both a `Function` node and a `Method` node, and only the `Method` twin ever receives inbound `CALLS` edges.
  This is not the same bug as the Impl-side rule above (that one is about `dead-code-methods`); this one hits the interface declaration itself, in the OTHER template.
  Cross-check any `*Service`/`I*`-shaped hit with `cbm-trace.sh` before reporting it dead; genuinely reliable for ordinary non-interface functions.
- **`CALLS` edges resolve by method name ONLY — no parameter count/type or receiver-type check (field-verified 2026-07-17, MANDATORY for any `get`/`set`/`is`-shaped name).** A business method whose name collides with a same-named Lombok-generated getter/setter on an unrelated DTO/VO/BO/Entity class gets its caller list polluted by every unrelated call to that accessor — confirmed on `DictService.getDictLabel`: 6 of 10 "callers" `cbm-trace.sh` returned were really calls to `SysDictDataVo.getDictLabel()` (an unrelated 0-arg Lombok getter), only 4 were real.
  Before reporting a caller/callee count or list for a `get`/`set`/`is`-prefixed method (or any name also used by MyBatis-Plus's `BaseMapper`, e.g. `updateById`/`selectList`), read the actual call site for at least a sample of the results — a 0-argument call site on a `get`/`is` name is a strong tell it's hitting the accessor, not your target. See `references/blindspots.md` for the full repro and the inverse false-negative consequence for dead-code detection.
- **`cbm-cypher.sh`'s `dead-code`/`dead-code-methods`/`cross-layer`/`routes` templates are capped (100/100/200/200 rows) and now self-report truncation (field-verified 2026-07-17, added in a code-review pass): if the JSON on stderr contains a `"results capped at N of M total"` warning, the M-row rows you did NOT get are real data, not noise.**
  Never state or imply the returned rows are the complete list when this warning is present — say "at least N" or re-run with a narrower filter instead.
  `hubs` is exempt by design (an intentional top-20 ranking has no "true total" to compare against).
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
