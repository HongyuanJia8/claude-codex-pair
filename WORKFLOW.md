# 双 Agent 开发工作流（/pair）设计文档

> Claude Code 规划与审查，Codex 实现，git 自动化。默认关闭，显式调用才启动。

## 设计理念

1. **开关即调用**：不装任何常驻框架、不改默认行为。skill 只有在你显式输入
   `/pair` / `/pair-review` 时才运行；平时正常对话零开销。
2. **上下文隔离**：实现者（Codex）和审查者（全新上下文的 Claude subagent）互不
   共享对话历史。审查者只读，不能顺手改代码。
3. **确定性质量门**：format / lint / typecheck / test 由脚本退出码判定，
   不信任何 agent 自称"测试已通过"。
4. **不限制基模发挥**：交给 Codex 的 handoff 文档只写目标、约束、验收标准和
   相关文件指引，刻意不写实现方案。
5. **循环有上限**：修复—质量门循环最多 2 轮，review—修复循环最多 2 轮，
   到顶就停下来向你报告，绝不无限打转。

## 核心桥接机制（免手动复制上下文）

- Claude Code 在会话内直接 `codex exec -c approval_policy=never - < handoff.md`
  无头调用 Codex；handoff 走 stdin，不污染项目目录。
- 修复循环用 `codex exec resume --last "<反馈>"` —— Codex 保留完整实现上下文，
  只需要发增量反馈。
- Codex 的产出通过 `git diff` 回到 Claude Code 手里，审查、质量门、commit 全部自动。

## 用法

| 命令 | 场景 | 流程 |
|---|---|---|
| （不调用） | 小修改、问问题 | 正常对话，工作流不存在 |
| `/pair fast <任务>` | 小任务但想让 Codex 干活 | 一段话指令 → Codex → 质量门 → commit |
| `/pair <任务>` | 中等功能（默认 standard 档） | 澄清 → handoff 文档 → 分支 → Codex → 质量门 → Claude 只读 review（≤2 轮修复） → commit |
| `/pair strict <任务>` | 高风险/复杂改动 | standard + 计划需你人工批准 + 双重 review（Claude subagent 与 `codex exec review`），高危分歧时问你 |
| `/pair-review` | 只想要第二双眼睛 | 全新只读 subagent 审当前未提交改动；加 `codex` 参数叠加 Codex 原生 review；加 `base <branch>` 审分支 diff |

合并、push、开 PR 永远由你决定，工作流只 commit 到 `pair/*` 功能分支。

## 保留人工决策的节点

无论哪个档位，遇到以下情况一律停下来问你：

- 合并到主分支或 push
- 数据库 migration
- 删除/覆盖用户数据
- auth、权限、支付相关逻辑
- 公共 API 破坏性变更
- 大规模依赖新增/升级

## 对社区框架的取舍

- **Superpowers**：不安装。只借了 4 个思想 —— 规划前轻量 brainstorm（最多问 2-3
  个问题，且仅在需求模糊时）、handoff 计划作为交接工件、完成前验证清单、有上限的
  修复-审查循环。不采用它"每个微任务走全流程"、强制 TDD、每任务 fresh subagent
  的重型默认。
- **OpenSpec / Spec Kit**：都不装。strict 档的 handoff 文档就是轻量 spec，足以让
  两个 agent 共享一致需求。将来若有大型 greenfield 项目再单独评估 Spec Kit。

## 可选扩展（按需再做）

- **自动 Draft PR**：安装并登录 `gh` CLI 后，可在 Phase 6 加 `gh pr create --draft`。
- **反向调用**：在 `~/.codex/prompts/` 加一个自定义命令，让你在 Codex TUI 里也能
  一键 `claude -p` 叫 Claude review —— 适合以 Codex 为主界面的工作日。
- **并行任务**：同时跑多个 `/pair` 时改用 `git worktree`，每个任务独立目录互不干扰。

## 文件位置

- `~/.claude/skills/pair/SKILL.md` — 主工作流
- `~/.claude/skills/pair-review/SKILL.md` — 独立交叉审查
- `~/.claude/skills/pair/WORKFLOW.md` — 本文档
