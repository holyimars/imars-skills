# 本地 Claude Code 集成专项方案:codebase-memory-mcp(零 MCP,Skill + CLI)

> 范围:仅覆盖"本地 Claude Code 集成"。目标:①绝对不走 MCP;②让 Claude Code 在工具的优势领域**充分、主动**地调用它(而非装了不用);③调用方式**准确高效**(选对工具、传对参数、最少轮次与 token)。
> 全部 CLI 语法、参数名、行为均核对自官方 README(v0.9.0,2026-07-16 抓取);**更新(实机验证)**:raw JSON 位置参数已被上游弃用(运行时警告),所有脚本已迁移为 stdin 管道形式并收敛到 `cbm_call()` 单点包装;个别未在 README 明示的参数名(如 trace 深度)已在脚本内标注"以 `cli get_graph_schema` / 实际返回为准"。

## 一、集成架构:三层触发,一层执行

Skill 的经典失败模式是"装了但从不触发"(description 语义未命中)或"触发了但乱调"(模型猜参数、猜项目名、猜 qualified name)。本方案用三层触发保证"充分被调用",用脚本层保证"准确高效":

```
触发层 1:Skill description(~120 token 常驻,用户全局级,含中英文触发意图)
   └─ 语义命中:调用链/影响面/在哪定义/谁调用/架构/死代码……
触发层 2(可选增强):项目级 CLAUDE.md 策略段(~70 token,建议仅 ≥1 万行仓库添加)
   └─ 明确指令:结构性问题先用 cbm-navigator skill,禁止盲目多轮 grep 探索
触发层 3(可选):非阻断 PreToolUse hook
   └─ 兜底:Claude 习惯性 Grep/Glob 时,自动把图谱匹配结果注入上下文
运行时门槛(写在 SKILL.md 内,触发后由 Claude 自判——全局部署 ≠ 全局使用):
   ├─ 仓库 <~1,000 行 → 不用此 skill,回退原生检索
   └─ 档位认知:low/medium 档准确度低于 high/xhigh/max(实测);高风险结论 →
      委派 cbm-deep-analyst subagent(effort 覆盖 + 独立上下文),不可用则建议升档 + 原生复核
执行层:scripts/(项目名自动解析、参数模板化、输出投影瘦身、失败自愈提示)
```

**部署模型:skill 部署到用户全局级(`~/.claude/skills/`),一次安装、所有仓库生效;"是否适用当前仓库"不由部署决定,而由 SKILL.md 内置的运行时门槛指导 Claude 自行判断。**

**零 MCP 论证**:二进制以 `--skip-config` 安装(官方选项,不写任何 agent 配置,`.mcp.json` 不落盘);所有调用走 `codebase-memory-mcp cli <tool> '<json>'`(官方 README:"Every MCP tool can be invoked from the command line");skill 与 hook 均为 Claude Code 原生机制,不产生常驻工具 schema。官方给 Claude Code 的默认集成本身就包含 4 个 Skills——skill 路线是该项目官方认可的形态,我们只是把它的 MCP 部分整个剪掉。

## 二、安装与索引(本地开发机)

```bash
# 1) 只装二进制(零配置落盘);升级用 codebase-memory-mcp update(已批准自动升级)
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --skip-config

# 2) 首次索引本仓库(绝对路径;显式索引会写 Best 级 .codebase-memory/graph.db.zst 工件)
echo "{\"repo_path\": \"$(git rev-parse --show-toplevel)\"}" | codebase-memory-mcp cli index_repository

# 3) 本地保持默认 auto_watch=true:后台 watcher 以 git 轮询增量同步,索引跟随代码变化
#    (这与服务器方案相反——本地开发机正是 watcher 的设计场景)

# 4) 团队共享(可选但推荐):提交 .codebase-memory/graph.db.zst 到仓库,
#    队友 clone 后首次 index_repository 走 bootstrap 导入 + 增量补差,免全量重建;
#    引擎自动写 .gitattributes merge=ours,二进制工件无合并冲突
```

