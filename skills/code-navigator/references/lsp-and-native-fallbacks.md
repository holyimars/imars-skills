# LSP collaboration protocol, and native-only fallbacks shared by both tools

## LSP: opportunistic corroboration layer, never a chain head

Claude Code's own LSP tool (`findReferences`, `goToDefinition`, `hover`, `documentSymbol`, `goToImplementation`, `prepareCallHierarchy`, `incomingCalls`/`outgoingCalls`, `workspaceSymbol`) is a THIRD source of structural information, independent of both `codebase-memory-mcp` and `codegraph`.
It is deliberately NOT placed at the head of any row in `SKILL.md`'s decision table, for one reason: **only field-verified capabilities may lead a priority chain, and LSP has not been field-verified in this project at all.**

- **Field-verified (2026-07-18, this environment): no LSP server is installed for either language used across the two dogfood repos.**
  `findReferences` on a `.java` file returned `"No LSP server available for file type: .java"`; `documentSymbol` on a `.ts` file returned `"typescript-language-server not found or is in an unsafe location"`.
  Both attempts failed immediately, no partial result.
- **Trigger discipline**: only try the LSP tool once, opportunistically, when a single-symbol question is already being answered by `cg-trace.sh`/`cbm-trace.sh` — use it to corroborate a final caller count or definition location, never as the primary source, never for exploration, aggregation, or inheritance-direction questions.
- **Failure semantics (the actual protocol)**: any error shaped like `"No LSP server available for file type: X"` or `"... not found"` means this file type has no LSP support in the current session.
  Treat it as silent absence — do not retry, do not suggest installing a language server to the user, do not let it block or delay the chain already in progress.
  The graph-tool/native-grep answer stands on its own without LSP corroboration.
- **Honest labeling (mandatory wherever LSP is discussed)**: everything below about what LSP *would* provide if a server were configured is **untested design speculation, not a field-verified finding** — say "expected to" / "in theory", never "confirmed" or "field-verified", when describing it.
  If a future session finds a working LSP server in this or a similar repo, field-verify the claims below the same way every other claim in this skill was verified (direct tool calls, real symbols, checked against source) before upgrading any of this from speculation to fact.
  - Expected (untested): a real language server resolves symbols via the compiler/type-checker frontend, so it should be receiver-type-aware — no Lombok-getter name collision the way `codebase-memory-mcp`'s name-only `CALLS` edges have (field-verified 60% false-positive rate on `DictService.getDictLabel`, see `cbm-blindspots.md`).
  - Expected (untested): `goToImplementation`/`findReferences` on an interface method should, in principle, resolve through to real call sites without the manual union protocol `cbm-trace.sh` requires, and without the single-hop limitation `cg-trace.sh` has to heuristically bridge.
  - Expected (untested): being tied to the actual buffer/compiler state, LSP results should not suffer the same "index staleness" concern the graph tools have (`codegraph sync` / re-running `codebase-memory-mcp cli index_repository`).
- **LSP does not exempt any mandatory native-grep fallback.**
  Even a working LSP server operates on static/compiled structure — it has no more visibility than the graph tools into `SpringUtils.getBean(X.class)` reflection lookups, MyBatis XML `namespace=` binding, or Vue/React dynamic `() => import(...)` route registration.
  Every native-grep MANDATORY step in `SKILL.md`'s decision table stays mandatory regardless of whether LSP was available or corroborated a result.

## Native-only: blind spots shared by BOTH `codebase-memory-mcp` and `codegraph`

These are NOT fixed by switching between the two graph tools — both were independently field-verified to have the identical gap.
Go straight to native grep/Read; do not spend a call on either graph tool first.

- **MyBatis XML mapper binding** (`namespace=` → Java Mapper interface, `<if>/<foreach>` dynamic SQL, `@Select/@Update` SQL semantics).
  Both tools index the `.xml` file as a file node but extract zero symbols from it and bind nothing to the Java interface.
  Fallback: grep the mapper interface FQN as XML `namespace=`, then Read the mapper XML directly.
  (This repo's own `*Mapper.xml` files are empty MyBatis-Plus auto-registration shells with no hand-written SQL — the blind spot is confirmed structurally but hasn't had live dynamic SQL to fail on here.)
  See `cbm-blindspots.md`'s "Java + MyBatis / MyBatis Plus" section and `codegraph-blindspots.md`'s "MyBatis XML mapper binding" section for the per-tool repro.
- **Vue/React route-level dynamic `import()`** (`() => import('@/views/x.vue')`).
  Both tools produce no edge from the router file to the lazily-loaded component; only statically-imported components get an edge.
  Fallback: grep the component's file path/basename directly inside router config files.
  See `cbm-blindspots.md`'s "JS/TS + dynamic `import()`" section and `codegraph-blindspots.md`'s equivalent section for the per-tool repro (both confirmed on the same plus-ui router file).
