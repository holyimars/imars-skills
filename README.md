# imars-skills

让 Claude Code 通过 **纯 CLI(零 MCP)** 使用预建代码知识图谱的 Skill 套件——一次图谱调用替代几十轮 grep/read。内含两套**独立、并行**的工具集成,各自覆盖一个不同的底层 CLI,可以只装一个,也可以两个都装:

| 集成 | 底层 CLI | 索引产物 |
|---|---|---|
| `cbm-navigator` | [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | `.codebase-memory/` |
| `codegraph-navigator` | [codegraph](https://github.com/colbymchenry/codegraph) | `.codegraph/` |

两者互不依赖、互不冲突,各自的 skill 只在自己对应的索引产物存在时才会工作(见下方各自的"前提")。两者的实测对比结论见文末"工具选型对比"一节。

内含六个组件:
| 组件 | 位置 | 作用 |
|---|---|---|
| `cbm-navigator` skill | `skills/cbm-navigator/` | codebase-memory-mcp 触发协议 + 8 个查询脚本 + 盲区参考 |
| `cbm-deep-analyst` subagent | `agents/` | 高风险问题(影响面/改造决策)以 `effort: high` 在独立上下文运行并回传已验证结论 |
| `codegraph-navigator` skill | `skills/codegraph-navigator/` | codegraph 触发协议 + 8 个查询脚本 + 盲区参考,含接口/实现自动桥接 |
| `codegraph-deep-analyst` subagent | `agents/` | 同上,基于 codegraph 索引 |
| PreToolUse hook(可选,两套各一份) | `optional/hooks/` | Grep/Glob 时自动注入图谱符号匹配作为 additionalContext,非阻断;`cbm-augment.sh`/`codegraph-augment.sh` 各自按对应索引产物(`.codebase-memory/`/`.codegraph/`)是否存在决定是否生效,可以同时接进 settings.json,只建了其中一种索引的仓库另一个 hook 会静默跳过 |
| CLAUDE.md 片段(可选) | `optional/` | 两套集成各一份,强化触发 |

## 安装(两种方式,选其一;两套 skill 一起装,装了哪个 CLI 就有哪个能用)

**方式 A:Claude Code plugin(推荐,自动获得更新)**
```
/plugin marketplace add holyimars/imars-skills
/plugin install imars-skills@imars-skills
```

**方式 B:脚本安装(拷贝到 ~/.claude/)**
```bash
git clone https://github.com/holyimars/imars-skills && cd imars-skills
./install.sh              # 或 ./install.sh --with-hook
```

两种方式都会把 `cbm-navigator` 和 `codegraph-navigator` 两个 skill 一起装上;具体某个 skill 能不能用,取决于对应的 CLI 有没有装、目标仓库有没有建对应的索引(见下面各自的"前提")——不需要也不应该两个 CLI 都装。

---

## cbm-navigator 前提(codebase-memory-mcp)

1. 已安装 codebase-memory-mcp 二进制(**务必 `--skip-config`,不写任何 MCP 配置**):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --skip-config
   ```
2. 目标仓库已建索引(**团队标准命令**,实机验证的 flags 形式):
   ```bash
   codebase-memory-mcp cli index_repository \
     --repo-path "$(git rev-parse --show-toplevel)" \
     --name "$(basename "$(git rev-parse --show-toplevel)")" \
     --persistence true
   ```
   三个 flag 的原因:`--name` 固定项目短名(默认名是绝对路径扁平化,因人而异,跨机器不可移植);`--persistence true` 才会写团队共享工件 `.codebase-memory/graph.db.zst`(**默认不写**);语义检索(`cbm-find.sh -s`)依赖 similarity/semantic 边,仅 `--mode full|moderate` 构建,若语义检索无结果用 `--mode full` 重建。**实测(2026-07-17):语义检索仅对英文关键词可靠,中文查询(不论整词还是拆词)得分都在 0.02-0.10 的近随机区间,不可用**——中文业务词查询请用 `cbm-grep.sh`(纯文本匹配,能命中中文 Javadoc 注释),不要用 `-s`;`cbm-find.sh` 现在会在语义搜索最高分低于 0.3 时自动给出这条提示。手动用 `--repo-path` 传相对路径重新索引时留意:曾实测出会静默建出一个同仓库的重复 project 而不是更新原有的,务必配合绝对路径 + 显式 `--name`,复核 `list_projects` 确认没有多出条目。
3. 本机有 `jq`。

可选增强:对 ≥1 万行的重点仓库,把 `optional/CLAUDE.md.snippet` 内容加入该仓库的 CLAUDE.md,强化触发。其中 `<PROJECT_NAME>` 填索引输出 JSON 的 `project` 字段值——**注意命名规则(实机验证):project 名是仓库绝对路径的扁平化**(去掉前导分隔符、分隔符换连字符),如 `/Users/me/www/my-service` → `Users-me-www-my-service`,不是目录名;可用 `codebase-memory-mcp cli list_projects` 查询。skill 脚本已内置该规则的自动解析(扁平化精确匹配 + basename 后缀兜底),无需手工配置。

### cbm-navigator 安装后 10 分钟自测

1. `codebase-memory-mcp cli list_projects` 能看到目标项目;
2. 问"XxxService 的调用链" → 触发 skill,单次 cbm-trace 出链,无连环 Grep;
3. 问"这个项目的整体架构" → 单次 cbm-arch;
4. 问"有哪些死代码" → cbm-cypher dead-code;
5. 问 MyBatis XML 动态 SQL 问题 → 不用图谱、直接 grep/read;在 <1,000 行小仓库问结构问题 → 同样不用图谱;
6. 问不存在的函数调用链 → trace 返回 0 + hint,Claude 转 cbm-find 而非重试;
7. 主会话设为 low(/effort)问影响面问题 → 应委派 cbm-deep-analyst;若所装 Claude Code 版本不支持 agent 的 `effort` frontmatter(以继承档位运行),确认回退话术出现。

---

## codegraph-navigator 前提(codegraph)

1. 已安装 codegraph(推荐 npm 方式;官方也提供 `install.sh`/`install.ps1` 独立二进制,见其 [README](https://github.com/colbymchenry/codegraph)):
   ```bash
   npm i -g @colbymchenry/codegraph
   codegraph telemetry off   # 可选,默认开启遥测
   ```
   **不要跑 `codegraph install`**——那条命令会往 Claude Code / Cursor / Codex 等写入 MCP server 配置,与本仓库"零 MCP、纯 CLI"的设计相悖。本 skill 全程只用 `codegraph` CLI 子命令。
   **实测(2026-07-18,Windows):不要在 Git Bash 里跑官方 `install.sh`**——读了源码确认它的 OS 判断只有 `Darwin`/`Linux` 两个分支,`uname -s` 在 Git Bash(MINGW64)下的实际输出会落进 `*) unsupported OS; exit 1` 直接退出,对应上游 open issue [#1294](https://github.com/colbymchenry/codegraph/issues/1294);上面的 npm 方式没有这个 OS 判断步骤,不受影响,Windows 上如果确实要用独立二进制,改用 PowerShell 跑 `install.ps1`。
2. 目标仓库已建索引:
   ```bash
   codegraph init "$(git rev-parse --show-toplevel)"
   ```
   索引产物是仓库根目录下的 `.codegraph/`(实测未被自动 gitignore,建议手动加进目标仓库的 `.gitignore`)。无需 `--name`——codegraph 按目录路径解析索引,没有 codebase-memory-mcp 那种全局项目名注册表。改动后跑 `codegraph sync .` 增量更新(秒级),或让其自带的文件监听自动同步。
3. 本机有 `jq`。

可选增强:把 `optional/CLAUDE.md.codegraph.snippet` 内容加入目标仓库的 CLAUDE.md,强化触发。

### codegraph-navigator 安装后 10 分钟自测

1. `codegraph status .` 能看到已索引、`nodeCount`/`fileCount` 非零;
2. 问"XxxService 的调用链" → 触发 skill,单次 cg-trace 出链;若查询目标是 `*Impl` 类方法,确认返回里出现 `bridged: true` 且包含真实业务调用方(而不只是接口声明本身);
3. 问"这个项目的整体架构" → 单次 cg-arch;
4. 问 MyBatis XML 动态 SQL 问题、或 Vue/React 路由懒加载组件是否被使用 → 不用图谱、直接 grep/read(两者都是 field-verified 盲区,见 `skills/codegraph-navigator/references/blindspots.md`);
5. 问不存在的符号调用链 → trace 返回空 + hint,Claude 转 cg-find 而非重试;
6. 主会话设为 low(/effort)问影响面问题 → 应委派 `codegraph-deep-analyst`。

## 内置运行时门槛(团队实测口径,写在各自 SKILL.md 内)

1. **小仓库不用**:当前仓库 <~1,000 行代码时,skill 指导 Claude 直接用原生 grep/read——全局安装 ≠ 全局使用;
2. **档位认知**:思考/输出 token 预算过小会限制检索质量,low/medium 档准确度低于 high/xhigh/max,图谱不能抬升该上限;**将被采取行动的结论**(影响面、改造决策)会被委派给对应的 deep-analyst subagent(effort 覆盖 + 独立上下文 + 源码复核),该 agent 不可用时回退为建议升档 + 原生复核。

## 维护指引

- **文档换行规范**:SKILL.md、references、agent 定义、CLAUDE.md 片段一律"一句一行"(句末标点处换行,句内不折行),PR diff 即句子粒度;
- **触发调优是持续过程**:观察一周,哪类结构问题仍走原生多轮 grep,就把该类触发短语提 PR 加进 `SKILL.md` 的 description(中英文都收);
- **盲区案例**:发现新的图谱盲区形态(解析不到/答错),提 issue 附最小复现,合并进 `references/blindspots.md`;
- **上游跟踪**:codebase-memory-mcp 周更级迭代;若某 release 更改工具参数名(如 trace 深度参数),按 `cli get_graph_schema` 校准脚本中的 jq 投影;
- **发版**:改动合并后 bump `.claude-plugin/plugin.json` 的 version 并更新 CHANGELOG,plugin 用户 `/plugin marketplace update` 获取。

## CLI 调用形式说明(cbm-navigator)

上游已弃用 raw JSON 位置参数(`cli <tool> '<json>'` 会打印 deprecation 警告,未来版本移除)。本套件所有 cbm-navigator 脚本统一通过 **stdin 管道**传 JSON,且收敛在 `scripts/_project.sh` 的 `cbm_call()` 单一包装函数中——若未来 CLI 调用形式再次变更(如 flags-only),只需修改该函数一处。codegraph-navigator 的脚本直接透传 flags(codegraph CLI 本身就是 flags-only,没有这层包装需求)。

## cbm-navigator 已知边界(上游)

- **官方 README 为 main 分支,可能超前于已发布版本**(实测:main 文档中的 `--raw` flag 在 v0.9.0 上不存在)。任何 CLI 用法以 `cli <tool> --help` 与实际输出为准,不以 main 文档为准;
- 查询结果的文件字段为 `file_path` 且**无行号字段**(v0.9.0 实测),脚本投影与 Cypher 模板已按此适配(coalesce 兼容);
- macOS 默认无 `timeout` 命令,hook 已内置 timeout/gtimeout 探测,均无时依赖 settings 层的 hook timeout 兜底;
- **Java:接口方法与实现类方法是图谱里的两个不同节点,调用边只挂在接口方法上(field-verified,非边缘情况)**。对 `*Impl` 类方法直接查 callers/impact/dead-code 会得到假的 0——包括单实现接口,不需要多实现+`@Primary`才触发。必须同时查接口方法,取并集,详见 `skills/cbm-navigator/references/blindspots.md`;
- 图谱 Route 节点的类级 `@RequestMapping` 前缀经实测(3 个真实 Controller)**完整保留,未复现前缀丢失**;上游 issue #734 描述的丢失问题仍 open(milestone 0.9.1-rc),不同项目/版本可能表现不同,不要默认套用;
- **前端:Vue/React 路由懒加载 `() => import('...')` 组件在图谱里没有引用边**(field-verified on plus-ui)——判断路由懒加载组件是否被使用,直接 grep router 配置,不要信图谱的"0 引用";
- `detect_changes` 在 git worktree 下失效(上游 bug),请在普通 clone 使用;
- `effort` 为 subagent frontmatter 较新字段,部署前按自测第 7 条验证;
- 引用 GitHub issue 编号前必须实际打开确认——曾核查过的 5 个二手引用编号里有 4 个对不上号(指向无关内容或不存在),只有 1 个精确匹配;
- **`cbm-cypher.sh` 的 5 个全图模板本身,2026-07-17 逐个实跑核实前从未验证过端到端准确性——结果 2 个是静默答错,已修复**:`hubs` 原查询按一个根本不存在的 `c.degree` 属性排序(`ORDER BY` 对全空列是空操作),排出来的"top 20 god class"里混进测试类和普通数据对象,零真实工具类;`cross-layer` 默认(零参数)调用会直接把 Cypher 解析器打崩(`unexpected operator`),不是原生 hint 而是硬报错。两个都已在脚本里修复(`hubs` 改为按方法级真实入度聚合,`cross-layer` 去掉 WHERE 子句里导致解析失败的 coalesce),修复后的 `hubs` 排出 `StringUtils`/`R`/`LoginHelper` 等真实高频工具类,`cross-layer` 稳定返回 4 条真实跨层调用。另外 `dead-code`(Function 标签模板,区别于 `dead-code-methods`)对 Java 接口方法**必然**误报——接口方法在图里被同时注册成 `Function` 和 `Method` 两个节点,只有 `Method` 节点会挂真实调用边,这是本次新发现、此前未记录的盲区,细节见 `skills/cbm-navigator/references/blindspots.md`。
- **同日的代码审查(而非新一轮字段实测)在刚修好的模板集里又挖出 3 个问题,已全部修复**:①所有固定 `LIMIT` 的模板此前从没检查过返回行数和 `LIMIT` 是否相等,导致真实结果比上限多时被静默截断且零提示——实测 `routes` 真实 303 条但 `LIMIT 200`(隐藏 34%)、`dead-code` 真实 348 个但 `LIMIT 100`(隐藏 71%)、`dead-code-methods` 真实 1159 个但 `LIMIT 100`(隐藏 91%),此前"routes 已验证准确"的结论只核对了单条记录格式、从未核对过总数;现在脚本会在返回行数等于上限时自动跑一次 `count(*)` 并在 stderr 报出真实总数和隐藏行数。②`cross-layer` 的 `layerA`/`layerB` 参数此前未经转义直接拼进 Cypher 字符串,含单引号的输入会让解析器崩溃(实测报错 `expected token type 85, got 86`),属于注入形态的健壮性缺陷,已改为剥离参数里的引号和反斜杠。③这个脚本依赖的 `_project.sh::cbm_call` 没有 JSON 校验兜底(不像 codegraph-navigator 的 `cg_call()`),Cypher 引擎级崩溃此前会把原始报错甩给调用方而非返回结构化 `{"error","hint"}`——已在 `cbm-cypher.sh` 内部本地补上这层校验,但共享的 `cbm_call` 本身未动,其余 6 个直接调用它的脚本仍缺这层保护,留作后续。

## codegraph-navigator 已知边界(上游)

完整证据见 `skills/codegraph-navigator/references/blindspots.md`。要点:

- Java 接口/实现盲区**明显好于** cbm-navigator:`node`/`explore` 会给出 `[dynamic: interface → impl]` 双向标注,`cg-trace.sh` 已内置自动桥接;但底层 `callers` 命令本身仍是单跳,查 `*Impl` 类方法只会返回 1 个"caller"——那其实是接口声明本身,不是真实调用方,必须靠 `cg-trace.sh`/`cg-node.sh`/`cg-explore.sh` 而非裸 CLI 调用;
- **CALLS 边是接收者类型感知的,不会有 cbm-navigator 那种 Lombok getter/setter 同名碰撞问题(实测 2026-07-18)**:用同一个"getDictLabel"名字(业务接口方法 + 4 个不相关 DTO/VO/Entity 的 Lombok getter)测试,codegraph 完全正确区分,零污染——这是相对 cbm(name-only 解析,实测 60% 假阳性)的明确优势;
- Vue/React 动态 `() => import('...')` 路由懒加载、MyBatis XML mapper 绑定:**跟 codebase-memory-mcp 一样是盲区**,graph 完全无感知,直接 grep/read;
- Spring `getBean(运行时拼接名)` 场景:codegraph 会把接口的全部实现类都列成 dynamic dispatch 候选——诚实但不精确(不代表"全部被调用"或"就是这一个"),仍需 grep bean 名拼接逻辑;
- **⚠️ 实测新发现(2026-07-18):`SpringUtils.getBean(X.class)` 这种确定性单目标的 Bean 查找,比上面的运行时拼接名场景更差——完全解析不到,`callers`/`node`/`impact` 三个命令 0/2 召回**,且这个盲区会直接传导进 `cg-impact.sh` 的影响面分析,导致"改这个方法安全吗"这类问题被漏报;查任何接口方法的调用方/影响面前,建议顺手 grep 一下 `SpringUtils.getBean(<接口>.class)` 作为兜底核实;
- **⚠️ 实测新发现(2026-07-18):类的 `extends` 关系单向,查父类能看到子类列表(标签是 `Called by`,略有误导),反过来查子类完全看不到父类是谁**,JSON schema 里没有 `extends`/`superclass` 字段,精确复现上游 open issue [#1328](https://github.com/colbymchenry/codegraph/issues/1328)——要查一个类继承自谁,直接 grep `class X extends Y` 声明行;
- **⚠️ 实测新发现(2026-07-18):`cg-explore.sh`(官方文档最推荐的旗舰单一命令,也是唯一默认开启的 MCP 工具)纯中文查询完全失效**,测试了"字典标签""字典标签查询""用户登录""部门管理"四个不同中文业务词全部返回空,但用完全相同的词跑底层 `cg-find.sh`(FTS 全文检索)却精确命中——纯中文业务问题请直接用 `cg-find.sh`,不要指望 `cg-explore.sh`;
- 没有裸图查询能力(无 Cypher 等价物),死代码/hubs 这类全图模式问题**明确不要用 `cg-explore.sh` 兜底**——实测(2026-07-17)它对这类问题做的是关键词/语义检索而非图分析,会把问题里的词(如"find"/"list")匹配到同名符号上,再套用跟正常答案一模一样的"Blast radius"格式自信地给出**看似合理实则文不对题**的结果,不是"答不出来"而是"答错了还不报错";这两类问题改用 cbm-navigator;
- "列出所有 routes/classes/interfaces/components" 这类**穷举**(而非模糊搜索)反而有直接等价物:`cg-find.sh -k route\|class\|interface\|component`(pattern 留空)——实测数量与 `codegraph status` 的 `nodesByKind` 完全一致(303/303 routes、482/482 classes、99/99 components),比 cbm-cypher.sh 的 routes 模板还多带 HTTP 方法;
- **实测新发现(2026-07-18,Windows):`codegraph index` 全量重建时若有任何其他 codegraph 进程(哪怕只是一次只读 `query`)并发持有数据库文件,会直接硬失败退出**(`EPERM: database file is in use`,不会自动重试,但确认不会损坏现有索引),范围比上游 issue #1325 描述的"MCP server 运行时冲突"更广;日常增量更新用的 `codegraph sync` 未复现此问题,`index --force` 应单独跑,不要和其他 codegraph 调用并发;
- `codegraph install` 会写 MCP 配置,本套件明确不使用它。

## 工具选型对比(实测,2026-07-16/17,codegraph v1.4.1 vs codebase-memory-mcp v0.9.0)

在 RuoYi-Vue-Plus + plus-ui 两个真实仓库上做的头对头验证,同一批符号、同一批盲区场景。**两个 skill 的 SKILL.md 现在都按同一优先级选工具:准确度 > tokens 消耗 > 返回速度**——先看谁的结果对,分数相同再看谁调用次数/token 少,最后才比谁快;从不单纯因为"习惯用哪个"而选。

| 场景 | codebase-memory-mcp | codegraph |
|---|---|---|
| Java 接口→实现类调用 | 静默返回 0 callers,查询层因 Cypher 引擎限制无法修复,只能靠 SKILL.md 里的 MANDATORY 交叉查协议(必须 2 次调用取并集)兜底 | 图里有 interface→impl 链接,`node`/`explore` **一次调用**给出双向证据 + `[dynamic: ...]` 标注,`cg-trace.sh` 已实现自动桥接;准确度上限跟 cbm 一样(底层裸 `callers` 命令仍会把接口声明误当成"1 个 caller"),但达到同等准确度所需的调用次数更少、token 更省 |
| Vue Router `() => import()` 懒加载 | 完全无边 | 完全一样,同样无边——两个工具在这一点上共同的局限,不是某一方的短板,换工具解决不了,只能 grep router 配置 |
| Spring `getBean(运行时拼接名)` | 完全无法解析 | 用接口/实现启发式把全部候选实现列为 dynamic dispatch——不精确但诚实可用 |
| MyBatis XML mapper 绑定 | 完全无法解析 | 完全一样,XML 建了文件节点但 0 symbols,零绑定——同上,两个工具共同的局限 |
| 死代码/hubs/跨层违规全图模式查询 | 有专门的 Cypher 模板(`cbm-cypher.sh`);2026-07-17 逐个实跑核实后,`hubs`/`cross-layer` 2 个模板发现是静默答错(已修复,见上方"已知边界"),`dead-code`(Function 标签)对 Java 接口方法必然误报(新发现,用 `dead-code-methods`+交叉查协议代替) | **无等价物,且 `cg-explore.sh` 会文不对题地"答出来"**——关键词匹配到同名符号后套用正常回答的格式,不报错也不提示这是错的,比"查不到"更危险;实测过三种问法(死代码/hubs/routes)全部踩坑 |
| routes 全量列表 | 有专门的 Cypher 模板(`cbm-cypher.sh routes`),单条记录准确,但曾在这个仓库的规模上静默截断(`LIMIT 200` vs 真实 303 条,隐藏 34%,同日代码审查发现并修复,现会主动报出真实总数),只含 path 不含 HTTP 方法 | 实测有直接等价物:`cg-find.sh -k route`(pattern 留空)穷举,数量与 `codegraph status` 精确对上,`name` 字段还带 HTTP 方法,在这个仓库规模下无截断问题,且是单次 CLI 调用而非 Cypher 往返——两个工具都存在时优先这个 |
| 改动关联的测试文件 | 无此能力 | `codegraph affected` 原生支持,返回值含 `totalDependentsTraversed` 可作为"确实没有覆盖测试"结论的可信度信号 |
| 索引速度(RuoYi-Vue-Plus,709 文件) | 未记录精确耗时 | 2.4 秒,16497 节点/28199 边 |
| Lombok getter/setter 同名碰撞(实测 2026-07-18) | 实测 60% 假阳性:`DictService.getDictLabel` 的 callers 里 6/10 其实是不相关 Vo 类的 Lombok getter,name-only 边解析 | 用同一批同名符号测试,零污染——边按接收者类型限定,不是纯按方法名 |
| 中文业务语言查询(实测 2026-07-18) | 语义搜索(`-s`)完全不支持中文,得分近随机;纯文本 `cbm-grep.sh` 可用 | 底层 `cg-find.sh`(FTS)对中文表现好,但旗舰命令 `cg-explore.sh` 纯中文查询直接返回空——同一工具内部两个命令表现不一致,要分场景选 |
| 反射式 DI(`SpringUtils.getBean(X.class)` 单目标)(实测 2026-07-18) | 未针对性测试(cbm 的局限是 name-only 解析导致的碰撞,不是这类 DI 场景) | 完全解析不到,0/2 召回,且会传导进 `impact` 分析导致漏报 |
| 类继承关系(`extends`)查询(实测 2026-07-18) | 未针对性测试 | 单向缺口:查父类能看到子类,查子类看不到父类,复现上游 open issue #1328 |

结论:两个工具没有绝对的谁更好,互补大于替代,且**两者共享的局限(Vue 动态 import、MyBatis XML、Spring 运行时 bean 名)换工具换不掉,只能 grep**——单符号溯源(调用链/影响面)、routes 全量列表优先 codegraph(同等准确度下更省 token、更快);死代码/hubs/跨层违规全图模式扫描优先 codebase-memory-mcp 修复后的 `cbm-cypher.sh`,且这两类问题**不要**用 `cg-explore.sh` 兜底(实测会答错而非答不出来,三种问法全部验证过)。

## License

MIT