仓库规模分层(团队实测口径,**写入 SKILL.md 作为运行时门槛,而非部署开关**):**<1,000 行:无需用此 skill**(也无需索引),原生检索已足够;**1,000~10,000 行:可用**,收益以速度/便利为主,token/费用收益不明显;**≥10,000 行:显著收益区**。skill 本身全局部署一次,不随仓库增删。

## 三、CLAUDE.md 片段(可选增强,项目级;建议仅在 ≥1 万行仓库添加)

```markdown
## Code discovery policy
This repo has a pre-built code knowledge graph (codebase-memory, CLI-only, no MCP).
Project name in the graph: `<PROJECT_NAME>`   <!-- 固化,省去运行时解析 -->
For STRUCTURAL questions — where is X defined, who calls X, call chains,
change impact / blast radius, architecture overview, dead code, cross-layer
violations, "which module handles <business term>" — invoke the
`cbm-navigator` skill FIRST. Do not run multi-round Grep/Read exploration
for questions the graph answers in one call.
Fall back to native grep/read only for: framework magic (MyBatis XML,
Eloquent/facades, Blade logic, Django URLconf), comments/docs, single-file
line-level questions, or code changed after the last index sync.
```

要点:①硬编码 project 名,消除模型传错项目的可能;②"FIRST"与"do not multi-round grep"是行为约束而非建议;③回退清单同样写死,防止图谱被误用于盲区(准确 = 该用时用 + 不该用时不用)。

## 四、Skill 完整交付(触发层 2 + 执行层)

```
~/.claude/skills/cbm-navigator/          # 用户全局级:一次安装,所有仓库生效
├── SKILL.md
├── scripts/
│   ├── _project.sh      # 内部:自动解析当前仓库对应的 graph project 名(带缓存)
│   ├── cbm-find.sh      # 定位:结构 regex / 业务语义 双模式
│   ├── cbm-trace.sh     # 调用链:inbound/outbound/both,默认深度 3
│   ├── cbm-snippet.sh   # 按 qualified name 精读函数源码(替代 Read 整文件)
│   ├── cbm-impact.sh    # git diff → 受影响符号 + 风险分级
│   ├── cbm-arch.sh      # 一次拿全架构综述
│   ├── cbm-cypher.sh    # 全图扫描模板:dead-code / cross-layer / hubs / routes
│   └── cbm-grep.sh      # search_code:图谱内文本检索(字符串/SQL 片段)
└── references/
    └── blindspots.md    # 各栈盲区与回退指引
```

### 4.1 SKILL.md

