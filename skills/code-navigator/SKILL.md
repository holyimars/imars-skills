---
name: code-navigator
description: >
  Query this repo's pre-built code index/graph for structural questions: where a symbol is defined, who calls it, call chains (调用链/调用关系), change impact / blast radius (影响面/改动影响), architecture overview (架构/模块划分), dead code (死代码/无用代码), hubs/god-classes, cross-layer violations, API routes, which tests cover a change, and "which module handles X" (哪个模块/哪里实现).
  Works with either or both of two independent CLI-only indexes — `codebase-memory-mcp` (index product `.codebase-memory/`) and `codegraph` (index product `.codegraph/`) — picking whichever is actually installed and best suited to the question shape; the two are unrelated tools with unrelated indexes, having one does not imply the other.
  Do NOT use for tiny repos (under ~1,000 lines of code), MyBatis XML, Vue/React dynamic `import()` route lazy-loading, Laravel Eloquent/facades/Blade logic, Django dynamic URLconf, comments/docs, or single-line questions — use native grep/read there.
---

# code-navigator — accurate & efficient calling protocol

This skill replaces two formerly-separate integrations (`cbm-navigator` for codebase-memory-mcp, `codegraph-navigator` for codegraph) that used to ship independent SKILL.md files with no cross-reference — a real gap, since the two tools' arbitration logic ("which one wins when both are installed") used to live only inside each skill, unreachable from the always-loaded CLAUDE.md layer.
This file is the single, merged decision surface.
The two CLIs' 16 query scripts (`cbm-*.sh` / `cg-*.sh`) are unchanged, just consolidated under this one skill's `scripts/`.

## Gate check (before ANY call)

1. **Index detection — four possible states, check both independently.**
   Only `.codebase-memory/` present → cbm-side scripts only, degrade gracefully on rows below that name codegraph first.
   Only `.codegraph/` present → cg-side scripts only, same degradation in reverse.
   Both present → follow the Decision table's priority order as written; it already encodes the accuracy-first arbitration, no further tool-vs-tool judgment call needed.
   Neither present → this skill does nothing; use native grep/Read for everything, and tell the user which `init`/`index_repository` command would set one up if the question recurs.
2. **Tiny repo? Skip this skill entirely.**
   Under ~1,000 lines of code (`cg-arch.sh`'s `nodeCount`, or `cbm-arch.sh`'s node count, in the low hundreds) — native grep/read is just as accurate and faster at this scale.
   Installed globally ≠ applicable everywhere.
3. **Effort awareness (team-measured fact, applies to both CLIs equally).**
   Retrieval quality is capped by the reasoning/output token budget: at low/medium effort, accuracy is LOWER than at high/xhigh/max — no graph tool lifts this cap.
   For impact analysis, change decisions, or any structural conclusion the user will act on: delegate to the `deep-analyst` subagent (elevated effort, isolated context, verifies via source reads before returning a conclusion).
   If that agent is unavailable, recommend the user re-run at high effort (`/effort`) and verify conclusions with native Read on the key code paths.
4. **Freshness.**
   codebase-memory-mcp: re-indexing manually requires an ABSOLUTE `--repo-path` and an explicit `--name` — a relative path with no `--name` was field-verified to silently create a second, duplicate project instead of updating the existing one.
   codegraph: use `codegraph sync .` for routine incremental updates (seconds); never run a full `codegraph index --force` while any other `codegraph` command (even a read-only `query`) might still be in flight in the same session — field-verified on Windows to hard-fail with `EPERM: database file is in use` (aborts cleanly, no corruption, but no retry either).
   If the user mentions a change from the last few minutes, sync first or read the working tree directly.
5. **User names a tool explicitly → use that one, skip the arbitration.**
6. **Cross-repository questions** (e.g. a frontend + backend split): each repo is its own independent index, there is no aggregated multi-root graph. A question spanning both needs one call per project plus manual correlation of the results — neither tool joins across repos.

LSP is NOT part of this gate check — it has no persistent index to detect. See "LSP collaboration" below: it is tried opportunistically per single-symbol question, not gated on session start.

