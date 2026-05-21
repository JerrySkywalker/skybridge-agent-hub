# Goal 008: Dashboard Compact View

## 背景

先做可用的独立 Dashboard，而不是追求完整 UI。

## 任务

- 完善 `apps/web` 首页。
- 显示 AgentStatusCard。
- 显示最新事件列表。
- 显示 run count、last event、last seen。

## 完成标准

- `pnpm --filter @skybridge-agent-hub/web dev` 能启动。
- 能连接本地 server。
- 新事件能在页面中出现。

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
