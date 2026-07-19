---
name: code-navigator
description: >
  Query this repo's pre-built code index/graph for structural questions: where a symbol is defined, who calls it, call chains (调用链/调用关系), change impact / blast radius (影响面/改动影响), architecture overview (架构/模块划分), dead code (死代码/无用代码), hubs/god-classes, cross-layer violations, API routes, which tests cover a change, and "which module handles X" (哪个模块/哪里实现).
  Designed to work with BOTH of two independent CLI-only indexes installed together — `codebase-memory-mcp` (index product `.codebase-memory/`) and `codegraph` (index product `.codegraph/`) — picking whichever is actually best suited to the question shape, sometimes both at once; degrades gracefully if only one is installed. Claude Code's own LSP tool is an optional third, opportunistic corroboration layer, never required.
  Do NOT use for tiny repos (under ~1,000 lines of code), MyBatis XML, Vue/React dynamic `import()` route lazy-loading, Laravel Eloquent magic/built-in Facades (Cache::/Auth::)/Blade logic, Python decorator-application relationships (which functions a `@decorator` wraps), comments/docs, or single-line questions — use native grep/read there. Django dynamic URLconf routing IS worth using this skill for (codegraph resolves it well) — just don't expect cbm to match.
---

# code-navigator — accurate & efficient calling protocol

One unified entry point for both CLIs' 14 query scripts (`cbm-*.sh` / `cg-*.sh`). The design goal is: **pick the single cheapest call that gets the accurate answer**, never both tools "just in case," and never a graph-tool call where native grep is already faster and equally precise.

## Gate check (before ANY call)

1. **Recommended setup is both indexes present** (`.codebase-memory/` and `.codegraph/`). If only one exists, degrade to that tool's rows below and skip the other silently. If neither exists, this skill does nothing — use native grep/Read, and tell the user which `init`/`index_repository` command would set one up if the question recurs.
2. **Tiny repo? Skip this skill entirely.** Under ~1,000 lines of code (`cg-arch.sh`/`cbm-arch.sh` node count in the low hundreds) — native grep/read is just as accurate and faster at this scale.
3. **Effort awareness.** Retrieval quality is capped by the reasoning/output token budget on both CLIs equally — no graph tool lifts this cap. For impact analysis, change decisions, or any structural conclusion the user will act on: delegate to the `deep-analyst` subagent (elevated effort, isolated context, verifies via source reads before returning a conclusion). If unavailable, recommend the user re-run at high effort and verify conclusions with native Read on the key code paths.
4. **Freshness & operational gotchas:**
   - codebase-memory-mcp re-indexing needs an ABSOLUTE `--repo-path` and an explicit `--name` — a relative path with no `--name` silently creates a duplicate project instead of updating the existing one.
   - Watch host memory the first time `index_repository` runs on any new, unfamiliar repo, especially on Windows — a known, unmitigated upstream memory-blowup class that can hit tens of GB within SECONDS. **Repo size and PHP+TS language-mixing were the original suspects but have been field-disproven as the actual cause** (a larger, same-language-mix repo indexed clean three times; a from-scratch bisection down to 2 files isolated the real trigger to a much narrower, cheaper-to-check condition — full methodology and every confirming/disconfirming test in `research/code-navigator/cbm-blindspots.md`'s "Round 10"): **a user class literally named `Database` (or similarly reserved-sounding: `Cache`/`Config`/`Session`/`Container`/`Storage`/`Log`) that also has a self-referential generic relation annotation (`@return ...<Target, $this>`) on at least one method.** Before indexing an unfamiliar repo, a cheap zero-risk pre-check (`grep -rn "^class \(Database\|Cache\|Config\|Session\|Container\|Storage\|Log\)\b"` combined with a `, \$this>` generic on that class's methods) is a sharper signal than eyeballing file count or language mix. Field-verified: switching to `--mode fast` does NOT avoid it (comparable blowup rate to full mode — the hungry step apparently runs in every mode), so a lighter mode is not the safe retry it sounds like; and killing the worker alone doesn't stop it — a supervisor respawns it, kill both processes. The scripts' own "repo not indexed" hint prints a ready-to-run `index_repository` command; don't paste it unmonitored without having done the pre-check above. The economical default when the pre-check flags a hit, or when in doubt: skip cbm indexing and use codegraph alone (no equivalent risk, indexes the same repo in seconds) unless a cbm-exclusive capability (dead code/hubs/cross-layer) is genuinely needed.
   - `codegraph sync .` for routine updates (seconds); never run `codegraph index --force` while another `codegraph` command might be in flight — hard-fails with `EPERM: database file is in use` on Windows.
   - If the user mentions a change from the last few minutes, sync first or read the working tree directly.