All scripts resolve the repo root via `git rev-parse --show-toplevel` (or cwd) automatically. cbm-side scripts auto-resolve the project name (codebase-memory-mcp's own project registry); cg-side scripts need no name (codegraph resolves per-directory) — never pass or guess either.

## Decision table (question shape → ONE script, in one shot)

| Question shape | Priority chain (degrade to what's actually installed) | Key constraint / mandatory step |
|---|---|---|
| Symbol location, EXACT file/class/component name already known | Native Glob (`**/<ExactName>.*`) — skip both graph tools entirely | Field-verified (2026-07-18, both repos): Glob was faster (up to 18x), cheaper, and equally-or-more precise than either graph tool in every tested case where the exact name was already known — the graph tools only added fuzzy-match noise and 3-18x latency for zero accuracy gain here. Fall through to the row below only if Glob finds nothing or multiple ambiguous hits |
| Symbol location, fuzzy/partial name ("where is X", not sure of the exact name) | `cg-find.sh` (optionally `-k <kind>`) > `cbm-find.sh` (regex, optionally `-l <Label>`) > native Grep | Precondition for trace/impact/node/snippet below — never invent a name, always copy the exact `qualified_name` from this step's output |
| Show a symbol's source + context | `cg-node.sh` (source + both-direction callers + `[dynamic: interface → impl]` label, one call) > `cbm-snippet.sh` > native Read | Needs an exact name from the row above; if `cg-node.sh`/`cg-explore.sh` already printed the source block, that satisfies "read the source before concluding" — no separate Read needed |
| Exhaustive listing of a kind (all routes/classes/interfaces/components) | `cg-find.sh -k <kind>` with an EMPTY pattern (field-verified exact: 303/303 routes, 482/482 classes, 99/99 components — route names include the HTTP verb) > for routes specifically, `cbm-cypher.sh routes` (self-reports truncation past its row cap — a warning means "at least N", not "all N"; no HTTP verb in this template) > for other kinds via cbm, `cbm-find.sh` with `-l <Label>` (exhaustiveness NOT field-verified for non-route kinds, say so) > native grep (accept the manual composition cost) | When both installed, prefer codegraph: same accuracy, cheaper, and includes the verb. **NEVER use `cg-explore.sh` for this** — field-verified to keyword-match "list" against methods literally named `list` and surface zero real routes |
| Who calls X / call chain | `cg-trace.sh` (auto-bridges the Java interface→impl gap; when it reports `bridged: true`, cross-check with `cg-node.sh`/`cg-explore.sh` before stating a final count) > `cbm-trace.sh` queried on the **INTERFACE side ONLY** PLUS a **MANDATORY** second query against the interface method if the first hit was the impl, union the results, every time, no exceptions (the Cypher engine cannot express this 2-hop bridge at all) > native grep | Tool-independent mandatory checks apply regardless of which graph tool answered — see "Interface-method call-chain — mandatory checks" right after this table for the full numbered checklist (getBean/getAopProxy/globalProperties greps, Lombok sample-read, wrong-side warning, why running both graph tools doesn't help here, LSP corroboration) |
| Impact / blast radius, symbol-anchored ("what breaks if I change X") | `cg-impact.sh` (multi-hop, default depth 2, already bridges interface/impl; raise `-d` if an expected Route node is missing) > cbm has no symbol-anchored equivalent, approximate with `cbm-trace.sh` + the interface-union protocol above > native grep | Same `SpringUtils.getBean(X.class)` mandatory grep as the row above; any conclusion the user will act on → delegate to `deep-analyst` |
| Impact, uncommitted-diff-anchored ("what do my current changes affect") | `cbm-impact.sh` (diff → impacted symbols + risk) and `cg-affected.sh` (diff → covering tests) are COMPLEMENTARY, not alternatives — run both if both are installed | Each tool owns half of this question shape; there is no overlap to arbitrate |
| Which tests cover this change | `cg-affected.sh` — cbm has **no equivalent capability** at all > native grep of test directories | High `totalDependentsTraversed` in the output makes a "no covering tests" conclusion more trustworthy |
| Exploratory compound question ("how does X reach Y", "why does Z happen"), English or containing ≥1 Latin identifier | `cg-explore.sh` (flagship: one call returns relevant symbols' source + call paths + blast radius, including interface/impl synthesis) — cbm has no one-call equivalent, chain `cbm-find.sh` → `cbm-trace.sh` → `cbm-snippet.sh` manually if only cbm is installed > native | Quickly skim the returned symbol list for relevance — field-verified to occasionally pull in a keyword-coincidence match even on its strong-case questions; scoped to single-area questions only, see the three aggregate rows below for whole-graph shapes |
| Business term → module, English | `cg-explore.sh` (if the question is compound) or `cbm-find.sh -s` (semantic search, field-verified reliable for English; a top score below 0.3 in its own hint means fall back to `cbm-grep.sh`) or `cg-find.sh` (FTS) | |
| Business term → module, pure Chinese, Java/backend repo | `cbm-grep.sh` (literal text match, confirmed to hit Chinese Javadoc) or `cg-find.sh` (FTS, confirmed reliable on Chinese) — either is fine | **NEVER** `cg-explore.sh` (field-verified: returns empty on every pure-Chinese query tested, needs ≥1 Latin-script anchor token) and **NEVER** `cbm-find.sh -s` (Chinese scores near-random regardless of phrasing). If the term is mixed Chinese+Latin (≥1 identifier in Latin script alongside the Chinese words), that anchor token makes `cg-explore.sh` viable again — route back to the exploratory-compound row above instead of this one |
| Business term → module, pure Chinese, Vue/TS/frontend repo | `cbm-grep.sh` **only** — do not treat `cg-find.sh` as an equal alternative here | Field-verified (2026-07-18, plus-ui): `cg-find.sh` failed systematically, 0/6 real Chinese terms found across two test rounds regardless of whether the term sat next to a Latin identifier — looks like a CJK-tokenizer gap in codegraph's FTS layer on this repo shape, not a query-shape fluke. `cbm-grep.sh` found 6/6, byte-for-byte matching independent manual grep every time. Same `cg-explore.sh`/`cbm-find.sh -s` prohibitions as the row above apply |
| Architecture overview / hotspots | `cg-arch.sh` or `cbm-arch.sh` — either is fine, use whichever is installed | `cbm-arch.sh`'s `fan_in` numbers should only be trusted as relative ranking (~4% deviation from a real grep count observed) — aggregate stats tolerate name-collision noise far better than a single-target trace does |
| Dead code | `cbm-cypher.sh` — **the only capability that exists for this shape**, codegraph has none. Java class methods → `dead-code-methods` PLUS the mandatory interface-union protocol above; plain functions → `dead-code` (every Java interface method is reported dead regardless of real usage — a separate Function/Method double-registration issue — cross-check any `*Service`/`I*`-shaped hit with `cbm-trace.sh`) | Both templates self-report truncation past their row cap (field-verified real totals of 348/1159 far exceeding the shown 100) — a truncation warning means "at least N," never the full list; name-only resolution also produces a false-NEGATIVE direction (an unrelated same-named getter can make a truly dead method look used). **NEVER substitute `cg-explore.sh`** — field-verified to keyword-match "find"/"dead" against unrelated method names like `findFirst` and report them dead despite real callers, with the same confident formatting as a correct answer. **A raw "dead" verdict can be completely wrong, not just imprecise** — field-verified: 3 candidates flagged dead by the raw query were 0/3 actually dead once run through the full cross-check chain (graph trace + `SpringUtils.getBean`/`getAopProxy` grep + Read), so treat the raw list as candidates to disprove, not a conclusion. Requiring a second graph tool to "agree" is not sufficient proof either — if both tools share the same underlying blind spot (e.g. `getAopProxy(this)` self-invocation), they will agree and both be wrong; only a native grep for ANY textual reference to the method name, cross-checked by reading the actual call site, closes this. Neither tool installed → say plainly there is no low-cost native substitute |
| Hubs / god-classes | `cbm-cypher.sh hubs` — **the only capability**, top-20 by design (not subject to the truncation warning above) | Class/OOP-oriented repos only — returns empty on function-oriented JS/TS/Vue repos, a real modeling gap, not a bug. **NEVER substitute `cg-explore.sh`**, same failure mode as dead code above |
| Cross-layer violations (e.g. Controller calling Mapper directly) | `cbm-cypher.sh cross-layer [layerA] [layerB]` — **the only capability**, args are sanitized, 200-row truncation self-reported | **NEVER substitute `cg-explore.sh`**, same failure mode as dead code above |
| Class inheritance (`extends` / "what does X inherit from") | Native grep of the `class X extends Y` declaration line — **the only reliable path** | codegraph's graph is one-directional (querying a subclass never reveals its parent, matches upstream open issue #1328; querying the parent DOES list subclasses, but mislabeled under a `Called by ←` heading — don't misread that as a call relationship); codebase-memory-mcp never modeled this relationship in either direction |
| Framework magic: MyBatis XML mapper binding, Vue/React dynamic `import()`, Spring `getBean(runtime-computed-name)`, Laravel/Django dynamic dispatch | Native grep/Read — **the only path**, switching graph tools does not help | See `references/lsp-and-native-fallbacks.md` for the full repro and grep recipe on each; the computed-bean-name case is genuinely undecidable without running the code, codegraph's all-implementations fan-out there is an honest candidate enumeration, not a resolved answer |
| Config-binding consistency (`@Value("${key}")` ↔ `application.yml`; `import.meta.env.VITE_X` ↔ `.env`) | Native grep both sides (the annotation/usage site, then the config file) + Read to confirm the value — do not rely on either graph tool alone | Neither is a clean "zero visibility" case (correcting an earlier assumption): `cg-find.sh` unexpectedly indexes some `.yml` keys as `constant` nodes linked to `@Value` sites (field-verified, but not confirmed to extend to `.properties` or profile-specific `application-*.yml`); `cbm-grep.sh` (not `cbm-find.sh`) partially sees `.env` files, modeled as a Module node. Neither is complete enough to skip the native grep+Read — treat any graph hit here as a lead to verify, not an answer |
| Cross-repo consistency (e.g. "does this frontend API call have a matching backend route") | Native grep on both repos' trees (extract the URL/path fragment on one side, grep for it on the other) + `cg-find.sh -k route` on the backend side as a structural cross-check | Neither tool has ANY cross-repo capability — each resolves strictly to its own cwd's git-toplevel repo (see Gate check item 6); this question shape is manual-correlation-only, field-verified 3/3 real API-to-route matches found this way on RuoYi-Vue-Plus/plus-ui |
| Literal text / string / SQL fragment | Native Grep first choice; `cbm-grep.sh` (graph-scoped grep) also works | codegraph has no text-search command |
| Comments / docs / single-file line-level question | Native Read | |

(The <1,000-line tiny-repo skip, index-presence detection, effort delegation, and freshness rules live in the Gate check above, not as table rows.)

### Interface-method call-chain — mandatory checks (detail for the "who calls X" row)

Whichever graph tool answered, run these before reporting a final caller count for an interface method — none of them are optional, and none are satisfied by picking a different graph tool instead:

1. If the target is an interface method, grep `SpringUtils.getBean(<Interface>.class)` before reporting a final count — codegraph is confirmed 0/2 blind to this call shape; cbm's name-only resolution may incidentally surface it but buried in noise, so neither tool's silence/noise can be trusted alone.
2. ALSO grep `SpringUtils.getAopProxy(this).<method>(` when the target carries `@Cacheable`/`@CachePut`/`@CacheEvict` or another AOP-relevant annotation — a field-verified sibling of the getBean gap (self-invocation through the AOP proxy to trigger the annotation), invisible to both `cbm-cypher.sh dead-code-methods` and `cg-trace.sh`/`cg-node.sh` at once, so their agreement here is NOT corroboration (see the "shared blind spot" Quality rule below).
3. If the target is a Vue/React function registered on `app.config.globalProperties` (check `src/plugins/index.ts` or equivalent), grep `proxy\.<name>\|\.<name>(` directly — field-verified 3/3 on real functions (`parseTime`, `handleTree`, `addDateRange`): both graph tools recalled ~0-1/10-19 real call sites for this call shape, native grep recovered all of them in <100ms every time.
4. If the name is `get`/`set`/`is`-shaped or a common `BaseMapper` name (`updateById`/`selectList`) AND the answer came from cbm, sample-read the actual call sites before trusting the count — see the Quality rules' `CALLS`-edge name-resolution bullet below for the accuracy evidence; codegraph does not have this collision.
5. Querying `cbm-trace.sh` on the WRONG (impl) side is silently dangerous — field-verified TWICE to return confidently-formatted callers that were 100% false positives, with no warning distinguishing it from a correct answer. Always confirm which side you queried — the chain above says INTERFACE side only precisely because of this.
6. Running BOTH `cg-trace.sh` and `cbm-trace.sh` for cross-validation is not where the recall gain comes from — field-verified they return IDENTICAL callers when both are installed and queried correctly. The checks above are what close the recall gap, not a second graph tool, so don't spend an extra call running both "just in case."
7. LSP, if it happens to be available, may corroborate the final count (see LSP collaboration below) — it does not change chain order.

## Mandatory sequences (accuracy protocol)

1. Trace/impact/node/snippet all need an EXACT name.
   Unknown name → run the find/query step FIRST, copy the exact name from its output — prefer `qualified_name` over a bare `name` (bare names can silently fuzzy-match an unrelated symbol of the same short name).
   Never invent a name.
2. First structural question in a session on an unfamiliar area → run the architecture-overview row once to ground yourself, then targeted calls.
3. If any script returns an empty result, an error, or a `hint` field, follow that hint (broaden the pattern, try the other tool, fall back to native).
   Do not retry the same call unchanged.

## Quality rules (non-negotiable)

- **The graph LOCATES and STRUCTURES; it does not conclude.**
  Before stating any business-logic or "safe to change" conclusion, read the actual source — `cg-node.sh`/`cg-explore.sh` already embed verbatim source (reading that satisfies the requirement, no separate Read needed for files they already printed); for cbm, use `cbm-snippet.sh` or Read the file path the graph returned.
- **Agreement between signals is not proof when the signals share a blind spot — this applies to ANY "cross-check with another tool/signal" instruction in this file.**
  Field-verified twice: a dead-code candidate had the `dead-code-methods` query AND a `cg-trace`/`cg-node` structural check both agree it was dead, because both were independently blind to the same `SpringUtils.getAopProxy(this)` self-invocation call shape — their agreement was the same mistake counted twice, not corroboration.
  Separately, a "is this component unused" check flipped in BOTH directions once a genuinely independent signal (grep for the literal template tag, plus checking the framework's own auto-registration mechanism) was added — a graph "0 usages" verdict was a false negative (missed `unplugin-vue-components`-style auto-registration by folder name) and a graph "used by 29 files" verdict was a false positive (boilerplate variable-name collision inflating a file-level heuristic).
  When this file says "cross-check," the second signal must fail for a DIFFERENT underlying reason than the first — a second graph tool built on the same static-analysis limitation does not count, and field-verified to sometimes return literally identical results to the first (see the "who calls X" row's note on redundant dual-graph-tool queries).
- **Java interface → implementation calls are the single most consequential shared gap, handled differently by each tool.**
  A call through an interface-typed variable/field/param attaches to the interface's method node on BOTH tools' static analysis — this is a property of static analysis on interface-typed calls, not an implementation quirk of either tool.
  codegraph's higher-level commands (`cg-node.sh`, `cg-explore.sh`, `cg-impact.sh`) synthesize the bridge automatically in one call; `cg-trace.sh`'s bridge is a heuristic (flagged `bridged: true`) and still warrants a cross-check before a final count.
  cbm's Cypher engine cannot express this bridge query at all — the union protocol in the Decision table's "who calls X" row is MANDATORY, not optional, every single time, including plain single-implementation `IFoo`→`FooImpl` pairs (it is not limited to multi-impl/`@Primary` cases).
- **`CALLS`-edge name resolution differs sharply between the two tools, and this is the accuracy-deciding factor for get/set/is-shaped names.**
  cbm resolves by bare method name only (no parameter count/type or receiver-type check) — confirmed 60% false-positive rate on a real symbol from unrelated Lombok-generated getters.
  codegraph's edges are receiver/type-qualified — confirmed zero cross-pollution on the identical symbol.
  When both tools are installed and the target name is `get`/`set`/`is`-shaped or a `BaseMapper`-inherited name, this is why codegraph is preferred, not merely token cost.
  This receiver-typed guarantee covers method-level `CALLS` edges only — it does NOT extend to `cg-node.sh`'s file-level "used by N files" dependency aggregation for Vue SFCs, field-verified vulnerable to coincidental shared boilerplate variable names (`handleQuery`/`queryParams`) across unrelated CRUD pages, once inflating a real 0-usage component to a false "used by 29 files." Never trust a bare file-level usage count as evidence either way — grep the actual template tag.
- **`SpringUtils.getBean(X.class)` (a deterministic single-target Spring bean lookup) is a standing spot-check, not an edge case.**
  codegraph's `callers`/`node`/`impact` are confirmed fully blind to it (0/2 recall on two real call sites); this silently propagates into `cg-impact.sh`'s blast radius, producing a false "safe to change" read.
  Before reporting a final caller/impact count for ANY interface method, grep this pattern for the interface in question as a standing check — this rule applies regardless of which graph tool produced the count being reported.
  This is the canonical statement of this rule — other files reference it rather than re-deriving it.
  `SpringUtils.getAopProxy(this).<method>(...)` is a field-verified sibling of this gap (self-invocation through the AOP proxy, typically to trigger `@Cacheable`/`@CachePut`/`@CacheEvict`) — grep this pattern too whenever the target method carries an AOP-relevant annotation, same standing-check discipline, same silent blindness on both graph tools.
- **`SpringUtils.getBean(runtime-computed-name)`** (as opposed to the single-target case above) is genuinely undecidable statically — no amount of querying resolves a value only known at request time.
  codegraph's interface/impl fan-out lists all implementations as honest candidates ("one of these runs, decided at runtime" — not "all run", not "codegraph knows which"); grep the bean-name construction logic directly if the exact runtime selection matters.
- **Truncation self-reports must be believed.**
  Any script that emits a stderr warning naming a real total larger than its shown row count is telling you the shown rows are NOT the complete list — say "at least N," never imply completeness.
  `hubs` is deliberately exempt (a top-20 ranking has no "true total" to compare against).
- **Route class-level prefixes**: field-verified PRESENT (not dropped) across real controllers on the currently installed codebase-memory-mcp version — don't assume prefix-loss by default; upstream issue #734 describing this failure is real but open/unfixed, spot-check the one controller in question if a path looks truncated rather than assuming it's systemic.
- Code changed after the last sync/index may be missing — see the Gate check's freshness rule.

## Fall back to native grep/glob/read (do NOT use any graph tool)

See `references/lsp-and-native-fallbacks.md` for the full, field-verified list of constructs invisible to BOTH tools (MyBatis XML binding, Vue/React dynamic `import()`, computed Spring bean names, `extends` direction, unverified Laravel/Django magic) with grep recipes for each.
In addition:

- Comments, docstrings, README semantics; single-file line-level questions; literal text/SQL fragment search where no script applies.

## LSP collaboration

Claude Code's own LSP tool is a third, independent source — see `references/lsp-and-native-fallbacks.md` for the full protocol.
In short: **it is an opportunistic corroboration layer for single-symbol questions, never a chain head**, because it has not been field-verified in this project (this environment currently has no Java or TypeScript LSP server installed — confirmed by direct tool calls, not assumed).
Try it once, if relevant, after the graph-tool answer is already in hand; treat any "not available"/"not found" error as silent absence and move on without it.

## Token discipline

- Keep default limits (cbm: 20; cg fuzzy search: 20, exhaustive kind listing: 500 — do not lower this, codegraph's own `-l` behaves as a per-group multiplier rather than a literal cap on an empty pattern); paginate rather than re-running with a higher limit.
- Trace depth defaults (cbm: 3, cg: single-hop + auto-bridge) — raise only when the user asks for the full chain.
- `cg-explore.sh` defaults to `--max-files 3` (raise with `-m N` if needed).
- Summarize graph/JSON output in prose; never paste raw tool output to the user.