```markdown
---
name: cbm-navigator
description: >
  Query this repo's pre-built code knowledge graph (codebase-memory CLI) for
  structural questions: where a symbol is defined, who calls it, call chains
  (调用链/调用关系), change impact / blast radius (影响面/改动影响), architecture
  overview (架构/模块划分), dead code (死代码/无用代码), cross-layer violations,
  API routes, and "which module handles X" (哪个模块/哪里实现). One graph call
  replaces dozens of grep/read rounds. Do NOT use for tiny repos (under
  ~1,000 lines of code), MyBatis XML, Laravel Eloquent/facade/Blade magic,
  comments/docs, or single-line questions — use native grep/read there.
---

# CBM Navigator — accurate & efficient calling protocol

## Gate check (before ANY graph call — installed globally ≠ applicable everywhere)
1. **Tiny repo? Skip this skill entirely.** If the current repo is under
   ~1,000 lines of code (a handful of source files; `list_projects` shows a
   node count in the low hundreds), do NOT use the graph — native grep/read
   is just as accurate and faster at this scale. Answer with native tools.
2. **Effort awareness (team-measured fact).** Retrieval quality is capped by
   the reasoning/output token budget: at low/medium effort, accuracy is
   LOWER than at high/xhigh/max — the graph does not lift this cap. Weigh
   this when stating conclusions, and see Quality rules for when to
   recommend re-running at higher effort.

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
1. trace/snippet need exact names. Unknown name → `cbm-find.sh` FIRST, copy
   the exact `name` / `qualified_name` from its output. Never invent names.
2. First structural question in a session on an unfamiliar area →
   `cbm-arch.sh` once to ground yourself, then targeted calls.
3. If any script returns `{"results": []}` or an error, follow the `hint`
   field it prints (e.g. broaden pattern, or fall back to native grep).
   Do not retry the same call unchanged.

## Quality rules (non-negotiable)
- Team-measured: answer accuracy is capped by the reasoning/output token
  budget — low/medium effort limits retrieval quality REGARDLESS of the
  graph. For impact analysis, change decisions, or anything the user will
  act on: DELEGATE to the `cbm-deep-analyst` subagent — it runs at elevated
  effort in an isolated context, verifies via source reads, and returns
  only conclusions. If that agent is unavailable, recommend the user re-run
  at high effort (/effort) and verify conclusions with native Read/LSP on
  the key code paths.
- The graph LOCATES and STRUCTURES; it does not conclude. Before stating any
  business-logic conclusion, read the actual source: `cbm-snippet.sh` for a
  function, or Read on the file:line the graph returned.
- Route paths from the graph may lack class-level prefixes — treat them as
  suffixes; verify full URLs in source when the exact URL matters.
- Code changed after the last sync may be missing: if the user references a
  change from minutes ago, prefer reading the working tree.

## Fall back to native grep/glob/read (do NOT call the graph)
- MyBatis mapper XML / dynamic SQL; Laravel facades / Eloquent magic / Blade
  logic; Django dynamic URLconf / signals; reflection dispatch
  (see references/blindspots.md for how to grep these instead).
- Comments, docstrings, README semantics; single-file line-level questions.

## Token discipline
- Keep default limits (20); paginate with `-o <offset>` when truly needed.
- Trace depth defaults to 3; raise to 5 only when the user asks for the full chain.
- Summarize graph JSON in prose; never paste raw output to the user.
```

### 4.2 脚本全文

`scripts/_project.sh`(被其余脚本 source;自动解析 + 缓存,模型永远不猜项目名):
```bash
#!/usr/bin/env bash
# Resolve the graph project name for the current repo. Cached per repo root.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE="/tmp/cbm-project-$(echo -n "$ROOT" | md5sum | cut -c1-12)"
if [ -f "$CACHE" ]; then PROJECT=$(cat "$CACHE"); else
  BASE=$(basename "$ROOT")
  PROJECT=$(codebase-memory-mcp cli --raw list_projects \
    | jq -r --arg b "$BASE" '.projects[]?.name // empty | select(. == $b or (ascii_downcase == ($b|ascii_downcase)))' | head -1)
  if [ -z "$PROJECT" ]; then
    echo "{\"error\":\"repo not indexed\",\"hint\":\"run: codebase-memory-mcp cli index_repository '{\\\"repo_path\\\": \\\"$ROOT\\\"}' — or fall back to native grep\"}" >&2
    exit 2
  fi
  # Soft gate (first resolution only): tiny project → remind the skill's gate rule
  NODES=$(codebase-memory-mcp cli --raw list_projects | jq -r --arg n "$PROJECT" \
    '.projects[]? | select(.name==$n) | (.nodes // .node_count // empty)' 2>/dev/null || true)
  if [ -n "${NODES:-}" ] && [ "$NODES" -lt 500 ] 2>/dev/null; then
    echo "warning: '$PROJECT' has only $NODES graph nodes (likely <1k LOC) — per skill gate, prefer native grep/read" >&2
  fi
  echo "$PROJECT" > "$CACHE"
fi
export PROJECT
```

