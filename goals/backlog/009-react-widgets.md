# Goal 009: React Widgets

## 背景

前端要做成可复用控件，而不是绑定 Glance。

## 任务

- 完善 `packages/react-widgets`。
- 实现 `AgentStatusCard`、`AgentTimeline`、`AgentPipelineBar` 的 MVP。
- 控件通过 `apiBase` 连接后端。

## 完成标准

- apps/web 使用 react-widgets。
- 组件不依赖具体宿主。

## 禁止

- 不要提交 `.env`、token、私钥或任何真实密钥。
- 不要修改生产部署脚本，除非本 goal 明确要求。
- 不要删除测试来使 CI 通过。
- 不要扩大范围到后续阶段。

## 建议命令

```powershell
pnpm lint
pnpm typecheck
pnpm test
pnpm build
```
