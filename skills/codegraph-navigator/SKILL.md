---
name: codegraph-navigator
description: >
  Query this repo's pre-built codegraph CLI index for structural questions: where a symbol is defined, who calls it, call chains (调用链/调用关系), change impact / blast radius (影响面/改动影响), architecture overview (架构/模块划分), which tests cover a changed file, and "which module handles X" (哪个模块/哪里实现).
  Requires the repo to already have a `.codegraph/` index (built via `codegraph init`) — this is a DIFFERENT tool and index from cbm-navigator's `.codebase-memory/`, do not assume one implies the other.
  Do NOT use for tiny repos (under ~1,000 lines of code), MyBatis XML, Vue/React dynamic `import()` route lazy-loading, comments/docs, or single-line questions — use native grep/read there.
---

# codegraph Navigator — accurate & efficient calling protocol

## Gate check (before ANY graph call)
1. **`.codegraph/` must exist at the repo root.**
   Every script in this skill hard-stops with a clear error if it doesn't — the hint tells you to run `codegraph init` (or, if the repo instead has a `.codebase-memory/` directory, to use the `cbm-navigator` skill).
2. **Tiny repo? Skip this skill entirely.**
   Under ~1,000 lines of code (`codegraph status` shows `nodeCount` in the low hundreds) — native grep/read is just as accurate and faster.
3. **Both `.codegraph/` and `.codebase-memory/` present in the same repo?**
   Field-verified division of labor: for single-symbol questions (who calls X, show me X, what breaks if I change X) prefer codegraph — its `explore`/`node` commands surface the Java interface/impl cross-reference automatically (see Quality rules below), which cbm-navigator cannot do without a manual mandatory cross-check.
   For whole-graph AGGREGATE/ANALYTIC questions (dead code, god classes/hubs, cross-layer violation sweeps) prefer cbm-navigator's `cbm-cypher.sh` — codegraph has no raw graph-query equivalent and, field-verified, its `explore` command produces confidently-wrong answers for these three shapes (see Quality rules below), it is not just weaker.
   Exception: "list all routes" — codegraph DOES have a direct, verified-accurate equivalent (`cg-find.sh -k route`, see Decision table), prefer that over cbm-cypher.sh's `routes` template when both are available (codegraph's route names include the HTTP verb).
   If the user names a tool explicitly, use that one.
4. **Effort awareness (team-measured fact, same as cbm-navigator).**
   Retrieval quality is capped by the reasoning/output token budget: at low/medium effort, accuracy is LOWER than at high/xhigh/max.
   For impact analysis, change decisions, or anything the user will act on: delegate to `codegraph-deep-analyst`.
5. **Freshness.**
   If the user mentions a change from the last few minutes, run `codegraph sync .` first (incremental, seconds) or read the working tree directly — `_gate.sh` warns on stderr when the index has pending changes.

All scripts resolve the repo root via `git rev-parse --show-toplevel` (or cwd) automatically; codegraph itself resolves the index the same way — never pass or guess a project name (there is no named registry, unlike cbm-navigator).
Scripts print compact JSON (except `cg-node.sh`/`cg-explore.sh`, which print codegraph's own markdown — that IS the intended AI-facing format, don't re-wrap it).

## Decision table (question type → ONE script, in one shot)

| Question shape | Script | Notes |
|---|---|---|
| "Where is X / list all X" | `scripts/cg-find.sh 'X'` | fuzzy text match; add `-k function\|class\|method\|interface\|component\|route` to filter kind |
| "List ALL routes/classes/interfaces/components" (exhaustive, not fuzzy) | `scripts/cg-find.sh -k route\|class\|interface\|component` (omit the pattern) | field-verified EXACT: an empty pattern + `-k` enumerates every symbol of that kind — count matched `codegraph status`'s `nodesByKind.<kind>` precisely (303/303 routes, 482/482 classes). This is the accurate way to answer "list all X of kind Y" — do NOT use `cg-explore.sh` for this, see below |
| "Who calls X / what does X call" | `scripts/cg-trace.sh <exact-symbol> [in\|out\|both]` | needs EXACT name → run cg-find.sh first if unsure; prefer `qualified_name` over bare `name` (bare method names can fuzzy-match unrelated symbols); auto-bridges the Java interface/impl gap on `in` regardless of which of the two you pass, see Quality rules |
| "What breaks if I change X" (blast radius) | `scripts/cg-impact.sh <exact-symbol> [depth]` | multi-hop by default (depth 2), already bridges interface/impl on its own |
| "Show me X (source + who calls/what it calls)" | `scripts/cg-node.sh <exact-symbol>` or `-f <file>` | one call, cheaper than Read on the whole file; look for `[dynamic: interface → impl]` labels on the Trail and follow them |
| Compound / exploratory SINGLE-AREA question ("how does X reach Y", "why does Z happen") | `scripts/cg-explore.sh "<question...>"` | **flagship tool for this shape only** — one call returns relevant symbols' source + call paths + blast radius, including interface/impl synthesis; prefer this over chaining find→trace→node for anything non-trivial. Do NOT use for whole-graph aggregate questions, see the row below |
| "Architecture / file structure / how big is this repo" | `scripts/cg-arch.sh [max-depth]` | merges index stats + file tree; tree truncated to 60 entries by default; `nodesByKind` in the output tells you which `-k` filters are worth trying on `cg-find.sh` |
| "Which tests cover this change" | `scripts/cg-affected.sh [files...]` | no args → uses uncommitted git diff; capability codebase-memory-mcp does not have; `totalDependentsTraversed` in the output is a transparency count — trust the "no covering tests" hint more when that number is high |
| whole-graph AGGREGATE patterns: dead code, hubs/god-classes, cross-layer violations | *(no equivalent — do NOT use `cg-explore.sh`)* | field-verified (2026-07-17): asked to find dead code / hubs, `explore` does keyword-similarity retrieval on the question text and returns symbols that merely share vocabulary with the question (e.g. methods named `find*` for a "dead code" query) — each with real callers, formatted with the same confident "Blast radius" / "⚠️ no covering tests" styling as a correct answer. It does not compute call-degree or reachability. Fall back to `cbm-cypher.sh dead-code\|hubs\|cross-layer` if this repo is also indexed by codebase-memory-mcp, otherwise native grep-based heuristics |
| literal text / string / SQL fragment | *(no direct equivalent)* | codegraph has no text-search command — use native Grep |