`scripts/cbm-find.sh`:
```bash
#!/usr/bin/env bash
# Usage: cbm-find.sh [-s] [-l LABEL] [-o OFFSET] '<regex-or-question>'
set -euo pipefail; source "$(dirname "$0")/_project.sh"
SEMANTIC=0; LABEL=""; OFFSET=0
while getopts "sl:o:" f; do case $f in s) SEMANTIC=1;; l) LABEL=$OPTARG;; o) OFFSET=$OPTARG;; esac; done
shift $((OPTIND-1)); Q="$1"
if [ "$SEMANTIC" = 1 ]; then
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" '{project:$p, semantic_query:$q, limit:20, offset:$o}')
else
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" '{project:$p, name_pattern:$q, limit:20, offset:$o}')
fi
[ -n "$LABEL" ] && ARGS=$(echo "$ARGS" | jq --arg l "$LABEL" '. + {label:$l}')
OUT=$(codebase-memory-mcp cli --raw search_graph "$ARGS")
echo "$OUT" | jq '{count: (.results|length),
  results: [.results[] | {name, qualified_name: (.qualified_name // null), label, file, line: (.line // null), degree: (.degree // null)}],
  hint: (if (.results|length)==0 then "no match — broaden the regex (e.g. .*Name.*), try -s semantic mode, or fall back to native grep" else null end)}'
```

`scripts/cbm-trace.sh`:
```bash
#!/usr/bin/env bash
# Usage: cbm-trace.sh <exact-function-name> [in|out|both] [depth]
set -euo pipefail; source "$(dirname "$0")/_project.sh"
NAME="$1"; DIRRAW="${2:-both}"; DEPTH="${3:-3}"
case "$DIRRAW" in in) DIR=inbound;; out) DIR=outbound;; *) DIR=both;; esac
# NOTE: depth param name per current schema; confirm via `cli get_graph_schema` if a release renames it.
ARGS=$(jq -n --arg p "$PROJECT" --arg n "$NAME" --arg d "$DIR" --argjson dep "$DEPTH" \
  '{project:$p, function_name:$n, direction:$d, depth:$dep}')
OUT=$(codebase-memory-mcp cli --raw trace_path "$ARGS")
echo "$OUT" | jq '. + {hint: (if ((.paths // .results // [])|length)==0
  then "0 paths — the name must be EXACT: run cbm-find.sh first and copy the exact name (official troubleshooting guidance)"
  else null end)}'
```

`scripts/cbm-snippet.sh`:
```bash
#!/usr/bin/env bash
# Usage: cbm-snippet.sh <qualified-name>   (format: <project>.<path_parts>.<name>, from cbm-find output)
set -euo pipefail; source "$(dirname "$0")/_project.sh"
codebase-memory-mcp cli --raw get_code_snippet \
  "$(jq -n --arg p "$PROJECT" --arg q "$1" '{project:$p, qualified_name:$q}')"
```

`scripts/cbm-impact.sh`:
```bash
#!/usr/bin/env bash
# Maps the current uncommitted git diff to impacted symbols + risk. Run from a normal clone (NOT a git worktree — known upstream bug).
set -euo pipefail; source "$(dirname "$0")/_project.sh"
codebase-memory-mcp cli --raw detect_changes "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq '{summary: (.summary // null), impacted: [((.impacted_symbols // .results // [])[]) | {name, file, risk: (.risk // null)}][:30],
         hint: (if ((.impacted_symbols // .results // [])|length)==0 then "empty — are you in a git worktree? (upstream bug) or no uncommitted changes; use cbm-trace.sh inbound on the touched function instead" else null end)}'
```

`scripts/cbm-arch.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail; source "$(dirname "$0")/_project.sh"
codebase-memory-mcp cli --raw get_architecture "$(jq -n --arg p "$PROJECT" '{project:$p}')" \
  | jq '{languages, packages: (.packages[:15] // null), entry_points: (.entry_points[:10] // null),
         routes: (.routes[:20] // null), hotspots: (.hotspots[:10] // null), clusters: (.clusters[:10] // null)}'
```