- **Vue/React functions registered on `app.config.globalProperties`** (e.g. `app.config.globalProperties.parseTime = parseTime`, called elsewhere as `proxy.parseTime(...)` or `proxy?.parseTime(...)`).
  Field-verified as a repo-wide CLASS of blind spot, not a per-function quirk: three independently-registered functions in `plus-ui/src/plugins/index.ts` (`parseTime`, `handleTree`, `addDateRange`) were each tested separately, and all three reproduced the identical failure — both `cg-trace.sh` and `cbm-trace.sh` recalled only 0-1 out of 10-19 real call sites, because the real call goes through the injected property, which neither tool's static call-graph model resolves back to the plugin registration.
  A single native `grep -rn "proxy\.<name>\|\.<name>("` call recovered every real call site (10/10, 19/19, 10/10 across the three functions), each in under 100ms — see `references/tool-collaboration-benchmark.md` for the full per-function numbers.
  Fallback: before trusting a call-chain answer for ANY function, check whether it's registered on `app.config.globalProperties` (grep `src/plugins/index.ts` or equivalent to enumerate the full registered set) — if so, grep its real call sites directly rather than trusting either graph tool's trace.
- **Spring `getBean(runtime-computed-name)`** (e.g. `SpringUtils.getBean(grantType + "AuthStrategy")`).
  Genuinely undecidable without running the code — this is not a graph gap, no amount of static analysis resolves a value only known at request time.
  codegraph's interface/impl heuristic will honestly (if imprecisely) list every implementation as a dynamic-dispatch candidate; codebase-memory-mcp has no equivalent synthesis here at all.
  Fallback: grep the bean-name construction pattern to enumerate candidates by hand.
  See `cbm-blindspots.md`'s "Runtime bean-name lookup" section and `codegraph-blindspots.md`'s "Spring runtime bean-name lookup" section for the per-tool repro (both tested against the same `IAuthStrategy` strategy-pattern example).
- **Class `extends`/inheritance direction.**
  codegraph's graph is confirmed one-directional (querying a subclass never reveals its parent, matching upstream open issue [colbymchenry/codegraph#1328](https://github.com/colbymchenry/codegraph/issues/1328); querying the parent DOES list subclasses, mislabeled under a `Called by ←` heading — don't read that as a call relationship).
  codebase-memory-mcp never modeled this relationship at all, in either direction.
  Fallback: grep the `class X extends Y` declaration line directly — this is the one relationship neither tool carries.
  See `codegraph-blindspots.md`'s "Class inheritance (`extends`)" section for the full repro (schema-level confirmation, not just text output) — codebase-memory-mcp has no equivalent section since it never modeled this relationship at all, in either direction, to have a repro against.
- **Laravel / Django / PHP / Python dynamic dispatch** (Facades, Eloquent magic methods/scopes, container string bindings, Blade logic, dynamic URLconf, signals).
  Not field-verified against either tool in this project (no PHP/Python repo was available to test against) — treat as a likely-blind structural inference carried over from general framework-magic reasoning, and spot-check before relying on it for a real decision.
  See `cbm-blindspots.md`'s "PHP + Laravel"/"Python + Django" sections and `codegraph-blindspots.md`'s "Not tested / out of scope for this pass" section — both explicitly label this unverified rather than field-verified, keep that distinction when citing it.

`SpringUtils.getBean(X.class)` — a deterministic SINGLE-target bean lookup (as opposed to the computed-name case above) — is deliberately NOT listed here as a "shared" blind spot: the two tools are asymmetric on this one.
See `SKILL.md`'s Quality rules section (the `SpringUtils.getBean(X.class)` bullet) for the canonical statement of that asymmetry and the standing mandatory grep check; see `codegraph-blindspots.md`'s dedicated section for the underlying field-verification evidence (exact call sites, 0/2 recall across three commands).
`SpringUtils.getAopProxy(this).<method>(...)` self-invocation IS listed as a genuinely shared miss (unlike the `getBean(X.class)` case above): both `cg-trace.sh`/`cg-node.sh` AND `cbm-cypher.sh dead-code-methods` independently missed the same call site in testing, so two tools "agreeing" a method looks dead does not corroborate anything here — see `codegraph-blindspots.md`'s dedicated section (and `cbm-blindspots.md`'s dead-code section) for the full repro, and grep `SpringUtils.getAopProxy(this).<method>(` as a standing check on any AOP-annotated (`@Cacheable`/`@CachePut`/`@CacheEvict`) method before trusting a dead-code verdict.

## Config-file key binding (`@Value("${key}")` ↔ `application.yml`; `import.meta.env.VITE_X` ↔ `.env`) — NOT a clean shared blind spot, partial and asymmetric

- Unlike the fully-blind items in the list above, config-binding visibility is inconsistent per script, and one assumption from earlier testing turned out wrong: `cg-find.sh` unexpectedly indexes some `application.yml` keys as `constant`-kind nodes and links them to `@Value` reference sites in Java code — a real, if incomplete, capability (field-verified 2026-07-18; not confirmed to extend to `.properties` files or profile-specific `application-{dev,prod}.yml`).
- `cbm-find.sh` (regex/symbol-oriented) has zero visibility into `.yml`/`.env` files at all.
  `cbm-grep.sh` (literal-text-oriented) partially does — it modeled `plus-ui/.env.development` as a Module node and found the defining line for a `VITE_APP_CLIENT_ID`-style key.
- Net guidance: native grep of the config file directly is still faster and complete either way, and remains the only path for `.properties` files and any env-var file no script here modeled — do not write off a graph hit here as impossible, but do not trust its absence as proof the key doesn't exist either.
  See `references/tool-collaboration-benchmark.md` for the full test recipe on both repos.