## Mandatory sequences (accuracy protocol)
1. trace/impact/node need exact names.
   Unknown name → `cg-find.sh` FIRST, copy the exact name from its output — prefer the `qualified_name` field (disambiguated) over bare `name` (can silently fuzzy-match unrelated symbols of the same short name).
   Never invent names.
2. First structural question in a session on an unfamiliar area → `cg-arch.sh` once to ground yourself, then targeted calls.
3. If any script returns an empty result array or an error, follow the `hint` field it prints — every script in this skill returns valid JSON with a `hint` even when the underlying `codegraph` call fails or the symbol doesn't exist, never a raw crash.
   Do not retry the same call unchanged.

## Quality rules (non-negotiable)
- **`cg-explore.sh` is a keyword/semantic retrieval tool over symbol names and source text, NOT a graph-analytics engine — field-verified (2026-07-17) to fail silently, not loudly, on aggregate questions.**
  Asked "find dead code" or "which classes are hubs", it returns symbols whose NAME happens to match the question's vocabulary (e.g. `findFirst`/`findAny` for a "find unused methods" query) — every one of them had real callers, and the response's own "Blast radius" section proved it, but the confident markdown formatting (⚠️ warnings, caller counts) makes a wrong-shaped answer look authoritative. Asked "list all routes" it matched controller methods literally named `list`, never surfacing a single `/api/...` path.
  Use it ONLY for single-area compound questions (call paths, "how does X reach Y", interface/impl synthesis) — that is genuinely its strength (see below). For "list all X of a kind" use `cg-find.sh -k <kind>` (empty pattern) instead; for dead-code/hubs/cross-layer there is no codegraph substitute, use `cbm-cypher.sh` or grep-based heuristics — see Decision table.
- **Java interface → implementation calls (field-verified, better than codebase-memory-mcp but still needs care).**
  `cg-node.sh`/`cg-explore.sh` label the cross-reference edge `[dynamic: interface → impl @file:line]` and — for `explore` — already include both sides' blast radius in one response; prefer these two for anything you'll report a conclusion from.
  `cg-trace.sh` auto-bridges the single-hop `callers` gap and marks the result `"bridged": true` when it did — treat that flag as "verify with cg-node.sh/cg-explore.sh before stating a final count," not as a guarantee.
  See `references/blindspots.md` for the full repro and the exact mechanism.
- **`[dynamic: interface → impl]` fan-out on a multi-implementation interface (e.g. a Spring strategy pattern with `getBean(computedName)`) lists ALL implementations as candidates — this means "one of these runs, decided at runtime," NOT "all of these run" and NOT "codegraph knows which one."**
  Grep the bean-name construction logic directly if the exact runtime selection matters.
- The graph LOCATES and STRUCTURES; it does not conclude.
  `cg-explore.sh` already embeds verbatim source in its response — reading that source block satisfies "read the actual source," no separate Read call needed for files it already printed.
- Code changed after the last sync may be missing: run `codegraph sync .` or read the working tree if the user references a very recent change.

## Fall back to native grep/glob/read (do NOT use the graph)
- MyBatis mapper XML / dynamic SQL: codegraph indexes the `.xml` file but extracts 0 symbols and does not bind `namespace=` to the Java Mapper interface (field-verified, identical to codebase-memory-mcp's blind spot).
  Grep the mapper interface FQN as XML `namespace=`, then Read the mapper XML directly.
- Vue/React route-level lazy loading (`() => import('...')`): dynamically-imported route components produce NO graph edge (field-verified, identical to codebase-memory-mcp).
  Grep the router config directly for "who routes to this component" instead.
- Laravel/Django/PHP/Python framework magic: not field-verified against codegraph specifically — treat as likely-blind (codegraph's own docs claim limited reflection/dynamic-dispatch analysis) but spot-check before relying on it.
- Comments, docstrings, README semantics; single-file line-level questions; literal text/SQL fragment search (no equivalent command).

## Token discipline
- `cg-explore.sh` defaults to `--max-files 3` (pass `-m N` to raise it); `cg-find.sh` defaults to limit 20 for a fuzzy pattern, 500 for an exhaustive `-k <kind>` listing (empty pattern) — the underlying `codegraph query` CLI does not treat `-l` as a literal cap when the pattern is empty (field-verified: `-l 1/3/5` returned ~5x that many rows), so don't lower this default when doing a "list all" call; `cg-arch.sh` truncates its file tree to 60 entries.
- Summarize graph output in prose; never paste raw tool output to the user.