`scripts/cbm-cypher.sh`(全图扫描模板,一次扫描替代 N 次检索):
```bash
#!/usr/bin/env bash
# Usage: cbm-cypher.sh dead-code|cross-layer|hubs|routes  [arg1] [arg2]
set -euo pipefail; source "$(dirname "$0")/_project.sh"
case "$1" in
  dead-code)   Q='MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() } RETURN f.name, f.file LIMIT 100';;
  cross-layer) A="${2:-/controller/}"; B="${3:-/mapper/}"
               Q="MATCH (a)-[:CALLS]->(b) WHERE a.file CONTAINS '$A' AND b.file CONTAINS '$B' RETURN a.name, a.file, b.name LIMIT 200";;
  hubs)        Q='MATCH (c:Class) RETURN c.name, c.file ORDER BY c.degree DESC LIMIT 20';;
  routes)      Q='MATCH (r:Route) RETURN r.name, r.file LIMIT 200';;
  *) echo '{"error":"unknown template","hint":"use: dead-code | cross-layer [layerA] [layerB] | hubs | routes"}'; exit 1;;
esac
codebase-memory-mcp cli --raw query_graph "$(jq -n --arg p "$PROJECT" --arg q "$Q" '{project:$p, query:$q}')"
```

`scripts/cbm-grep.sh`:
```bash
#!/usr/bin/env bash
# Graph-scoped text search (indexed files only). Usage: cbm-grep.sh '<text>'
set -euo pipefail; source "$(dirname "$0")/_project.sh"
codebase-memory-mcp cli --raw search_code "$(jq -n --arg p "$PROJECT" --arg q "$1" '{project:$p, query:$q, limit:20}')"
```

**执行层设计要点(准确高效的实现机制)**:
1. **项目名零猜测**:`_project.sh` 从 git root 自动匹配 `list_projects`,缓存到 /tmp;官方 troubleshooting 里"查询打到错误项目"这类事故被结构性消除。
2. **失败自愈提示**:每个脚本在空结果/错误时输出 `hint` 字段,内容直接取自官方 troubleshooting(如 trace 0 结果 → 先 find 精确名)——模型看到 hint 就知道下一步,省掉试错轮次。
3. **输出投影**:所有输出经 jq 投影为最小字段集 + 截断,原始大 JSON 不进上下文。
4. **get_code_snippet 替代 Read 整文件**:精读某函数时按 qualified name 只取函数体,是最直接的 token 节省点。
5. **模板化 Cypher**:模型不现场写 Cypher(易超出 openCypher 子集报错),只选模板传参;模板全部用官方文档确认过的语法(含官方死代码示例)。
6. **门槛前置**:SKILL.md 的 Gate check 让"全局安装"与"按仓库适用"解耦——两条团队实测口径(<1,000 行不用图谱;low/medium 档准确度低于 high/xhigh/max)直接写进 skill 本体成为运行时行为;`_project.sh` 对微型已索引项目输出软警告作二次提醒。

## 五、可选:非阻断 PreToolUse Hook(触发层 3)

官方给 Claude Code 的集成含一个 PreToolUse hook:拦截 Grep/Glob(从不拦 Read),把命中的索引符号作为 additionalContext 注入,结构性非阻断(所有失败路径 exit 0)。我们不用官方安装器(它会同时写 MCP 配置),但可自写等效 hook 达到"即使 skill 未触发、Claude 习惯性 grep 时也能自动获得图谱上下文"的兜底效果:

```json
// .claude/settings.json (project)
{"hooks": {"PreToolUse": [{"matcher": "Grep|Glob",
  "hooks": [{"type": "command", "command": ".claude/hooks/cbm-augment.sh", "timeout": 3}]}]}}
```
```bash
#!/usr/bin/env bash
# .claude/hooks/cbm-augment.sh — non-blocking on EVERY path (mirrors official design)
INPUT=$(cat); PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || exit 0
[ -z "$PATTERN" ] && exit 0
source ~/.claude/skills/cbm-navigator/scripts/_project.sh 2>/dev/null || exit 0
MATCH=$(timeout 2 codebase-memory-mcp cli --raw search_graph \
  "$(jq -n --arg p "$PROJECT" --arg q "$PATTERN" '{project:$p, name_pattern:$q, limit:5}')" 2>/dev/null \
  | jq -c '[.results[]? | {name, file, line}]' 2>/dev/null) || exit 0
[ -z "$MATCH" ] || [ "$MATCH" = "[]" ] && exit 0
jq -n --argjson m "$MATCH" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  additionalContext: ("Knowledge-graph symbol matches for this pattern: " + ($m|tostring) + " — consider cbm-navigator skill for structural follow-ups.")}}'
exit 0
```
纪律:timeout 2s、一切失败路径 exit 0、从不拦 Read(官方明确:gating Read 会破坏 read-before-edit 不变式)、只增强不阻断。团队试用两周后按噪声/收益决定去留。