5. **User names a tool explicitly → use that one, skip the arbitration.**
6. **Cross-repository questions**: each repo is its own independent index, no aggregated multi-root graph exists on either tool. A question spanning both needs one call per project plus manual correlation — see `references/fallback-cookbook.md`.

LSP is NOT part of this gate check — no persistent index to detect. See `references/lsp-notes.md`: tried opportunistically per single-symbol question, never gating session start.

All scripts resolve the repo root via `git rev-parse --show-toplevel` automatically and auto-resolve the project name — never pass or guess one.

## Decision table (question shape → ONE script, in one shot)

| Question shape | Priority chain | Key constraint |
|---|---|---|
| Symbol location, EXACT name already known | Native Glob (`**/<ExactName>.*`) — skip both graph tools | Faster (up to 18x) and equally-or-more precise when the exact name is known; graph tools only add fuzzy-match noise here. Fall through only if Glob finds nothing or multiple ambiguous hits |
| Symbol location, fuzzy/partial name | `cg-find.sh` (optionally `-k <kind>`) > `cbm-find.sh` (optionally `-l <Label>`) > native Grep | Precondition for every row below — always copy the exact `qualified_name` from this step's output, never invent one |
| Show a symbol's source + context | `cg-node.sh` (source + both-direction callers + interface/impl bridge, one call) > `cbm-snippet.sh` > native Read | If `cg-node.sh`/`cg-explore.sh` already printed the source, that satisfies "read the source before concluding" |
| Exhaustive listing of a kind (all routes/classes/interfaces/components) | `cg-find.sh -k <kind>` with an EMPTY pattern (accurate exhaustive count, verb included for routes) > `cbm-cypher.sh routes` for routes only (self-truncates, no verb) > `cbm-find.sh -l <Label>` for other kinds (self-reports truncation via `hasMore`) > native grep | Prefer codegraph when both installed — same accuracy, cheaper, includes the HTTP verb. **NEVER `cg-explore.sh`** — keyword-matches "list" against unrelated methods and misses real routes |
| Who calls X / call chain | `cg-trace.sh` (auto-bridges interface→impl; cross-check with `cg-node.sh` when it reports `bridged: true`) > `cbm-trace.sh` queried on the INTERFACE side PLUS a mandatory second query if the first hit was the impl, union both > native grep | See "Interface-method call-chain — mandatory checks" below — these run regardless of which tool answered |
| Impact / blast radius, symbol-anchored | `cg-impact.sh` (multi-hop, bridges interface/impl; raise `-d` if an expected node is missing) > approximate with `cbm-trace.sh` + interface-union (cbm has no direct equivalent) > native grep | Same `SpringUtils.getBean(X.class)` standing check as the row above; any conclusion the user will act on → `deep-analyst` |
| Impact, uncommitted-diff-anchored | `cbm-impact.sh` (diff → impacted symbols + risk) AND `cg-affected.sh` (diff → covering tests) — run BOTH, they're complementary not alternatives | Each tool owns half this question shape |
| Which tests cover this change | `cg-affected.sh` — cbm has no equivalent > native grep of test dirs | High `totalDependentsTraversed` makes a "no covering tests" conclusion more trustworthy |
| Exploratory compound question ("how does X reach Y") | `cg-explore.sh` (one call: source + call paths + blast radius) — cbm has no one-call equivalent, chain `find`→`trace`→`snippet` manually > native | Skim the returned symbols for relevance — can pull in keyword-coincidence matches even on strong-case questions |
| Business term → module, English | `cg-explore.sh` (compound questions) or `cbm-find.sh -s` (semantic, reliable for English) or `cg-find.sh` (FTS) | |
| Business term → module, Chinese, Java/backend repo | `cbm-grep.sh` or `cg-find.sh` (FTS) — either is fine | **NEVER** `cg-explore.sh` (empty on pure-Chinese, needs a Latin anchor token) and **NEVER** `cbm-find.sh -s` (near-random on Chinese) |
| Business term → module, Chinese, Vue/TS/frontend repo | `cbm-grep.sh` ONLY | `cg-find.sh` fails systematically on this repo shape (CJK-tokenizer gap), not a fluke — see `references/tool-divergence.md` |
| Architecture overview / hotspots | `cg-arch.sh` or `cbm-arch.sh` — either is fine | `cbm-arch.sh`'s `fan_in` is relative ranking only (~4% deviation from grep observed) — trust for ranking, not exact counts |
| Dead code | `cbm-cypher.sh` — the only capability, codegraph has none. Java methods → `dead-code-methods` PLUS the interface-union protocol; plain functions → `dead-code` | Both self-report truncation past their row cap. **A raw "dead" verdict is a candidate to disprove, not a conclusion** — cross-check with a plain textual grep for the method name AND read the call site; agreement between both graph tools does NOT count as proof if they share the same blind spot (see `references/tool-divergence.md`). **NEVER substitute `cg-explore.sh`** — same keyword-coincidence failure as the listing row above |
| Hubs / god-classes | `cbm-cypher.sh hubs` — the only capability, top-20 by design | Class/OOP-oriented repos only — empty on function-oriented JS/TS/Vue repos. **NEVER substitute `cg-explore.sh`** |
| Cross-layer violations | `cbm-cypher.sh cross-layer [layerA] [layerB]` — the only capability | **NEVER substitute `cg-explore.sh`** |
| Class inheritance (`extends`) | Native grep of the `class X extends Y` line — the only reliable path | Neither tool reliably carries this relationship — see `references/fallback-cookbook.md` |
| Framework magic (MyBatis XML, Vue/React dynamic `import()`, Spring computed `getBean`, Laravel built-in Facades/Eloquent magic, Python decorator-application edges) | Native grep/Read — the only reliable path | Full construct-by-construct grep recipes in `references/fallback-cookbook.md`. Two field-verified exceptions that are NOT framework magic to avoid: an APP-DEFINED Laravel Facade whose accessor returns a concrete app class resolves well via `cg-trace.sh` on the target class (watch for same-named global PHP functions); and Django dynamic URLconf (multi-level `include()`) resolves well via `cg-trace.sh`/`cg-find.sh -k route` — cbm does not, use codegraph specifically. Both in `references/tool-divergence.md` |
| Config-binding consistency (`@Value`/`.yml`; `import.meta.env`/`.env`) | Native grep both sides + Read to confirm the value | Neither tool is a clean miss OR a complete answer — partial/asymmetric coverage on both, see `references/fallback-cookbook.md`. Treat any graph hit as a lead to verify, never a final answer |
| Cross-repo consistency (frontend call ↔ backend route) | Native grep both repos' trees + `cg-find.sh -k route` on the backend side as a structural cross-check | Neither tool has ANY cross-repo capability — manual correlation only |
| Literal text / string / SQL fragment | Native Grep first choice; `cbm-grep.sh` also works | codegraph has no text-search command |
| Comments / docs / single-file line-level question | Native Read | |

