# cbm-navigator

让 Claude Code 通过 **纯 CLI(零 MCP)** 使用 [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) 预建代码知识图谱的 Skill 套件:符号定位、调用链、影响面、架构综述、死代码、语义检索——一次图谱调用替代几十轮 grep/read。

内含三个组件:
| 组件 | 位置 | 作用 |
|---|---|---|
| `cbm-navigator` skill | `skills/cbm-navigator/` | 触发协议 + 8 个查询脚本 + 盲区参考 |
| `cbm-deep-analyst` subagent | `agents/` | 高风险问题(影响面/改造决策)以 `effort: high` 在独立上下文运行并回传已验证结论 |
| PreToolUse hook(可选) | `optional/hooks/` | Grep/Glob 时自动注入图谱符号匹配作为 additionalContext,非阻断 |

## 前提

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
   三个 flag 的原因:`--name` 固定项目短名(默认名是绝对路径扁平化,因人而异,跨机器不可移植);`--persistence true` 才会写团队共享工件 `.codebase-memory/graph.db.zst`(**默认不写**);语义检索(`cbm-find.sh -s`)依赖 similarity/semantic 边,仅 `--mode full|moderate` 构建,若语义检索无结果用 `--mode full` 重建。
3. 本机有 `jq`。

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

可选增强:对 ≥1 万行的重点仓库,把 `optional/CLAUDE.md.snippet` 内容加入该仓库的 CLAUDE.md,强化触发。其中 `<PROJECT_NAME>` 填索引输出 JSON 的 `project` 字段值——**注意命名规则(实机验证):project 名是仓库绝对路径的扁平化**(去掉前导分隔符、分隔符换连字符),如 `/Users/me/www/my-service` → `Users-me-www-my-service`,不是目录名;可用 `codebase-memory-mcp cli list_projects` 查询。skill 脚本已内置该规则的自动解析(扁平化精确匹配 + basename 后缀兜底),无需手工配置。

## 内置运行时门槛(团队实测口径,写在 SKILL.md 内)

1. **小仓库不用**:当前仓库 <~1,000 行代码时,skill 指导 Claude 直接用原生 grep/read——全局安装 ≠ 全局使用;
2. **档位认知**:思考/输出 token 预算过小会限制检索质量,low/medium 档准确度低于 high/xhigh/max,图谱不能抬升该上限;**将被采取行动的结论**(影响面、改造决策)会被委派给 `cbm-deep-analyst`(effort 覆盖 + 独立上下文 + 源码复核),该 agent 不可用时回退为建议升档 + 原生复核。

## 安装后 10 分钟自测

1. `codebase-memory-mcp cli list_projects` 能看到目标项目;
2. 问"XxxService 的调用链" → 触发 skill,单次 cbm-trace 出链,无连环 Grep;
3. 问"这个项目的整体架构" → 单次 cbm-arch;
4. 问"有哪些死代码" → cbm-cypher dead-code;
5. 问 MyBatis XML 动态 SQL 问题 → 不用图谱、直接 grep/read;在 <1,000 行小仓库问结构问题 → 同样不用图谱;
6. 问不存在的函数调用链 → trace 返回 0 + hint,Claude 转 cbm-find 而非重试;
7. 主会话设为 low(/effort)问影响面问题 → 应委派 cbm-deep-analyst;若所装 Claude Code 版本不支持 agent 的 `effort` frontmatter(以继承档位运行),确认回退话术出现。

## 维护指引

- **文档换行规范**:SKILL.md、references、agent 定义、CLAUDE.md 片段一律"一句一行"(句末标点处换行,句内不折行),PR diff 即句子粒度;
- **触发调优是持续过程**:观察一周,哪类结构问题仍走原生多轮 grep,就把该类触发短语提 PR 加进 `SKILL.md` 的 description(中英文都收);
- **盲区案例**:发现新的图谱盲区形态(解析不到/答错),提 issue 附最小复现,合并进 `references/blindspots.md`;
- **上游跟踪**:codebase-memory-mcp 周更级迭代;若某 release 更改工具参数名(如 trace 深度参数),按 `cli get_graph_schema` 校准脚本中的 jq 投影;
- **发版**:改动合并后 bump `.claude-plugin/plugin.json` 的 version 并更新 CHANGELOG,plugin 用户 `/plugin marketplace update` 获取。

## CLI 调用形式说明

上游已弃用 raw JSON 位置参数(`cli <tool> '<json>'` 会打印 deprecation 警告,未来版本移除)。本套件所有脚本统一通过 **stdin 管道**传 JSON,且收敛在 `scripts/_project.sh` 的 `cbm_call()` 单一包装函数中——若未来 CLI 调用形式再次变更(如 flags-only),只需修改该函数一处。

## 已知边界(上游)

- **官方 README 为 main 分支,可能超前于已发布版本**(实测:main 文档中的 `--raw` flag 在 v0.9.0 上不存在)。任何 CLI 用法以 `cli <tool> --help` 与实际输出为准,不以 main 文档为准;
- 查询结果的文件字段为 `file_path` 且**无行号字段**(v0.9.0 实测),脚本投影与 Cypher 模板已按此适配(coalesce 兼容);
- macOS 默认无 `timeout` 命令,hook 已内置 timeout/gtimeout 探测,均无时依赖 settings 层的 hook timeout 兜底;
- **Java:接口方法与实现类方法是图谱里的两个不同节点,调用边只挂在接口方法上(field-verified,非边缘情况)**。对 `*Impl` 类方法直接查 callers/impact/dead-code 会得到假的 0——包括单实现接口,不需要多实现+`@Primary`才触发。必须同时查接口方法,取并集,详见 `skills/cbm-navigator/references/blindspots.md`;
- 图谱 Route 节点的类级 `@RequestMapping` 前缀经实测(3 个真实 Controller)**完整保留,未复现前缀丢失**;上游 issue #734 描述的丢失问题仍 open(milestone 0.9.1-rc),不同项目/版本可能表现不同,不要默认套用;
- **前端:Vue/React 路由懒加载 `() => import('...')` 组件在图谱里没有引用边**(field-verified on plus-ui)——判断路由懒加载组件是否被使用,直接 grep router 配置,不要信图谱的"0 引用";
- `detect_changes` 在 git worktree 下失效(上游 bug),请在普通 clone 使用;
- `effort` 为 subagent frontmatter 较新字段,部署前按自测第 7 条验证;
- 引用 GitHub issue 编号前必须实际打开确认——曾核查过的 5 个二手引用编号里有 4 个对不上号(指向无关内容或不存在),只有 1 个精确匹配。

## License

MIT
