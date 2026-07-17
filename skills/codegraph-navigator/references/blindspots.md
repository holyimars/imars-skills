# codegraph blind spots & native fallbacks (field-verified 2026-07-16, v1.4.1)

The graph is built by codegraph's own static extractor.
The constructs below either bind at RUNTIME or are handled differently than codebase-memory-mcp's graph — verified head-to-head on the same two repos (RuoYi-Vue-Plus, plus-ui) used to verify that tool's blind spots (see the `cbm-navigator` skill's own `references/blindspots.md`).
Use the native fallback instead; do not report graph emptiness here as "no usage / dead code".

## Java interface → implementation calls — codegraph handles this BETTER than codebase-memory-mcp, but not perfectly

- The underlying `codegraph callers` command is still single-hop: querying callers of an `*Impl` class method returns exactly ONE "caller" — and that caller is the interface's own method declaration line, not a real business caller.
  Confirmed on two independent pairs: `SysDeptServiceImpl.selectDeptList` → 1 caller, `ISysDeptService.java:33` (the interface declaration itself); `SysUserServiceImpl.selectUserListByDept` → 1 caller, `ISysUserService.java:230` (same shape).
  Read naively, this looks like "this method has exactly one caller" — it does not; the real callers (`SysDeptController.list`, `.excludeChild`) are invisible from this single command.
- BUT unlike codebase-memory-mcp, codegraph's graph DOES carry an explicit interface→impl edge, and two higher-level commands surface it:
  `codegraph node <method>` labels the cross-reference as `[dynamic: interface → impl @file:line]` on the Trail section, in BOTH directions (querying the interface method shows `Calls → impl [dynamic: ...]`; querying the impl method shows `Called by ← interface [dynamic: ...]`).
  `codegraph explore` goes further and lists the blast-radius entries for BOTH the interface method (2 real callers) and the impl method (1 "caller" = the interface) in the same response, so a single `explore` call already contains the full picture.
- `codegraph impact` (multi-hop, default depth 2) also bridges this automatically: `impact` on the impl method returns the real controller methods as affected nodes, because it walks impl→interface→caller as one of its hops.
  It can still miss deeper nodes (e.g. Route nodes) at the default depth if they are more than 2 hops from the impl side — raise `-d` if a route/endpoint seems to be missing from `cg-impact.sh` output on an impl-anchored query.
- `cg-trace.sh` in this skill auto-bridges the single-hop `callers` gap: when the direct result contains a caller whose name equals the queried method's own short name (the fingerprint of an interface-declaration bridge), it re-queries callers of that bridge symbol and unions the results, flagging `bridged: true`.
  This is a heuristic, not a proof — when `bridged: true` appears, cross-check with `cg-node.sh` or `cg-explore.sh` before stating a final caller count, the same discipline cbm-navigator requires unconditionally.
  Code-review note (2026-07-17): an earlier version of this bridge only recognized the plain `ClassName.methodName` shorthand — passing the full `qualifiedName` (`namespace::Class::method`, the field returned by `cg-find.sh`'s own `qualified_name` key) silently defeated the bridge with no warning, because the short-name extraction split on the last `.` and landed inside the package prefix instead of at the `::` separator. Fixed to split on `::` first when present; re-verified against both field-tested pairs (`SysDeptServiceImpl.selectDeptList`, `SysUserServiceImpl.selectUserListByDept`) with both name formats — both now bridge identically.
  Separately, `codegraph callers/callees/impact` report "symbol not found" via exit code 0 plus a non-JSON message on stdout (not an error exit, not stderr) — the scripts' error handling now parses stdout with `jq empty` to detect this instead of trusting the exit code, and surface it as a normal `hint` instead of crashing on a raw `jq` parse error.
- Outbound (impl → what it calls) is NOT affected — `codegraph callees` on the impl method returns its real internal calls directly, no bridging needed.

## CALLS edges are receiver/type-aware — no Lombok getter/setter name collision (field-verified 2026-07-18, direct contrast with codebase-memory-mcp)

- `cbm-navigator`'s own `references/blindspots.md` documents a 60% false-positive rate on `DictService.getDictLabel` callers, caused by cbm's name-only edge resolution colliding with same-named Lombok-generated getters on unrelated DTO/VO/Entity classes.
  Ran the identical scenario against codegraph: `getDictLabel` exists as a business method on `DictService`/`SysDictTypeServiceImpl` AND as a Lombok-generated getter on four unrelated classes (`SysDictData`, `SysDictDataBo`, `SysDictDataVo`, `DictDataDTO`).
  `codegraph callers "SysDictDataVo::getDictLabel"` (the Lombok getter) returned exactly its 3 real call sites, all inside `SysDictTypeServiceImpl` where that Vo's getter is genuinely invoked — zero pollution from the business method's own real external callers, and vice versa: `callers "DictService::getDictLabel"` did not include any of the Lombok-getter call sites either (its actual gap is unrelated, see the `SpringUtils.getBean(X.class)` section below).
  Root cause of the difference: codegraph's edges are keyed by qualified/receiver-typed symbol (`Class::method`), not bare method name — the collision class of bug documented for cbm-navigator does not reproduce here.
  This is a genuine accuracy advantage worth stating plainly, not just implied by "better than codebase-memory-mcp" language elsewhere in this file.

## Spring `getBean(X.class)` — deterministic single-target lookup, complete miss (field-verified 2026-07-18, distinct from and worse than the computed-name fan-out below)

- The section below covers `SpringUtils.getBean(computedName)` selecting among MULTIPLE implementations, where codegraph responds with an honest (if imprecise) fan-out listing every candidate.
  This is a different call shape entirely: `SpringUtils.getBean(DictService.class).getDictLabel(dictType, value, separator)` — a single, statically-determinable target (there is exactly one `DictService` implementation, `SysDictTypeServiceImpl`), reached through a bean-lookup-by-`Class`-literal instead of field/constructor injection.
  Confirmed on two real call sites: `DictPatternValidator.java:51` and `ExcelDictConvert.java:65`, both calling the 3-arg `DictService.getDictLabel(String,String,String)` via `SpringUtils.getBean(DictService.class).getDictLabel(...)`.
  Neither call site appears anywhere — not in `codegraph callers "DictService::getDictLabel"` (returned only the 2 real field-injected callers, `DictTypeTranslationImpl`/`SysNoticeController`), not in `codegraph node`'s Trail section for either overload, not in `codegraph impact "DictService::getDictLabel" -d 2` (stopped at the same 2 callers + the route they lead to, 4 nodes total).
  0/2 recall on this call shape, consistent across all three commands.
  This is worse than the computed-name case: that one at least surfaces something (over-inclusive candidates, flagged as uncertain via the `[dynamic: interface → impl]` fan-out), where a `SpringUtils.getBean(X.class)` chain is invisible to the extractor outright, even though the target is fully statically determinable — unlike the computed-name case, which genuinely can't be resolved without running the code.
  Consequence for `cg-impact.sh`/blast-radius analysis is direct, not theoretical: changing `DictService.getDictLabel`'s signature or behavior would silently miss `DictPatternValidator` and `ExcelDictConvert` in the reported blast radius, a false "safe to change" read on a method with 2 more real callers than reported.
  Fallback: grep `SpringUtils.getBean(<Interface>.class)` for the interface in question directly; this pattern is common enough in Spring codebases (validators, converters, static utility classes reaching into the Spring context outside normal DI) to be worth a standing spot-check on any interface method's blast radius before reporting a final caller count.

## Spring runtime bean-name lookup (`SpringUtils.getBean(computedName)`)

- Confirmed on RuoYi-Vue-Plus's `IAuthStrategy` strategy pattern (5 implementations: Email/Password/Sms/Social/Xcx AuthStrategy, each registered under a computed bean name, selected via `SpringUtils.getBean(loginType + IAuthStrategy.BASE_NAME)` at runtime).
- codegraph applies the SAME interface/impl heuristic used for ordinary DI here: `codegraph node "IAuthStrategy.login"` lists all 5 implementations as `[dynamic: interface → impl]` candidates on the Trail.
- This is honest and useful (it correctly enumerates "one of these 5 executes, decided at runtime") but it does NOT know this is a runtime-string-computed selection specifically — it would produce the exact same fan-out for an ordinary single-bean interface.
  Do not read "5 candidates listed" as "all 5 are called on every request" or as "codegraph resolved which one is called" — it did neither; it only enumerated what implements the interface.
- Fallback for the precise selection logic: grep the bean-name construction (`+ IAuthStrategy.BASE_NAME`, `@Service("...")`) directly to see how the runtime string maps to a concrete impl.

## JS/TS + dynamic `import()` (field-verified on plus-ui / Vue Router) — reproduces IDENTICALLY to codebase-memory-mcp

- Blind: components registered via `() => import('@/views/x.vue')` (Vue Router / React Router route-level code splitting) produce NO edge from the router file to the target component — same failure as codebase-memory-mcp, not something codegraph's richer edge model fixes.
- Confirmed on plus-ui's `src/router/index.ts`, which dynamically imports `login.vue` among others: `codegraph callers "src/views/login.vue::login"` returns an EMPTY callers list; `codegraph node -f src/views/login.vue --symbols-only` reports "used by 1 file: src/views/tool/gen/index.vue" — a genuinely unrelated file, not the router.
- `codegraph explore "who imports or routes to login.vue"` also does NOT surface the router → login.vue edge (it found unrelated in-component "dynamic" links like `@click` handlers, but not the route registration).
- Fallback: identical to cbm-navigator's — grep the component's file path/basename directly inside router config files rather than trusting any graph command here.

## MyBatis XML mapper binding — reproduces IDENTICALLY to codebase-memory-mcp

- codegraph DOES index `.xml` files as `file` nodes (`language: "xml"`) — the file itself is not invisible.
- But it does NOT parse the `namespace=` → Java Mapper interface binding, nor `<if>/<foreach>` dynamic SQL semantics.
  Confirmed: `codegraph node -f "ruoyi-modules/ruoyi-system/src/main/resources/mapper/system/SysDeptMapper.xml" --symbols-only` → `"0 symbols, no other indexed file depends on it"`, despite `SysDeptMapper.java` (the interface it binds to via `namespace=`) existing and being indexed separately.
- Note: as with the codebase-memory-mcp finding, RuoYi-Vue-Plus's own `*Mapper.xml` files are empty MyBatis-Plus auto-registration shells with zero hand-written SQL, so this blind spot is a structural inference confirmed against an empty-shell case — it did not have live dynamic SQL content to fail on.
  The XML-file-has-0-symbols result is still a direct, positive confirmation that codegraph does not model the namespace binding at all, regardless of SQL content.
- Fallback: identical to cbm-navigator's — grep the mapper interface FQN as XML `namespace=`, then Read the mapper XML directly.

## Class inheritance (`extends`) is one-directional in the graph — reproduces upstream open issue #1328 (field-verified 2026-07-18)

- Querying a KNOWN PARENT class's node does surface its subclasses: `codegraph node "BaseController"` lists 20+ known controller subclasses (`SysConfigController`, `SysDeptController`, `GenController`, etc.) — but under a `Called by ←` heading, the same label used for genuine call edges, not a distinct "Extended by"/"Subclasses" section.
  Read carelessly this looks like "these classes call BaseController", when the real relationship is `extends`.
  Querying a KNOWN CHILD class's node in the other direction surfaces nothing: `codegraph node "SysConfigController"` (confirmed `extends BaseController` in source) lists its 10 own members and nothing else — no mention of `BaseController`, no parent-class field, no inherited-member indication anywhere in the text output.
  Confirmed this is a schema gap, not a text-rendering omission: `codegraph query "SysConfigController" -k class -j` was inspected field-by-field — the node JSON has no `extends`/`superclass`/`implements`/`parent` key at all, only the standard location/visibility/docstring fields shared by every class node.
  This exactly matches the shape of open upstream issue [colbymchenry/codegraph#1328](https://github.com/colbymchenry/codegraph/issues/1328) ("how to know super/sub class from current class node"), filed 2026-07-17, unresolved as of this pass.
  Fallback: to find a class's parent/superclass, grep the class declaration line (`class X extends Y`) directly rather than querying the graph — the parent-class direction is exactly the one the graph does not carry.

## `cg-explore.sh`'s officially-claimed strength (single-symbol / compound questions) — re-confirmed genuinely good, with one caveat (field-verified 2026-07-17)

To verify the claimed strength, not just the aggregate-question failure mode below, ran a fresh compound query this pass: `codegraph explore "how does SysUserServiceImpl.selectUserListByDept get called, show the full call chain"`.
Result was genuinely strong: correctly surfaced the `[dynamic: interface → impl]` edge in both directions, gave real blast-radius counts for both the interface and impl copies of the method (matching the independently-confirmed `ISysDeptService`/`SysDeptServiceImpl` pair below and in `cbm-navigator/references/blindspots.md` — the same interface/impl split reproduces on a second, different service pair), and included verbatim source for all 63 retrieved symbols across 3 files in one call.
**Caveat**: even on this genuinely-good compound question, one unrelated symbol (`SysSocialController.list`) was pulled into the result set purely because the word "list" loosely matches the query's phrasing — a smaller-scale instance of the same keyword-similarity retrieval mechanism that causes the aggregate-question failures below.
On a well-scoped single-symbol question the signal-to-noise ratio is high enough to be genuinely useful (this is the tool's real strength), but do not assume every symbol in an `explore` response is relevant just because the response's overall shape looks right — a quick relevance skim of the symbol list costs far less than acting on a wrong one.

## `cg-explore.sh` fails outright on pure-Chinese-language queries (field-verified 2026-07-18) — a caveat to the "officially-claimed strength" section above

- Ran `codegraph explore` with four independent Chinese business terms on RuoYi-Vue-Plus: `"字典标签"`, `"字典标签查询"`, `"用户登录"`, `"部门管理"`.
  All four returned `No relevant code found for "..."` — zero symbols, zero source, nothing to skim for relevance, unlike the aggregate-question failure mode above which at least returns something wrong-shaped.
  Confirmed this is specific to `explore`'s own query handling, not a general Chinese-language gap in the index: `codegraph query "字典标签" -j` (the underlying FTS symbol search `cg-find.sh` wraps) on the exact same term returned well-ranked, correct hits — top match `selectDictLabel` (docstring `根据字典类型和字典键值查询字典数据信息...字典标签`, score 16.7), plus `DictService::getDictLabel`, `DictService::getDictValue`, and more genuinely related symbols in the top 10.
  The FTS5 index tokenizes and matches Chinese text fine; `explore`'s own query-phrase handling on top of it does not.
  Isolated the mechanism with a mixed-language control: `codegraph explore "SysUser 登录"` (one Latin identifier + one Chinese word) DID work — 109 symbols across multiple files, correct blast-radius output.
  `explore` appears to require at least one Latin-script/identifier-shaped token to anchor its retrieval on; a query with zero such tokens is silently dropped to an empty result rather than falling back to FTS matching on the CJK text.
  Practical impact: this hits `explore` specifically — the tool's own docs and this skill's Decision table both position it as the flagship "ask a question in plain language, one call" command, and it is the ONLY MCP tool enabled by default per the official README.
  A Chinese-only business-language question routed to `cg-explore.sh` gets a false "nothing here" instead of a wrong-shaped-but-visible answer or a graceful fallback — worse than the aggregate-question failure mode above precisely because there is no output at all to sanity-check.
  Fix shipped: `SKILL.md`'s decision table now splits business-language questions by term language, mirroring `cbm-navigator`'s existing Chinese/English split — Chinese business term → `cg-find.sh` (FTS, confirmed reliable above); pure-English term → `cg-explore.sh` directly, no caveat needed.

## Same symbol, both tools — direct interface/impl comparison (cross-referenced, not a new repro)

`codegraph` and `codebase-memory-mcp` were independently tested against the EXACT SAME interface/impl pairs on the same repo (`ISysDeptService.selectDeptList` / `SysDeptServiceImpl.selectDeptList`, and `ISysUserService.selectUserListByDept` / `SysUserServiceImpl.selectUserListByDept`) — this file documents the codegraph side, `cbm-navigator/references/blindspots.md` documents the cbm side.
Putting them side by side is itself the finding:
- **Root cause is identical on both tools**: a call through an interface-typed reference attaches its edge to the interface's method node, never the impl's — cbm's tree-sitter+LSP extractor and codegraph's extractor made the same static-typing decision independently.
  This is a property of static analysis on interface-typed calls in general, not an implementation quirk of either specific tool.
- **The two tools diverge only in what they do ABOVE that shared limitation**: cbm's Cypher engine cannot express the 2-hop bridge query at all (`unsupported EXISTS pattern` — confirmed by direct testing, see cbm's blindspots.md), so cbm-navigator's protocol is a MANDATORY manual second query + union, every time, no exceptions.
  codegraph's higher-level commands (`node`, `explore`, `impact`) DO carry an explicit interface→impl graph edge and synthesize the bridge automatically in a single call — genuinely less manual work and fewer tokens for the same question.
  `cg-trace.sh`'s bridge is a heuristic (flagged `bridged: true`) and still recommends the same cross-check discipline before a final conclusion, so the accuracy CEILING is the same on both tools; only the number of calls needed to reach it differs.

## `cg-explore.sh` on whole-graph aggregate questions — silently answers a DIFFERENT question (field-verified 2026-07-17)

- Ran three real `codegraph explore` calls on RuoYi-Vue-Plus, the exact aggregate-question shapes the earlier version of this file suggested as an `explore` fallback:
  - `explore "find methods that are never called from anywhere in the codebase (dead code)"` → returned `findFirst`/`findAny`/`findCode`/`find` (StreamUtils, DataBaseType, DataScopeType) — every one of them has 1-2 REAL callers shown in the response's own "Blast radius" section. `explore` matched the word "find" in the query against method names starting with "find"; it did not compute call-degree-zero at all.
  - `explore "which classes have the most callers, the biggest hub/god classes"` → returned `scanEncryptClasses` (1 caller) and a YAML config field `host` (1 caller) — the opposite of "most callers".
  - `explore "list all the API routes/endpoints defined by REST controllers"` → returned 26 controller methods literally named `list` (because "list" is in both the query and their names) plus a note about runtime dispatch to `BaseController` implementations. Zero `/api/...` paths appeared anywhere in the response.
- Root cause: `explore` (like `query`) is a text/embedding similarity search over symbol names and source, then it computes blast-radius/call-paths for whatever it retrieved. It has no notion of "zero incoming edges", "sort by degree", or "node kind == route" — there is no aggregate/analytic mode at all, confirmed by `codegraph --help` (`explore`, `node`, `query`, `callers/callees/impact`, `affected` — no `stats`/`hubs`/`unused` command exists).
- The dangerous part is not that it's blind — codebase-memory-mcp is equally blind to some things — it's that the response is formatted with the same confidence markers (⚠️ "no covering tests", numbered "Blast radius" caller counts, a "Relationships" section) whether or not the retrieved symbols have anything to do with the question. Nothing in the output signals "these symbols were chosen by keyword coincidence."
- Fix shipped: `SKILL.md`'s decision table now explicitly routes whole-graph aggregate questions away from `cg-explore.sh`. Dead-code/hubs/cross-layer remain genuine capability gaps for codegraph (fall back to `cbm-cypher.sh` or grep); routes turned out to have a real, accurate equivalent — see next section.

## `cg-find.sh -k <kind>` with an empty pattern = accurate exhaustive listing (field-verified 2026-07-17) — routes is NOT actually a gap

- `codegraph query '' -k route -j -l 500` on RuoYi-Vue-Plus returned exactly 303 results — an EXACT match against `codegraph status -j`'s `nodesByKind.route` (303). Same exact-match verification repeated for `-k class` (482/482). On plus-ui (TS/Vue), `-k component` correctly enumerated all 99 Vue components (matches `nodesByKind.component`).
- Each route result includes the real HTTP verb and full path as its `name`, e.g. `"DELETE /auth/unlock/{socialId}"` — arguably more precise than `cbm-cypher.sh routes`, whose Cypher template only returns the path (verb not modeled in that graph schema).
- This means the original "(no direct equivalent)" verdict for "routes list" in `SKILL.md` was wrong — corrected. Dead-code and hubs are still genuine gaps (no node property encodes call-degree or callers-count for a direct filter/sort).
- Two bugs found and fixed while confirming this:
  1. `cg-find.sh -k route` (pattern omitted entirely, the natural way to ask "list all routes") crashed with `line 6: $1: unbound variable` — `set -u` treats a missing positional param as unbound, and the script assumed a pattern was always given. Fixed: `Q="${1:-}"`.
  2. Once that crash was fixed, the *default* limit (20) silently under-returned: with an EMPTY pattern, codegraph's own `-l` behaves like a per-file/group multiplier, not a literal cap — `-l 1` returned 5 rows, `-l 3` returned 15, `-l 5` returned 25 (a consistent ~5x on this repo; the exact ratio is not something to depend on). `cg-find.sh` now defaults `-l` to 500 specifically when the pattern is empty (kept at 20 for normal fuzzy search), so "list all X" actually returns everything by default. With a non-empty pattern `-l` was confirmed to behave as a normal literal cap (`-l 3` on `"system"` → exactly 3 rows) — the quirk is specific to the empty-pattern case.

## Windows: concurrent access hard-fails a full `index` rebuild — broader than upstream issue #1325 (field-verified 2026-07-18)

- Upstream issue [colbymchenry/codegraph#1325](https://github.com/colbymchenry/codegraph/issues/1325) reports `codegraph index` failing with "database file is in use" specifically when an MCP server is still running against the same project.
  Reproduced a broader version with no MCP server involved at all: launched a plain `codegraph query "Sys" --limit 5 --json` in the background, then immediately ran `codegraph index --quiet` in the foreground on the same project (local NTFS disk, WAL journal mode — none of the network-share/WSL2 caveats already documented upstream apply here).
  Result: hard failure, not a queue/retry — `[ERR] Failed to index: Could not rebuild the index — the database file is in use (EPERM, Permission denied: ...codegraph.db ...)`.
  `codegraph status` immediately after confirmed the existing index was untouched (same file/node/edge counts as before the attempt) — the failure aborts cleanly, it does not corrupt the database.
  Practical implication for this skill (CLI-only, no MCP server, so the upstream issue's specific trigger doesn't apply): a full `codegraph index --force` should not be run from one shell while another `codegraph` command — even a plain read-only `query` — might still be in flight in the same session.
  The lighter-weight `codegraph sync` used for normal incremental updates (see Quality rules) was not observed to hit this in the same test and is the safer default; reserve `index --force` for cases that actually need a full rebuild, and run it standalone.

## `install.sh` fails immediately under Git Bash / MINGW64 on Windows — root cause confirmed by reading the script (field-verified 2026-07-18)

- Open upstream issue [colbymchenry/codegraph#1294](https://github.com/colbymchenry/codegraph/issues/1294), "codegraph: unsupported OS 'MINGW64_NT-10.0-26200'", filed 2026-07-15, no maintainer response as of this pass.
  Fetched `install.sh` directly: its OS detection is `os="$(uname -s)"` followed by a `case` statement with exactly two branches, `Darwin` and `Linux` — every other value, including any MINGW/MSYS/CYGWIN string Git Bash reports, falls through to `*) echo "codegraph: unsupported OS '$os'."; exit 1`.
  `uname -s` on the machine used for this whole verification pass returns `MINGW64_NT-10.0-26200` — the exact string in the open issue, not a coincidence; running `install.sh` from Git Bash on this or any similarly-configured Windows machine will hit that `exit 1` branch every time.
  Not a blocker for this skill in practice: `README.md`'s own install instructions already use `npm i -g @colbymchenry/codegraph` (confirmed working, v1.4.1, this entire verification pass ran through it), which has no OS-detection step at all.
  Documented here so nobody "fixes" a working npm-based setup by switching to `install.sh` on a Windows/Git-Bash machine expecting it to be equivalent — it will not run at all there; use PowerShell's `install.ps1` instead if a standalone binary (not npm) is specifically wanted on Windows.

## Not tested / out of scope for this pass

- Laravel/Django/PHP/Python-specific magic (Facades, Eloquent, URLconf, signals): not re-tested against codegraph in this pass; codegraph's own README claims "limited static analysis for dynamic dispatch and reflection" in general, treat these as unverified-until-spot-checked, same standing rule as cbm-navigator's blindspots.md.
- Cross-repository aggregation: codegraph indexes per-directory (`.codegraph/` at the repo root, resolved from cwd or `-p`), same one-graph-per-repo model as codebase-memory-mcp — no multi-root aggregation confirmed either way, not tested here.
- `codegraph install` (the MCP-server registration subcommand) was deliberately never run in this verification pass — this skill only uses the CLI directly, matching cbm-navigator's zero-MCP design.

## Methodology note (2026-07-16)

All findings above were obtained by running codegraph v1.4.1 directly against RuoYi-Vue-Plus and plus-ui, the same repos and the same interface/impl/route/mapper symbols used to verify codebase-memory-mcp's blind spots — a genuine head-to-head, not a reading of codegraph's own documentation.
Re-verify after a codegraph version bump; `codegraph node`/`explore`'s dynamic-dispatch synthesis in particular is exactly the kind of feature that could change shape between releases.

## Cross-checked against upstream sources (2026-07-17) — read the confidence labels, do not treat these as equal to the live-CLI findings above

The 2026-07-17 findings above (explore's aggregate-question failures, the `-l` empty-pattern quirk, the `cg-find.sh` bugs) were all obtained by directly RUNNING the CLI and observing byte-level output — those stand on their own regardless of anything below.
What follows is supplementary web research (GitHub README/issues, fetched and paraphrased by a summarizing tool, not independently executed) — useful for context and citation-checking, but weaker evidence than a live repro, and it is labeled accordingly. Do not upgrade a "documentation says" line below into a "field-verified" claim elsewhere in this skill.

**Re-confirmed by direct execution just now (HIGH confidence, not a web claim):** `codegraph callers "totallyBogusXYZ999" -j` on a bare, un-wrapped CLI call → exit code `0`, stdout is `\x1b[34m[i]\x1b[0m Symbol "..." not found\n` verified byte-for-byte with `xxd` (real ANSI escape bytes `1b 5b 33 34 6d`, not JSON). This is the fact the whole `cg_call()` fix rests on, and it needs no documentation to be true.

**Documentation research (MEDIUM confidence — read, not run):**
- `explore`'s scope: the README's own description ("returns relevant symbols' verbatim source ... plus call paths ... and a blast-radius summary") does not mention dead-code/hub/aggregate analysis. This is low-risk as a paraphrase (short, specific claim) and, more importantly, is not the load-bearing evidence anyway — the load-bearing evidence is the three live `explore` repros already in this file that show it returning keyword-matched wrong answers. Treat this doc line as "consistent with", not "proof of", that finding.
- `CLAUDE.md` verbatim (re-fetched requesting an exact quote, not a summary, to reduce paraphrase risk): "`isError` is reserved for genuine 'stop trying' cases ... every expected/recoverable condition — project not indexed, symbol not found, file not in the index — returns a SUCCESS-shaped response carrying the guidance (`NotIndexedError` → `textResult`, see `ToolHandler.execute`'s catch) ... the old empty-`tools/list` gate was removed in #964". The terms `ToolHandler.execute`, `tools/list`, and `textResult` are MCP-protocol vocabulary, which is why we read this passage as describing the MCP server path specifically — but the document never states in so many words "this does not apply to the CLI", and this skill cannot test an actual MCP session (it deliberately never runs `codegraph install`) to confirm the CLI truly falls outside this guarantee. **Treat "this design principle is MCP-only" as our plausible inference from terminology, not a confirmed fact** — the confirmed fact is only the byte-level CLI behavior above, which is what `cg_call()` actually fixes regardless of why the gap exists.
- Closed issue [colbymchenry/codegraph#551](https://github.com/colbymchenry/codegraph/issues/551) ("Support inheritance/implementation navigation") requested a capability that resembles `node`/`explore`'s `[dynamic: interface → impl]` synthesis — read via a paraphrased fetch, not the raw thread, and the summary explicitly said the thread doesn't discuss the single-hop `callers` gap this file documents. Treat this as a loose, unconfirmed association, nothing more.
- The empty-pattern `-l` multiplier behavior was searched for in the README, the CLI reference site, and issue search, and not found documented anywhere — this doc-search absence is consistent with (but doesn't add confidence beyond) the live finding already in this file; it remains the least durable claim here, re-check it first after any codegraph upgrade.
- `cbm-navigator`'s existing citations were spot-checked: [DeusData/codebase-memory-mcp#734](https://github.com/DeusData/codebase-memory-mcp/issues/734) — a paraphrased fetch reported its title/content as matching the existing citation (class-level `@RequestMapping` prefix dropped from Route nodes), status open. The main-branch README was likewise reported to show a `--raw` flag — consistent with the existing "main docs ahead of the shipped v0.9.0 CLI" finding, which itself WAS independently confirmed by directly running `--raw` and getting "unknown tool: --raw" (see `_project.sh`), so that underlying claim does not depend on this web check at all.
- Not re-checked against docs at all: the MyBatis-XML/Vue-dynamic-import/Spring-`getBean` blind spots on both tools. These are "tool does NOT do X" claims — no README documents the absence of a feature — so doc research cannot confirm or refute them; only the live testing already in this file (and cbm-navigator's own blindspots.md) can, and that is what they rest on.

## Methodology note (2026-07-18 pass)

This pass ran the CLI directly against RuoYi-Vue-Plus (v1.4.1, same version as the 2026-07-16 pass, no upgrade in between) with an explicit goal: verify the suitable/limited-use scenarios drafted from web research (official docs, GitHub issues) against live command output, not just read the docs.
Every finding above dated 2026-07-18 is a direct CLI repro — the GitHub issue numbers cited (#1294, #1325, #1328) are corroborating context found via web research BEFORE the live repro, then independently reproduced live; none of them are asserted on the issue text alone, unlike the weaker "documentation research" citations in the section above.
The `SpringUtils.getBean(X.class)` and Chinese-`explore` findings were not suggested by any upstream issue or doc — both were discovered by testing this skill's own existing claims (the interface/impl synthesis strength, and the general "ask in plain language" pitch for `explore`) against edge cases the existing blindspots.md hadn't yet covered, not by looking for known bugs.
