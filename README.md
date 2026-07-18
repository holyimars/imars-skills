# imars-skills

让 Claude Code 通过 **纯 CLI(零 MCP)** 使用预建代码知识图谱的 Skill 套件——一次图谱调用替代几十轮 grep/read。

一套统一 skill `code-navigator`,内部可对接两种互不依赖的底层 CLI,按问题形状自动选用其中最合适的一个(或两个都用):

| 底层 CLI | 索引产物 |
|---|---|
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | `.codebase-memory/` |
| [codegraph](https://github.com/colbymchenry/codegraph) | `.codegraph/` |

推荐两个都装:`code-navigator` 会按 SKILL.md 里的决策表自动选择准确度最高、成本最低的那一个;只装一个也完整可用,对应能力会降级到只用那一个工具能做到的程度(见文末"工具选型对比")。0.0.18 之前这里是 `cbm-navigator`/`codegraph-navigator` 两个完全并行的 skill,各自的 CLAUDE.md 片段常驻层会同时写"invoke 我 FIRST"、互相矛盾——已合并为一个统一入口,详见 CHANGELOG 0.0.18。

内含五个组件:
| 组件 | 位置 | 作用 |
|---|---|---|
| `code-navigator` skill | `skills/code-navigator/` | 统一触发协议 + 16 个查询脚本(`cbm-*.sh` 8 个 + `cg-*.sh` 8 个)+ 两份盲区参考 + LSP 协作协议 |
| `deep-analyst` subagent | `agents/` | 高风险问题(影响面/改造决策)以 `effort: high` 在独立上下文运行并回传已验证结论 |
| PreToolUse hook(可选,两个脚本) | `optional/hooks/` | Grep/Glob 时自动注入图谱符号匹配作为 additionalContext,非阻断;`cbm-augment.sh`/`codegraph-augment.sh` 各自按对应索引产物(`.codebase-memory/`/`.codegraph/`)是否存在决定是否生效,可以同时接进 settings.json,只建了其中一种索引的仓库另一个 hook 会静默跳过——两个都建了索引的仓库,每次 Grep/Glob 会收到最多两段提示,详见下方"PreToolUse hook 的双索引代价" |
| CLAUDE.md 片段(可选) | `optional/` | 一份统一片段,强化触发,同时兼容只建了一种索引的仓库 |
| settings 模板 | `optional/` | hook 接线,project/user 两个作用域各一份 |

## 安装(两种方式,选其一)

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

两种方式都会装上统一的 `code-navigator` skill 和 `deep-analyst` agent;具体哪半能力能用,取决于对应的 CLI 有没有装、目标仓库有没有建对应的索引(见下面各自的"前提")——不需要也不应该只为了"用全部能力"而在没有对应仓库场景的机器上强装两个 CLI。

---

## codebase-memory-mcp 前提(code-navigator 的 cbm 侧)

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
   三个 flag 的原因:`--name` 固定项目短名(默认名是绝对路径扁平化,因人而异,跨机器不可移植);`--persistence true` 才会写团队共享工件 `.codebase-memory/graph.db.zst`(**默认不写**);语义检索(`cbm-find.sh -s`)依赖 similarity/semantic 边,仅 `--mode full|moderate` 构建,若语义检索无结果用 `--mode full` 重建。**实测(2026-07-17):语义检索仅对英文关键词可靠,中文查询(不论整词还是拆词)得分都在 0.02-0.10 的近随机区间,不可用**——中文业务词查询请用 `cbm-grep.sh`(纯文本匹配,能命中中文 Javadoc 注释),不要用 `-s`;`cbm-find.sh` 现在会在语义搜索最高分低于 0.3 时自动给出这条提示。手动用 `--repo-path` 传相对路径重新索引时留意:曾实测出会静默建出一个同仓库的重复 project 而不是更新原有的,务必配合绝对路径 + 显式 `--name`,复核 `list_projects` 确认没有多出条目。**实测(2026-07-18):在一个 1,289 文件的中大型混合语言(PHP+TS)仓库上跑 `index_repository`,内存占用一路涨到把机器 64GB 内存打满前不得不强杀进程**——这不是这次环境的偶发问题,是 `codebase-memory-mcp` 一个持续被跟踪、跨 Windows/macOS/Linux 都有真实报告的已知问题类(issue #581/#593/#832/#775/#1084/#580/#765/#317/#363/#1070,目前官方还没有 `--max-memory` 这类限流开关),给大仓库首次建索引前建议开着任务管理器/`Activity Monitor`盯一下,不放心就先在小一点的仓库上验证。详见 `skills/code-navigator/references/cbm-blindspots.md` 的"`index_repository` memory usage"小节。
3. 本机有 `jq`。

## codegraph 前提(code-navigator 的 cg 侧)

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

## code-navigator 安装后 10 分钟自测

1. `codebase-memory-mcp cli list_projects` 能看到目标项目(若装了 cbm 侧);`codegraph status .` 能看到已索引、`nodeCount`/`fileCount` 非零(若装了 cg 侧);
2. 问"XxxService 的调用链" → 触发 `code-navigator`,单次出链,无连环 Grep;两个索引都建了时应优先走 codegraph(`cg-trace.sh`),若查询目标是 `*Impl` 类方法,确认返回里出现 `bridged: true` 且包含真实业务调用方(而不只是接口声明本身);
3. 问"这个项目的整体架构" → 单次 arch 调用;
4. 问"有哪些死代码" → 只有装了 codebase-memory-mcp 才会给出答案(`cbm-cypher.sh dead-code`);只装了 codegraph 的仓库上,skill 应如实说明这类问题它没有能力回答,不会用 `cg-explore.sh` 冒充答案;
5. 问 MyBatis XML 动态 SQL 问题、或 Vue/React 路由懒加载组件是否被使用 → 不用图谱、直接 grep/read(两个工具的共同 field-verified 盲区,见 `skills/code-navigator/references/lsp-and-native-fallbacks.md`);在 <1,000 行小仓库问结构问题 → 同样不用图谱;
6. 问不存在的函数调用链 → trace 返回空/0 + hint,Claude 转 find 而非重试;
7. 主会话设为 low(`/effort`)问影响面问题 → 应委派 `deep-analyst`;若所装 Claude Code 版本不支持 agent 的 `effort` frontmatter(以继承档位运行),确认回退话术出现;
8. (可选,仅当环境里确实配置了 Java/TypeScript 语言服务器时才有意义)问单符号调用链时,确认 skill 只把 LSP 结果当"额外佐证"引用,不作为链头——本仓库实测环境未装任何语言服务器,这一条大概率会静默跳过。

## 内置运行时门槛(团队实测口径,写在 SKILL.md 内)

1. **小仓库不用**:当前仓库 <~1,000 行代码时,skill 指导 Claude 直接用原生 grep/read——全局安装 ≠全局使用;
2. **档位认知**:思考/输出 token 预算过小会限制检索质量,low/medium 档准确度低于 high/xhigh/max,图谱不能抬升该上限;**将被采取行动的结论**(影响面、改造决策)会被委派给 `deep-analyst` subagent(effort 覆盖 + 独立上下文 + 源码复核),该 agent 不可用时回退为建议升档 + 原生复核;
3. **只有实测过的能力才能当决策表的链头**:LSP 目前在本团队环境里未经实测(见下方"LSP 协作"),因此永远只作为单符号问题的额外佐证,不参与链序判断。

## PreToolUse hook 的双索引代价

两个 hook 脚本(`cbm-augment.sh`/`codegraph-augment.sh`)保持独立进程、不合并逻辑——hook 之间互相看不到对方的输出,任何跨 hook 去重都需要引入共享状态,对一个非阻断、best-effort、单次 ≤5 条的提示注入是过度工程;而且两者的匹配机制不同(cbm 是 `search_graph` 的 name_pattern 精确/正则匹配,codegraph 是内置 FTS 模糊匹配),召回互补,强行去重反而会丢信息。

代价如实说明:双索引仓库上,每次 Grep/Glob 都会收到最多两段(各 ≤5 条)符号提示注入进 additionalContext,现在两段的结尾建议已经统一指向同一个 `code-navigator` skill,冗余只剩符号列表本身的重复,不再是矛盾指令。对 token 消耗敏感、又两个索引都建了的用户,可以只在 settings.json 里接 `codegraph-augment.sh` 一个——双索引场景下它的匹配结果带 `kind` 字段且没有 cbm 那种 name-only 碰撞噪声。

## 维护指引

- **文档换行规范**:SKILL.md、references、agent 定义、CLAUDE.md 片段一律"一句一行"(句末标点处换行,句内不折行),PR diff 即句子粒度;
- **触发调优是持续过程**:观察一周,哪类结构问题仍走原生多轮 grep,就把该类触发短语提 PR 加进 `SKILL.md` 的 description(中英文都收);
- **盲区案例**:发现新的图谱盲区形态(解析不到/答错),提 issue 附最小复现,合并进对应工具的 `references/*-blindspots.md`,两工具共同的盲区合并进 `references/lsp-and-native-fallbacks.md`;
- **上游跟踪**:codebase-memory-mcp、codegraph 均按各自节奏迭代;若某 release 更改工具参数名(如 trace 深度参数),按各自的 schema/help 输出校准脚本中的 jq 投影;
- **发版**:改动合并后 bump `.claude-plugin/plugin.json` 的 version 并更新 CHANGELOG,plugin 用户 `/plugin marketplace update` 获取。

## CLI 调用形式说明(cbm 侧脚本)

上游已弃用 raw JSON 位置参数(`cli <tool> '<json>'` 会打印 deprecation 警告,未来版本移除)。`code-navigator` 的所有 `cbm-*.sh` 脚本统一通过 **stdin 管道**传 JSON,且收敛在 `scripts/_project.sh` 的 `cbm_call()` 单一包装函数中——若未来 CLI 调用形式再次变更(如 flags-only),只需修改该函数一处。`cg-*.sh` 脚本直接透传 flags(codegraph CLI 本身就是 flags-only,没有这层包装需求)。

## 已知边界:codebase-memory-mcp 一侧(上游)

- **官方 README 为 main 分支,可能超前于已发布版本**(实测:main 文档中的 `--raw` flag 在 v0.9.0 上不存在)。任何 CLI 用法以 `cli <tool> --help` 与实际输出为准,不以 main 文档为准;
- 查询结果的文件字段为 `file_path` 且**无行号字段**(v0.9.0 实测),脚本投影与 Cypher 模板已按此适配(coalesce 兼容);
- macOS 默认无 `timeout` 命令,hook 已内置 timeout/gtimeout 探测,均无时依赖 settings 层的 hook timeout 兜底;
- **Java:接口方法与实现类方法是图谱里的两个不同节点,调用边只挂在接口方法上(field-verified,非边缘情况)**。对 `*Impl` 类方法直接查 callers/impact/dead-code 会得到假的 0——包括单实现接口,不需要多实现+`@Primary`才触发。必须同时查接口方法,取并集,详见 `skills/code-navigator/references/cbm-blindspots.md`;
- **前端:Vue/React 路由懒加载 `() => import('...')` 组件在图谱里没有引用边**(field-verified on plus-ui,codegraph 一侧同样如此)——判断路由懒加载组件是否被使用,直接 grep router 配置,不要信图谱的"0 引用";两工具共同盲区的完整清单见 `skills/code-navigator/references/lsp-and-native-fallbacks.md`;
- **前端:挂在 `app.config.globalProperties` 上的函数(如 `app.config.globalProperties.parseTime = parseTime`,调用处写作 `proxy.parseTime(...)`)是同一类共同盲区**(field-verified 2026-07-18,plus-ui 三个真实函数 `parseTime`/`handleTree`/`addDateRange` 各自独立测试,两个图谱工具都只能召回 10-19 个真实调用点里的 0-1 个)——查这类函数的调用链前先 grep `src/plugins/index.ts`(或等价注册文件)确认是否走了这条路径,是的话直接 `grep -rn "proxy\.<name>\|\.<name>("`,单次调用 100ms 内拿到全部真实调用点;详见 `skills/code-navigator/references/tool-collaboration-benchmark.md`;
- 图谱 Route 节点的类级 `@RequestMapping` 前缀经实测(3 个真实 Controller)**完整保留,未复现前缀丢失**;上游 issue #734 描述的丢失问题仍 open(milestone 0.9.1-rc),不同项目/版本可能表现不同,不要默认套用;
- `detect_changes` 在 git worktree 下失效(上游 bug),请在普通 clone 使用;
- `effort` 为 subagent frontmatter 较新字段,部署前按自测第 7 条验证;
- 引用 GitHub issue 编号前必须实际打开确认——曾核查过的 5 个二手引用编号里有 4 个对不上号(指向无关内容或不存在),只有 1 个精确匹配;
- **`cbm-cypher.sh` 的 5 个全图模板本身,2026-07-17 逐个实跑核实前从未验证过端到端准确性——结果 2 个是静默答错,已修复**:`hubs` 原查询按一个根本不存在的 `c.degree` 属性排序(`ORDER BY` 对全空列是空操作),排出来的"top 20 god class"里混进测试类和普通数据对象,零真实工具类;`cross-layer` 默认(零参数)调用会直接把 Cypher 解析器打崩(`unexpected operator`),不是原生 hint 而是硬报错。两个都已在脚本里修复(`hubs` 改为按方法级真实入度聚合,`cross-layer` 去掉 WHERE 子句里导致解析失败的 coalesce),修复后的 `hubs` 排出 `StringUtils`/`R`/`LoginHelper` 等真实高频工具类,`cross-layer` 稳定返回 4 条真实跨层调用。另外 `dead-code`(Function 标签模板,区别于 `dead-code-methods`)对 Java 接口方法**必然**误报——接口方法在图里被同时注册成 `Function` 和 `Method` 两个节点,只有 `Method` 节点会挂真实调用边,详见 `skills/code-navigator/references/cbm-blindspots.md`。
- **同日的代码审查(而非新一轮字段实测)在刚修好的模板集里又挖出 3 个问题,已全部修复**:①所有固定 `LIMIT` 的模板此前从没检查过返回行数和 `LIMIT` 是否相等,导致真实结果比上限多时被静默截断且零提示——实测 `routes` 真实 303 条但 `LIMIT 200`(隐藏 34%)、`dead-code` 真实 348 个但 `LIMIT 100`(隐藏 71%)、`dead-code-methods` 真实 1159 个但 `LIMIT 100`(隐藏 91%);现在脚本会在返回行数等于上限时自动跑一次 `count(*)` 并在 stderr 报出真实总数和隐藏行数。②`cross-layer` 的 `layerA`/`layerB` 参数此前未经转义直接拼进 Cypher 字符串,含单引号的输入会让解析器崩溃,属于注入形态的健壮性缺陷,已改为剥离参数里的引号和反斜杠。③这个脚本依赖的 `_project.sh::cbm_call` 没有 JSON 校验兜底(不像 cg 侧的 `cg_call()`),Cypher 引擎级崩溃此前会把原始报错甩给调用方而非返回结构化 `{"error","hint"}`——已在 `cbm-cypher.sh` 内部本地补上这层校验;当时共享的 `cbm_call` 本身未动,其余 6 个直接调用它的脚本仍缺这层保护,标记为后续项——**2026-07-20 已修复**,详见下方"cbm-\*.sh 脚本自身缺陷"一条。
- **`dead-code-methods` 还有一个和 codegraph 共同踩坑的假阴性(field-verified 2026-07-18)**:`SysDictTypeServiceImpl.selectDictTypeByType`(`@Cacheable` 方法)被标记为死代码,实际是通过 `SpringUtils.getAopProxy(this).selectDictTypeByType(...)` 自调用触发缓存注解生效——`cg-trace.sh`/`cg-node.sh` 独立测试同样漏判,两个工具"都同意"这个方法是死代码恰恰是因为它们共享同一个盲区,不构成互相印证。对任何带 `@Cacheable`/`@CachePut`/`@CacheEvict` 的方法,在下死代码结论前顺手 grep 一下 `SpringUtils.getAopProxy(this).<method>(`,详见 `skills/code-navigator/references/codegraph-blindspots.md` 的专门小节;
- **跨仓库一致性问题(如"这个前端 API 调用有没有对应的后端路由")两个工具都没有能力**,各自的索引严格限定在自己 cwd 所在的 git 仓库——field-verified 3/3:从 `plus-ui` 的 API 请求 URL 里截取路径片段,直接 grep 到 `RuoYi-Vue-Plus` 的 Controller 里,并用 `cg-find.sh -k route` 独立交叉核实,详见 `skills/code-navigator/references/cbm-blindspots.md` 的 "Cross-repository analysis" 小节。
- **Laravel/PHP 这一侧至今仍未拿到真实字段数据**:2026-07-18 尝试用 `pterodactyl/panel`(Laravel+React 真实应用)补齐这块证据,但 `index_repository` 索引到一半就把机器内存打到接近打满(见上方安装步骤里的内存警告),只能强杀进程放弃——codegraph 一侧倒是拿到了真实数据(Facade 高召回、Eloquent scope 完全盲区、构造函数注入接口可靠解析,见下一节),但 cbm 这一侧的 Laravel 结论目前仍是未实测的推测,不能当作和 codegraph 同等可信度的结论对待。2026-07-19 又用第二个 Laravel 仓库(`hi.events`)给 codegraph 补数据时,cbm 这一侧同样出于对上次内存事故的谨慎主动跳过,不是重试失败,结论没有变化。
- **`cbm-*.sh` 脚本自身缺陷,靠逐个对照上游 `--help` 输出系统性核查出来,而非新一轮字段实测(field-verified 2026-07-20 on RuoYi-Vue-Plus)**——`cg-trace.sh` 那个截断 bug提示了一个问题:既然一个脚本能悄悄背离自己 CLI 的文档行为,其他脚本呢?这轮就是把每个 `cbm-*.sh` 的假设和 `codebase-memory-mcp cli <tool> --help` 的真实输出逐条对表,查出 4 个真实 bug,全部已修复:
  1. `cbm-find.sh` 硬编码 `limit:20`(官方文档默认值是 200),且输出格式化时把官方专门用来探测截断的 `total`/`has_more` 字段整个丢弃——实测 `-l Route '.*'` 返回恰好 20 条,真实值是 303 条,零提示,和 `cg-trace.sh` 的截断 bug 是同一种失败形态,只是长在另一个工具上。已修复:默认上限提到 200,新增 `-n` 覆盖,`total`/`hasMore` 现在会带进 `hint`。
  2. `cbm-trace.sh` 自己的"0 结果"提示逻辑核对的字段名(`.paths`/`.results`)在 `trace_path` 真实返回值里根本不存在(真实字段是 `.callers`/`.callees`)——导致**每一次调用**都会报"0 paths",哪怕真实返回了 83 个调用者也一样,100% 复现率,不是截断才触发的边缘情况。已修复为核对真实字段;同时发现 `include_tests` 默认是 `false`(测试文件里的调用者会被排除,这是官方文档明确的默认行为,不是 bug),脚本原来从没暴露过这个开关——如果拿它和一个把测试文件也算进去的 grep ground truth 比召回率,会显得像工具的锅,其实是这个默认值造成的口径不一致;已加上第 4 个位置参数可以传 `true` 打开,且默认关闭时会在 hint 里主动提醒。
  3. 共享的 `_project.sh::cbm_call()` 对"报错信息走 stderr、退出码非零"这种失败模式完全没有安全网——实测 `trace_path` 查一个不存在的函数名时退出码是 1、stdout 完全为空、真正有用的 `{"error","hint"}` 其实好好地写在 stderr 里,但 `cbm_call()` 只抓 stdout,在调用脚本的 `set -e` 之下整个脚本会在这一行直接静默退出,CLI 自己给出的报错和提示全被扔掉,调用方什么都看不到。这正是上一条(2026-07-17 的 `cbm-cypher.sh` 代码审查)当时标记但没做的后续项,这轮补上了实测复现再修复:现在 `cbm_call()` 学 cg 侧的 `cg_call()` 用临时文件 + `jq empty` 校验,stdout 不是有效 JSON 时会尝试从 stderr 最后一行捞出 CLI 自己给的错误对象,捞不到才退化成通用包装。顺带发现 `jq empty` 对纯空字符串会返回成功(退出码 0)——这意味着"退出码非零+stdout 全空"这种失败原本会被误判成"空但合法"的成功,`cg_call()`(cg 侧)有同样的潜在漏洞,这轮一并加上非空检查,虽然没有在 codegraph 一侧实测复现出来(codegraph 目前已知的"未找到"失败模式都是 stdout 非空+退出码 0)。
  4. `cbm-impact.sh`/`cbm-arch.sh` 都引用了真实 API 里根本不存在的字段(`summary`/`risk`、`entry_points`)——恒为 `null`,和"这个仓库确实没有这类数据"完全无法区分。已修复为只报真实存在的字段;`cbm-arch.sh` 顺带补上了之前从没暴露过的 `layers`/`boundaries`(真实存在、和"架构总览"问题直接相关的字段),并且实测确认它的 `routes`/`hotspots`/`clusters` 都只是总览切片而非穷举(`routes` 这个仓库上实测 20/303),现在会在 hint 里主动说明。
  这一轮和上面 `cg-trace.sh` 的订正不一样:检查过现有文档里每一条调用次数结论,全部是直接读 `.callers`/`.results` 原始数组得到的,没有一条依赖过坏掉的 hint 字段——所以这轮不需要撤回任何已发布的具体数字,价值是让这些脚本从现在起说真话,而不是订正过去说错的话。完整实测复现见 `skills/code-navigator/references/cbm-blindspots.md` 新增小节。
- **上面这 4 处修复本身又被下游架空了——`cbm_call()` 新加的错误契约,调用它的每一个脚本都没有真正兑现,靠 `/code-review-expert` 加一轮后续 `/code-review` 揪出来,已全部修复**:①`cbm-find.sh` 遇到 `cbm_call()` 的错误对象直接崩溃——两个分支都无条件重建输出并迭代 `.results[]`/`.semantic_results[]`,不带 `// []` 兜底,错误对象缺这两个字段时 `jq` 报 `Cannot iterate over null`,在 `set -euo pipefail` 下整个脚本静默退出、零输出。②`cbm-impact.sh`/`cbm-arch.sh` 把 `.error` 静默吞掉——两者都无条件重建了一个新对象,`.error` 被丢弃,换成一个看起来"合理"的空结果/总览,和"这个仓库确实没有变更/是个小仓库"完全无法区分。③`cbm-trace.sh` 保留了 `.error`,但 `.hint` 不管真实原因是什么都会被一条通用的"名字必须精确"提示覆盖掉。④`cg-trace.sh` 的 `possiblyTruncated`/`bridged` 和 `cbm-find.sh` 的低分/`has_more` 提示,用 `elif` 链只能报出两个同时成立的告警里的一个(原始布尔字段本身一直是对的,只是自动生成的提示文案会漏掉一条)。全部已修复,并且逐条用模拟错误对象复现问题、验证修复,再对已建索引的 `RuoYi-Vue-Plus`/`plus-ui` 跑一遍所有改动脚本的正常路径回归确认无副作用。后续那轮 `/code-review` 还发现 `_is_valid_json_answer()`/`_require_positive_int()`(`scripts/_json_safe.sh`)并没有真正接到 `cbm_call()` 内部,以及 `elif` 改数组拼接这个 hint 写法在 `cg-trace.sh`/`cbm-find.sh` 里各手写了一份而不是共享——现已分别接入、并抽成 `scripts/_hint.jq` 的 `join_warnings()`。实际影响:本节开头"看到 hint 就照着办"这条准则,在这轮之前对 find/trace/impact/arch 这几个改完动最容易被立刻调用的脚本其实并不可靠,现在才算真正兑现。

## 已知边界:codegraph 一侧(上游)

完整证据见 `skills/code-navigator/references/codegraph-blindspots.md`。要点:

- Java 接口/实现盲区**明显好于** cbm 侧:`node`/`explore` 会给出 `[dynamic: interface → impl]` 双向标注,`cg-trace.sh` 已内置自动桥接;但底层 `callers` 命令本身仍是单跳,查 `*Impl` 类方法只会返回 1 个"caller"——那其实是接口声明本身,不是真实调用方,必须靠 `cg-trace.sh`/`cg-node.sh`/`cg-explore.sh` 而非裸 CLI 调用;
- **CALLS 边是接收者类型感知的,不会有 cbm 侧那种 Lombok getter/setter 同名碰撞问题(实测 2026-07-18,Java;2026-07-18 追加实测 PHP 上同样成立)**:用同一个"getDictLabel"名字(业务接口方法 + 4 个不相关 DTO/VO/Entity 的 Lombok getter)测试,codegraph 完全正确区分,零污染——这是相对 cbm(name-only 解析,实测 60% 假阳性)的明确优势;PHP 上用 `pterodactyl/panel` 的 `UserCreationService::handle()` 复测(仓库里有十几个不相关的 `*CreationService` 类都调用同名 `handle()`,共 19 处文本相同的调用形状,真实属于 `UserCreationService` 的只有 4 处)同样零假阳性,说明这个"按接收者类型而非纯方法名"的保证不是 Java 专属;**但这个"接收者类型限定"的保证只覆盖方法级 CALLS 边,不适用于 `cg-node.sh` 的文件级"used by N files"依赖聚合**(field-verified 2026-07-18):`RoleSelect/index.vue` 被报"used by 29 files",人工 grep 找到的真实引用是 0——假 29 来自其他不相关 CRUD 页面共用的通用标识符(`handleQuery`/`queryParams`)恰好被这个文件级启发式关联到了 `RoleSelect`。文件级"used by N files"计数不管数字大小都不能直接当结论,查 kebab-case 模板标签 + 检查 auto-import 注册入口才是可靠判断;
- **`cg-trace.sh` 曾经默默把 `callers`/`callees` 截断在 20 条,没有任何提示,已修复(field-verified 2026-07-19)**:底层 `codegraph callers`/`callees` 命令本身默认 `-l 20`,JSON 返回体里也没有 total/hasMore 字段——超过 20 条真实调用者时,结果和"正好 20 条"完全无法区分。`cg-trace.sh` 一直没有显式传 `-l`,默默继承了这个上限。这直接导致下面两条结论曾经测错:一个 Laravel Facade 方法报"7/24 文件(~29%)"、一个普通 React hook 报"20/30(~67%)",两个数字里的"20"都不是巧合。已修复:`cg-trace.sh` 现在默认 `-l 200`,并在结果卡满上限时返回 `possiblyTruncated: true` 提示——看到这个字段就该提高上限重查,不要直接采信数字;
- **Laravel Facade 调用实测召回率订正为 100%,不再是~29%(2026-07-19 订正上一条结论)**:自定义 Facade `Activity::event(...)` 真实调用点 58 处(24 个文件),修复上面这个截断 bug 后重新查询,24/24 文件全部召回。但同时发现一个更窄、更具体的真问题:Laravel 全局辅助函数 `event(new SomeEvent(...))` 和 Facade 背后的 `ActivityLogService::event()` 方法同名,codegraph 会把两者混为一谈,带出 4 个实际根本没调用过 Facade 的假阳性文件——查到"意外命中"时,读一眼真实调用行确认是不是这种全局函数/方法同名碰撞;
- **React hook 召回率同样订正为 100%,不再是~67%(2026-07-19 订正上一条结论)**:`useFlash()` hook 真实调用点 30 个,是同一个 20 条截断 bug 造成的假象,修复后单次查询直接拿到完整 30/30,不需要交叉核实才能补齐;
- **`cg-node.sh` 的调用链展示虽然没有 `-l` 可调,但截断是诚实的,不是又一个静默截断坑(field-verified 2026-07-20,`hi.events`)**:`codegraph node` 符号模式完全没有 `-l`/`--limit` 选项,但它自己的文本输出在链断掉的地方会显式打一个 `+N more` 标记——实测 `findById` 的一个定义处列出 12 个调用者后接 `+31 more`,12+31=43,和 Round 3 已经核实过的同一符号真实调用者总数完全吻合。看到 `+N more` 就该换 `cg-trace.sh` 提高上限查全量;反过来,一条短链如果没有这个标记,不能像修复前的 `callers`/`callees` 那样怀疑是被默默截断了。
- **Laravel 构造函数注入接口(标准依赖注入写法,和 Facade 是不同的魔法机制)实测能可靠解析,不需要理解容器绑定本身(field-verified 2026-07-19,`hi.events`)**:`EventRepositoryInterface::findById()` 声明在接口上、通过继承在 `BaseRepository` 里实现、在 ServiceProvider 里绑定到 `EventRepository`——直接查接口方法本身的调用者(而不是具体实现类)就能拿到全部真实调用点(实测 43 个,人工 grep 核对 100% 一致),因为 PHP 里接口类型的调用会挂在接口自己的节点上,这和已有的 Java 接口/实现结论是同一个机制,不需要 codegraph 理解 ServiceProvider 的绑定逻辑;
- Vue/React 动态 `() => import('...')`(React 侧写作 `lazy(() => import('...'))`)路由懒加载、MyBatis XML mapper 绑定:**跟 cbm 一样是盲区**,graph 完全无感知,直接 grep/read——原先只在 Vue Router 上验证过,2026-07-18 在 `pterodactyl/panel` 上追加验证 React 经典 `lazy()` 写法同样复现,2026-07-19 在 `hi.events` 上又验证了 React Router v6.4 的 `async lazy() { await import(...) }` 数据路由写法(语法结构完全不同),三种写法结论一致,确认是跨框架、跨语法的共同盲区;
- **Eloquent 本地 scope(`scopeXxx` 声明、调用时去掉 `scope` 前缀写成 `->xxx(...)`)是干净的盲区(field-verified 2026-07-18,`pterodactyl/panel`)**:`HasRealtimeIdentifier::scopeWhereIdentifier` 真实调用点仅 1 处,codegraph 按声明名索引,和去掉前缀后的真实调用形态完全对不上,召回 0/1——查任何 Eloquent scope 方法,直接 grep 去掉 `scope` 前缀后的调用形式;
- Spring `getBean(运行时拼接名)` 场景:codegraph 会把接口的全部实现类都列成 dynamic dispatch 候选——诚实但不精确(不代表"全部被调用"或"就是这一个"),仍需 grep bean 名拼接逻辑;
- **`SpringUtils.getBean(X.class)` 这种确定性单目标的 Bean 查找,比上面的运行时拼接名场景更差——完全解析不到**,`callers`/`node`/`impact` 三个命令 0/2 召回,且这个盲区会直接传导进 `cg-impact.sh` 的影响面分析,导致"改这个方法安全吗"这类问题被漏报;查任何接口方法的调用方/影响面前,建议顺手 grep 一下 `SpringUtils.getBean(<接口>.class)` 作为兜底核实(cbm 侧因为 name-only 解析,反而可能把这类调用点意外混在噪声里带出来,但不可依赖,同样需要 grep 兜底);
- **`SpringUtils.getAopProxy(this).<method>(...)` 自调用是 `getBean(X.class)` 盲区的姊妹坑,而且这次是两个工具真正共同盲区(field-verified 2026-07-18)**——不像上面的 `getBean(X.class)` 那样 cbm 侧因 name-only 解析可能意外带出来,这次 `cg-trace.sh`/`cg-node.sh` 和 `cbm-cypher.sh dead-code-methods` 独立测试都漏掉了同一个通过 AOP 代理自调用触发 `@Cacheable` 的调用点——两个工具都同意"这方法是死代码"在这里没有印证价值,详见 `skills/code-navigator/references/codegraph-blindspots.md`;
- **类的 `extends` 关系单向,查父类能看到子类列表(标签是 `Called by`,略有误导),反过来查子类完全看不到父类是谁**,JSON schema 里没有 `extends`/`superclass` 字段,精确复现上游 open issue [#1328](https://github.com/colbymchenry/codegraph/issues/1328)——要查一个类继承自谁,直接 grep `class X extends Y` 声明行;
- **`cg-explore.sh`(官方文档最推荐的旗舰单一命令,也是唯一默认开启的 MCP 工具)纯中文查询完全失效**,测试了"字典标签""字典标签查询""用户登录""部门管理"四个不同中文业务词全部返回空,但用完全相同的词跑底层 `cg-find.sh`(FTS 全文检索)却精确命中——纯中文业务问题请直接用 `cg-find.sh`,不要指望 `cg-explore.sh`;
- **上一条的结论只在 Java 后端仓库上成立,在 Vue/TS 前端仓库上 `cg-find.sh` 本身也会失效(field-verified 2026-07-18,plus-ui)**:同样是纯中文查询,这次连 `cg-find.sh` 也系统性失败(0/6,两轮独立测试,不论词旁边有没有拉丁字母标识符都一样),看起来是这个仓库形态下 codegraph FTS 层的 CJK 分词问题,不是查询写法的问题;`cbm-grep.sh` 在同一批词上 6/6 全部命中,逐字匹配独立人工 grep 的结果。**中文业务词查询在 Vue/TS 仓库上请只用 `cbm-grep.sh`,不要把 `cg-find.sh` 当作同等可靠的替代**,详见 `skills/code-navigator/references/tool-collaboration-benchmark.md`;
- 没有裸图查询能力(无 Cypher 等价物),死代码/hubs 这类全图模式问题**明确不要用 `cg-explore.sh` 兜底**——实测(2026-07-17)它对这类问题做的是关键词/语义检索而非图分析,会把问题里的词(如"find"/"list")匹配到同名符号上,再套用跟正常答案一模一样的"Blast radius"格式自信地给出**看似合理实则文不对题**的结果,不是"答不出来"而是"答错了还不报错";这两类问题只有装了 codebase-memory-mcp 才能回答;
- "列出所有 routes/classes/interfaces/components" 这类**穷举**(而非模糊搜索)反而有直接等价物:`cg-find.sh -k route\|class\|interface\|component`(pattern 留空)——实测数量与 `codegraph status` 的 `nodesByKind` 完全一致(303/303 routes、482/482 classes、99/99 components),比 `cbm-cypher.sh` 的 routes 模板还多带 HTTP 方法;
- **`codegraph index` 全量重建时若有任何其他 codegraph 进程(哪怕只是一次只读 `query`)并发持有数据库文件,会直接硬失败退出**(`EPERM: database file is in use`,不会自动重试,但确认不会损坏现有索引),范围比上游 issue #1325 描述的"MCP server 运行时冲突"更广;日常增量更新用的 `codegraph sync` 未复现此问题,`index --force` 应单独跑,不要和其他 codegraph 调用并发;
- `codegraph install` 会写 MCP 配置,本套件明确不使用它。

## LSP 协作(2026-07-18 新增,协议层面,非实测能力)

Claude Code 自带的 LSP 工具是第三个独立信息源,完整协议见 `skills/code-navigator/references/lsp-and-native-fallbacks.md`。**本环境实测(2026-07-18):Java 和 TypeScript 的语言服务器均未安装**——`findReferences` 对 `.java` 文件直接报 `"No LSP server available for file type: .java"`,`documentSymbol` 对 `.ts` 文件报 `"typescript-language-server not found"`。因此:

- LSP 在 SKILL.md 决策表里**不出现在任何一行的链头**,只作为单符号问题的机会性额外佐证(试一次、失败静默降级、不重试、不建议安装);
- "LSP 若可用能提供什么"(预期:编译器级 receiver-type 精度、不受 Lombok 同名碰撞影响)**目前全部是未经实测的设计推演**,不是本仓库的实测结论——任何环境真的装好可用的语言服务器后,应按本仓库一贯的 field-verify 纪律重新实测,再把这段升级为结论。

## 工具选型对比(实测,2026-07-16~18,codegraph v1.4.1 vs codebase-memory-mcp v0.9.0)

在 RuoYi-Vue-Plus + plus-ui 两个真实仓库上做的头对头验证,同一批符号、同一批盲区场景,现已直接烘进 `SKILL.md` 的决策表本体;下表是这些结论的证据附录。这份对比之外,还有一份专门测试"多个工具怎么协作"(而不是"哪个工具更好")的补充验证——`SpringUtils.getAopProxy(this)` 自调用坑、`app.config.globalProperties` 挂载函数坑、`cg-node.sh` 文件级聚合碰撞、Glob 优先快速路径、"多信号一致不等于互相印证"等发现都来自那一轮,完整方法论和 8 组原始数据见 `skills/code-navigator/references/tool-collaboration-benchmark.md`。**该文件的"Round 2"一节记录了后续用 `pterodactyl/panel` 补齐 Laravel+PHP/React+TS 证据缺口的一轮测试,"Round 3"一节记录了用 `hi.events` 做的第二轮验证——期间发现并修复了 `cg-trace.sh` 自身的一个默认截断 bug,连带订正了 Round 2 里 Facade 召回率(29%→100%)和 `useFlash` hook 召回率(67%→100%)两条结论,并新增了 Laravel 构造函数注入接口解析、PHP 全局函数/方法同名碰撞、React Router v6.4 动态路由等发现,下表相应行已同步这两轮结论。"Round 4"一节记录了顺着 `cg-trace.sh` 那次教训做的一次系统性审计——不是新找仓库测试,而是把每个 `cg-*.sh`/`cbm-*.sh` 脚本的假设逐条对照上游 `--help` 文档核查,在 `cbm-*` 一侧又挖出 4 个真实脚本 bug(详见上方"已知边界:codebase-memory-mcp 一侧"新增条目),但没有推翻任何已发布的具体数字。**

| 场景 | codebase-memory-mcp | codegraph |
|---|---|---|
| Java 接口→实现类调用 | 静默返回 0 callers,查询层因 Cypher 引擎限制无法修复,只能靠 SKILL.md 里的 MANDATORY 交叉查协议(必须 2 次调用取并集)兜底 | 图里有 interface→impl 链接,`node`/`explore` **一次调用**给出双向证据 + `[dynamic: ...]` 标注,`cg-trace.sh` 已实现自动桥接;准确度上限跟 cbm 一样(底层裸 `callers` 命令仍会把接口声明误当成"1 个 caller"),但达到同等准确度所需的调用次数更少、token 更省 |
| Vue/React 路由懒加载(`() => import()` / `lazy(() => import())` / React Router v6.4 `async lazy()`) | 完全无边 | 完全一样,同样无边——两个工具在这一点上共同的局限,不是某一方的短板,换工具解决不了,只能 grep router 配置;先后在 Vue Router、React 经典 `lazy()`、React Router v6.4 数据路由三种写法上验证,结论一致 |
| Laravel Facade 调用(如 `Activity::event(...)`) | 未实测(索引这个仓库时内存打满被迫放弃,见上方 cbm 已知边界) | 实测召回 24/24 文件(100%,2026-07-19 订正:原先报的 20/59~29% 是 `cg-trace.sh` 一个默认截断 20 条结果的 bug 造成的假象,已修复重测)——但要留意一个更窄的真问题:PHP 全局函数和同名 Facade 方法会被混淆,带出假阳性,意外命中时读一眼调用行确认 |
| Laravel 构造函数注入接口(标准依赖注入,如 `EventRepositoryInterface`) | 未实测 | 实测能可靠解析(43 个真实调用者,人工核对 100% 一致),不需要理解 ServiceProvider 容器绑定——直接查接口方法节点即可,机制和 Java 接口/实现一致 |
| Eloquent 本地 scope(`scopeXxx` 声明,调用时去 `scope` 前缀) | 未实测 | 干净盲区,召回 0/1——按声明名索引,和去前缀后的真实调用形态对不上,直接 grep 去前缀后的调用形式 |
| PHP 同名方法接收者类型消歧(如 `UserCreationService::handle()` vs 十几个不相关 `*CreationService` 类的同名 `handle()`) | 未实测 | 零假阳性(实测 4/4,19 处文本相同调用形状里精确排除 15 处不相关类)——和 Java 上已验证的接收者类型限定结论一致,不是 Java 专属 |
| Spring `getBean(运行时拼接名)` | 完全无法解析 | 用接口/实现启发式把全部候选实现列为 dynamic dispatch——不精确但诚实可用 |
| Spring `getBean(X.class)`(确定性单目标) | 因 name-only 解析,可能意外混在噪声里带出这类调用点,不可依赖 | 完全解析不到,0/2 召回,且会传导进 `impact` 分析导致漏报 |
| MyBatis XML mapper 绑定 | 完全无法解析 | 完全一样,XML 建了文件节点但 0 symbols,零绑定——同上,两个工具共同的局限 |
| 死代码/hubs/跨层违规全图模式查询 | 有专门的 Cypher 模板(`cbm-cypher.sh`);2026-07-17 逐个实跑核实后,`hubs`/`cross-layer` 2 个模板发现是静默答错(已修复),`dead-code`(Function 标签)对 Java 接口方法必然误报(用 `dead-code-methods`+交叉查协议代替) | **无等价物,且 `cg-explore.sh` 会文不对题地"答出来"**——关键词匹配到同名符号后套用正常回答的格式,不报错也不提示这是错的,比"查不到"更危险;实测过三种问法(死代码/hubs/routes)全部踩坑 |
| routes 全量列表 | 有专门的 Cypher 模板,单条记录准确,但曾在这个仓库的规模上静默截断(现会主动报出真实总数),只含 path 不含 HTTP 方法 | 实测有直接等价物:`cg-find.sh -k route`(pattern 留空)穷举,数量与 `codegraph status` 精确对上,`name` 字段还带 HTTP 方法,在这个仓库规模下无截断问题,且是单次 CLI 调用而非 Cypher 往返——两个工具都存在时优先这个 |
| 改动关联的测试文件 | 无此能力 | `codegraph affected` 原生支持,返回值含 `totalDependentsTraversed` 可作为"确实没有覆盖测试"结论的可信度信号 |
| 索引速度(RuoYi-Vue-Plus,709 文件) | 未记录精确耗时 | 2.4 秒,16497 节点/28199 边 |
| Lombok getter/setter 同名碰撞 | 实测 60% 假阳性:`DictService.getDictLabel` 的 callers 里 6/10 其实是不相关 Vo 类的 Lombok getter,name-only 边解析 | 用同一批同名符号测试,零污染——边按接收者类型限定,不是纯按方法名 |
| 中文业务语言查询,Java 后端仓库 | 语义搜索(`-s`)完全不支持中文,得分近随机;纯文本 `cbm-grep.sh` 可用 | 底层 `cg-find.sh`(FTS)对中文表现好,但旗舰命令 `cg-explore.sh` 纯中文查询直接返回空——同一工具内部两个命令表现不一致,要分场景选 |
| 中文业务语言查询,Vue/TS 前端仓库(实测 2026-07-18,plus-ui) | `cbm-grep.sh` 6/6 命中,逐字匹配人工 grep | `cg-find.sh` 本身也系统性失败(0/6),不只是 `cg-explore.sh`——这一行的结论不能从后端仓库直接套用到前端仓库,纯中文查询在这类仓库上请只用 `cbm-grep.sh` |
| 类继承关系(`extends`)查询 | 从未建模 | 单向缺口:查父类能看到子类,查子类看不到父类,复现上游 open issue #1328 |
| 配置文件键绑定(`@Value("${key}")` ↔ `application.yml`;`import.meta.env.VITE_X` ↔ `.env`) | `cbm-find.sh` 零可见;`cbm-grep.sh` 部分可见(实测把 `.env` 建模成 Module 节点,能找到定义行) | `cg-find.sh` 意外部分可见(实测把部分 `application.yml` 的 key 建成 `constant` 节点并链接到 `@Value` 引用点)——两边都不完整,原生 grep+Read 仍是唯一可靠路径,不要写成"图谱完全看不到" |
| 跨仓库一致性(如前端 API 调用是否有对应后端路由) | 无此能力,索引严格限定在自己 cwd 所在仓库 | 同样无此能力;可作为原生 grep 两侧结果的交叉核实(`cg-find.sh -k route`),field-verified 3/3 匹配成功 |
| 符号名已确切知道时的定位(exact 文件名/类名/组件名) | 原生 `Glob` 完胜两个图谱工具(实测 2026-07-18):更快(最多 18x)、更省 token、精度相等或更高——图谱工具在这种场景下只会带来模糊匹配噪声和额外延迟 | 同上,`Glob` 优先,两个图谱工具都不应作为第一选择 |
| LSP(Claude Code 自带,2026-07-18 新增测试) | — | 本环境两个语言的语言服务器均未安装,协议为机会性尝试 + 静默降级,不是本仓库的实测能力,见"LSP 协作"一节 |

结论:两个图谱工具没有绝对的谁更好,互补大于替代,且**两者共享的局限(Vue 动态 import、MyBatis XML、`app.config.globalProperties` 挂载函数、`SpringUtils.getAopProxy(this)` 自调用)换工具换不掉,只能 grep**——单符号溯源(调用链/影响面)、routes 全量列表优先 codegraph(同等准确度下更省 token、更快);死代码/hubs/跨层违规全图模式扫描 codegraph 完全没有能力,只能用 codebase-memory-mcp 修复后的 `cbm-cypher.sh`,且这两类问题**不要**用 `cg-explore.sh` 兜底。LSP 目前不参与这个对比——它在本环境未经实测,只作为决策表之外的机会性佐证层。

再往外一层的协作性结论(见 `tool-collaboration-benchmark.md`):**符号名已确切知道时,原生 `Glob` 应该跳过两个图谱工具直接用**;判断"两个信号一致"能不能当结论前,先确认两个信号是不是共享同一个盲区——`getAopProxy` 自调用坑就曾经让"死代码查询"和"结构化交叉核实"两个看似独立的信号同时判断错误,一致本身不构成印证。

## License

MIT
