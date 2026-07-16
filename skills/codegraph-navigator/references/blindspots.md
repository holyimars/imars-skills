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

## Not tested / out of scope for this pass

- Laravel/Django/PHP/Python-specific magic (Facades, Eloquent, URLconf, signals): not re-tested against codegraph in this pass; codegraph's own README claims "limited static analysis for dynamic dispatch and reflection" in general, treat these as unverified-until-spot-checked, same standing rule as cbm-navigator's blindspots.md.
- Cross-repository aggregation: codegraph indexes per-directory (`.codegraph/` at the repo root, resolved from cwd or `-p`), same one-graph-per-repo model as codebase-memory-mcp — no multi-root aggregation confirmed either way, not tested here.
- `codegraph install` (the MCP-server registration subcommand) was deliberately never run in this verification pass — this skill only uses the CLI directly, matching cbm-navigator's zero-MCP design.

## Methodology note (2026-07-16)

All findings above were obtained by running codegraph v1.4.1 directly against RuoYi-Vue-Plus and plus-ui, the same repos and the same interface/impl/route/mapper symbols used to verify codebase-memory-mcp's blind spots — a genuine head-to-head, not a reading of codegraph's own documentation.
Re-verify after a codegraph version bump; `codegraph node`/`explore`'s dynamic-dispatch synthesis in particular is exactly the kind of feature that could change shape between releases.
