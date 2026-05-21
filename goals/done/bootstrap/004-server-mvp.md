# Goal 004: Server MVP

## 背景

实现 Agent Hub 最小后端服务。

## 任务

- 完善 `apps/server`。
- 提供 `/health`。
- 提供 `POST /v1/events`。
- 提供 `GET /v1/events`。
- 提供 `GET /v1/runs`。
- 保持内存存储即可，不急于数据库。

## 完成标准

- 本地 `pnpm --filter @skybridge-agent-hub/server dev` 能启动。
- `/health` 返回 ok。
- 能提交事件并查询。

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