(Tiny-repo skip, index-presence detection, effort delegation, freshness live in the Gate check above, not as table rows.)

### Interface-method call-chain — mandatory checks (for the "who calls X" row)

Run these regardless of which graph tool answered — none are optional, and none are satisfied by switching to the other graph tool instead:

1. Grep `SpringUtils.getBean(<Interface>.class)` before reporting a final count for an interface method — a deterministic single-target lookup codegraph is confirmed fully blind to.
2. ALSO grep `SpringUtils.getAopProxy(this).<method>(` when the target carries `@Cacheable`/`@CachePut`/`@CacheEvict` — a self-invocation shape both tools miss.
3. If the target is a Vue/React function registered on `app.config.globalProperties`, grep `proxy\.<name>\|\.<name>(` directly — both graph tools AND TypeScript LSP recall almost nothing here.
4. If the name is `get`/`set`/`is`-shaped or a common `BaseMapper` name AND the answer came from cbm, sample-read the actual call sites — cbm resolves by bare name only. codegraph does not have this collision (receiver-typed).
5. Querying `cbm-trace.sh` on the WRONG (impl) side silently returns confidently-formatted false positives — always confirm you queried the INTERFACE side.
6. Running BOTH `cg-trace.sh` and `cbm-trace.sh` "for cross-validation" does not add recall by itself — when both are queried correctly they return identical callers. The checks above are what close the gap, not a second graph-tool call.
7. LSP, if available, may corroborate the final count but never changes chain order.
8. Check `cg-trace.sh`'s `possiblyTruncated` / `cbm-find.sh`'s `hasMore` before citing any count sitting at a round-number limit as final.