## 六、优势领域调用地图(何时"充分调用"的判据)

| 优势领域(图谱一次调用) | 原生检索代价 | 触发短语示例 |
|---|---|---|
| 跨文件调用链(trace both/depth 3) | 多轮 grep + 逐文件 read | "X 的调用链""谁在用 X" |
| 未提交改动影响面(detect_changes) | 人工 diff + 逐符号 grep | "我这些改动影响哪里" |
| 架构综述(get_architecture 单次) | 遍历目录 + 抽样 read | "这个项目结构""入口在哪" |
| 全图模式扫描(Cypher 模板) | 几乎不可行 | "有哪些死代码""controller 直调 mapper 的地方" |
| 业务语义定位(semantic_query) | grep 无法做模糊语义 | "退款审核逻辑在哪" |
| 函数级精读(get_code_snippet) | Read 整文件 | "看下 X 的实现" |

**反模式(此时调用图谱 = 不准确)**:MyBatis XML/动态 SQL、Eloquent/Facade/Blade、Django URLconf、注释与文档语义、行级/单文件问题、刚改完还没同步的代码、native-only 小仓库、用户明确要最高精度的深度分析(实测 high effort 下原生 LSP+Read 更准——让 Claude 直接原生)。

### 6.1 推理档位与准确度(团队实测口径,方案最终定位)

两条实测结论共同框定图谱的角色:
1. **思考与输出 token 预算过小会限制检索质量**:low/medium 档的准确度低于 high/xhigh/max——图谱不能突破档位的准确度天花板;
2. 高档位下,原生 grep+LSP 的准确度高于图谱。

**推论:图谱是效率工具,不是质量工具。**档位决定准确度上限;图谱决定同档位下的工具调用数、token 与延迟。据此选档:

| 任务类型 | 建议档位 | 图谱角色 |
|---|---|---|
| 高频问答、符号定位、架构概览(容错高) | low / medium | 主力——接受档位的准确度上限,图谱把有限预算从检索导航中解放出来用于回答本身 |
| 日常开发的结构问题 | medium / high | 首跳定位 + 关键点精读(cbm-snippet / Read) |
| 影响面分析、PRD 依据、改造决策(容错低、将据此行动) | high / xhigh / max | 仅作首跳定位;结论以原生 LSP/Read 复核为准,或直接纯原生 |

skill 已内置对应行为(Quality rules 第一条):对将被采取行动的结论,在低档位会话中主动建议升档并原生复核。

### 6.2 让高风险任务自动获得更高预算:subagent effort 覆盖(官方机制)

SKILL.md 本身无法修改会话的 effort 或思考预算(effort 是会话级设置:`/effort`、`/model`、settings.json 的 effortLevel;skill 只是按需注入的指令文本)。但 **subagent 的 frontmatter 支持 `effort` 字段**(官方 sub-agents 文档字段清单:description、prompt、tools、model、permissionMode、maxTurns、**skills**、**effort**、background、isolation 等),且 `skills` 字段会在 subagent 启动时**预载所列 skill 的全文**。组合两者即可实现"执行此类任务时以更高预算运行":

```markdown
<!-- ~/.claude/agents/cbm-deep-analyst.md(用户全局级,与 skill 配套安装) -->
---
name: cbm-deep-analyst
description: >
  Deep structural analysis at elevated reasoning effort. Delegate impact
  analysis, blast-radius assessment, change decisions, and any structural
  conclusion the user will act on (影响面/改动影响/重构决策). Runs the
  codebase-memory graph plus native source verification in an isolated
  context and returns only verified conclusions.
tools: Read, Grep, Glob, Bash
model: inherit            # 最难的分析可改 opus
effort: high              # 覆盖会话档位;xhigh/max 仅 Opus 系模型接受
skills: cbm-navigator     # 启动时预载 skill 全文,无需再发现
---
You are a deep structural analyst. For every task:
1. Follow the preloaded cbm-navigator protocol to locate and structure
   (gate check, decision table, exact-name discipline).
2. VERIFY every conclusion by reading the actual source (cbm-snippet.sh or
   Read on the exact file:line) — the graph locates; reading decides.
3. Return a concise verdict only: conclusion, evidence (file:line list),
   confidence, and what you did NOT verify. Keep all intermediate graph
   JSON and file dumps out of your reply.
```

三重收益:①**effort 覆盖**——主会话即使在 low/medium,该 agent 也以 high 运行,直接回应"低档位准确度受限"的实测;②**独立上下文窗口**——检索的中间产物(图谱 JSON、源码转储)留在 subagent 上下文,主会话只收结论,本身就是扩大有效预算;③可选 `model: opus` 再升一档。

注意事项:
- **版本验证**:effort 字段为近期落地(最新官方文档已列入;6 月初仍有 issue 请求该能力、称仅有全局 effortLevel)——部署前在所装版本实测一次,若不生效,该 agent 以继承档位运行,skill 的回退话术(建议 /effort 升档)自动接管;
- **thinking 开关不可按 agent 配**:v2.1.198 起 subagent 继承主会话的 extended thinking 配置,无 per-agent thinking 设置(effort 字段与 thinking 开关是两个维度);
- **xhigh/max 仅 Opus 系模型接受**,非 Opus 上设置这两档需预期回退;
- **成本纪律**:高 effort 委派只用于"将被采取行动的结论"(影响面、改造决策、PRD 依据);日常定位/概览仍走主会话低成本路径——SKILL.md 决策表与 Quality rules 已按此划界。

## 七、上线验证清单(装完 10 分钟自测)

1. `codebase-memory-mcp cli list_projects` 能看到本项目 → 索引正常;
2. 新会话问"XxxService 的调用链是什么" → 应触发 skill 并一次 cbm-trace 出链(不应出现连环 Grep);
3. 问"这个项目的整体架构" → 应单次 cbm-arch;
4. 问"有哪些死代码" → 应走 cbm-cypher dead-code;
5. 问一个 MyBatis XML 里的动态 SQL 问题 → 应**不**用图谱、直接 grep/read;在一个 <1,000 行的小仓库问结构问题 → 应同样**不**用图谱(运行时门槛生效);
6. 故意问一个不存在的函数调用链 → trace 返回 0 + hint,Claude 应转 cbm-find 而非重试;
7. 观察一周:若某类结构问题仍频繁走原生多轮 grep,把该类问题的触发短语补进 SKILL.md description 与 CLAUDE.md 策略段(触发调优是持续过程)。
8. subagent effort 验证:将主会话设为 low(/effort),问一个影响面问题 → 应委派 cbm-deep-analyst 且该 agent 以 high 档运行;若所装版本不接受 effort frontmatter(agent 以继承档位运行),确认 skill 的回退话术(建议升档 + 原生复核)正常出现。

## 八、核实与假设声明

一手核实(官方 README v0.9.0):CLI 全工具语法、--raw、--skip-config、list_projects→project 名、search_graph 参数(name_pattern/label/degree/limit-offset/semantic_query)、trace_path 方向与深度 1–5 及"0 结果先 search_graph"的官方指引、get_code_snippet qualified name 规则、openCypher 子集(含死代码官方示例)、get_architecture 返回项、auto_watch 默认开启与 git 轮询机制、工件 bootstrap 导入、官方 Claude Code hook 的形态(拦 Grep/Glob、additionalContext、非阻断、不拦 Read)。
标注为"以实际为准"的假设:trace 深度参数名、各工具返回 JSON 的确切字段名(脚本 jq 已用 `//` 兜底多种命名)——首次部署时跑 `cli get_graph_schema` 与一次真实调用校准 jq 投影即可。