Full evidence and numbers behind each check: `references/tool-divergence.md`.

## Mandatory sequences (accuracy protocol)

1. Trace/impact/node/snippet all need an EXACT name. Unknown name → run find/query FIRST, copy the exact `qualified_name` (prefer it over a bare `name`, which can silently fuzzy-match an unrelated symbol). Never invent a name.
2. First structural question in a session on an unfamiliar area → run the architecture-overview row once to ground yourself, then targeted calls.
3. If any script returns an empty result, an error, or a `hint` field, follow that hint (broaden the pattern, try the other tool, fall back to native). Do not retry the same call unchanged.

## Quality rules (non-negotiable)

- **The graph LOCATES and STRUCTURES; it does not conclude.** Before stating any business-logic or "safe to change" conclusion, read the actual source — `cg-node.sh`/`cg-explore.sh` already embed it; for cbm, use `cbm-snippet.sh` or Read the returned file path.
- **A find-level hit is not a resolved edge.** `cg-find.sh`/`cbm-find.sh` match names; when a variable is named after the file/symbol it points at (the default for lazy-import route constants, common elsewhere), find returns BOTH ends and looks exactly like successful resolution while the graph holds zero connecting edges — field-verified on a React `lazy()` route (find returned both nodes; `cg-impact.sh` showed `edgeCount: 0`). Before claiming the graph "sees" a link, confirm it with an edge-walking call (`cg-impact.sh`/`cg-trace.sh`/`cg-node.sh`'s trail), because that's what actually distinguishes a connection from a name coincidence.
- **Agreement between two signals is not proof when they share a blind spot.** A second graph tool built on the same static-analysis limitation, or a second run of the same query, does not count as independent corroboration — it has to fail for a genuinely different reason (e.g. a native grep, which works on a completely different principle). See `references/tool-divergence.md` for confirmed cases where "both tools agree" was the same mistake counted twice.
- **Java/PHP interface → implementation calls are the single most consequential shared gap.** codegraph's higher-level commands synthesize the bridge automatically; cbm's Cypher engine cannot express it at all — the union protocol in the decision table's "who calls X" row is mandatory every time, not just for multi-impl cases. Full mechanics: `references/tool-divergence.md`.
- **`CALLS`-edge name resolution differs sharply and decides which tool to trust for get/set/is-shaped or repeated method names.** codegraph is receiver/type-qualified (Java + PHP confirmed); cbm resolves by bare name only (confirmed 60% false-positive rate on a Lombok-getter collision). Exceptions and the PHP-specific global-function collision: `references/tool-divergence.md`.
- **All `cbm-*.sh`/`cg-*.sh` scripts now propagate errors and truncation signals reliably** (fixed across several rounds of code review — `cbm_call()`/`cg_call()` both validate JSON and surface `.error`/`.hint` instead of crashing or silently reshaping into an empty-looking success). Trust the `hint` field when a script returns one; a script returning an unexpected empty result without a hint is now itself a signal something is wrong, not a normal "no results" answer.
- **`SpringUtils.getBean(X.class)`** (deterministic single-target lookup) is a standing spot-check, not an edge case — codegraph is confirmed fully blind to it (silently produces a false "safe to change" read on impact analysis); `SpringUtils.getAopProxy(this).<method>(...)` self-invocation is a field-verified sibling gap shared by BOTH tools. Grep both patterns before reporting a final caller/impact count for any interface or `@Cacheable`-annotated method.
- **`SpringUtils.getBean(runtime-computed-name)`** is genuinely undecidable statically (as opposed to the single-target case above) — codegraph's interface/impl fan-out lists all implementations as honest candidates, not a resolved answer. Grep the bean-name construction logic directly.
- **Truncation self-reports must be believed.** Any script emitting a warning that names a real total larger than its shown row count means the shown rows are NOT the complete list — say "at least N," never imply completeness. `hubs` is deliberately exempt (a top-20 ranking has no "true total").
- **PHP fluent-chain tail calls are a real codegraph-specific gap** (confirmed root cause, not a wrapper bug) — prefer cbm whenever the query symbol may be reached through a builder chain (`->with(...)`/`->loadRelation(...)`-style intermediate calls). Full numbers: `references/tool-divergence.md`.
- **Go's most ordinary dependency pattern — a struct field typed from another package, calling a method on it — is a severe, newly-found blind spot on BOTH tools.** More basic than any Java/PHP finding above: not an interface/impl split, not a fluent chain, just an everyday cross-package call, and both tools miss it completely. For any Go repo, grep the field's declared type + method name directly as the PRIMARY path. Full ground truth: `references/fallback-cookbook.md`.
- **Python `Model.objects.custom_method()` (Django custom Manager, no renaming involved) is a genuine positive result on BOTH tools** — full recall, confirmed on `ProfileManager.for_user()` (10/10 real call sites on codegraph; cbm matched plus deeper transitive hops via its depth parameter). Contrast with PHP Eloquent's `scopeXxx→->xxx()` (confirmed shared blind spot): the difference is whether the framework convention renames the method between definition and call site, not whether it's "ORM magic" in general — don't extrapolate one ORM-convenience finding to another language/framework without checking for a rename. Python decorator-APPLICATION edges (`@decorator` → which functions it wraps), by contrast, ARE a confirmed shared blind spot — see the Framework-magic row above. Full detail: `references/tool-divergence.md`.
- **Config-key binding (`@Value`/`import.meta.env`) is partial and asymmetric on both tools, including across variants of the SAME config-file family** (`.env.production` can be completely unindexed while `.env.development` in the same repo is fully indexed). Never assume one config-file variant's coverage extends to its siblings — check each file individually. Full detail: `references/fallback-cookbook.md`.
- Code changed after the last sync/index may be missing — see the Gate check's freshness rule.

## Fall back to native grep/glob/read (do NOT use any graph tool)

See `references/fallback-cookbook.md` for the full, field-verified list of constructs invisible to BOTH tools, with a ready-to-use grep recipe for each. In addition: comments, docstrings, README semantics, single-file line-level questions, and literal text/SQL fragment search where no script applies.

## LSP collaboration (optional, never required)

Claude Code's own LSP tool is a third, independent, OPTIONAL source — see `references/lsp-notes.md` for the full protocol, setup gotchas, and confirmed TypeScript/Java results. In short: try it once, opportunistically, after the graph-tool/native answer is already in hand, for a single-symbol question only — never as the chain head, never for exploration/aggregation/inheritance-direction questions, and never assume a clean-looking result is complete without the same native-grep cross-check the graph tools would need.

## Token discipline

- Keep default limits (cbm find: 200; cg fuzzy search: 20, exhaustive kind listing: 500) — do not lower these, paginate rather than re-running with a higher limit.
- `cg-trace.sh`'s `callers`/`callees` default to 200 (not the underlying CLI's own default of 20, which silently under-reports with no truncation signal) — watch the `possiblyTruncated` field and raise the limit further only if it fires.
- `cbm-find.sh` follows the same discipline — its `hasMore`/`total` fields are the truncation signal, raise with `-n` only if `hasMore` is true.
- Trace depth defaults (cbm: 3, cg: single-hop + auto-bridge) — raise only when the user asks for the full chain. Remember cbm's 3rd positional arg is DEPTH, not a result limit like cg's identically-positioned argument (see `references/tool-divergence.md`).
- `cg-explore.sh` defaults to `--max-files 3` (raise with `-m N` if needed).
- Summarize graph/JSON output in prose; never paste raw tool output to the user.
