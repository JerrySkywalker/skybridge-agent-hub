# Goal 019: Hermes Adapter

## 背景

Hermes 更适合作为上层编排来源，需要接入其 run/status 概念。

## 任务

- 完善 `packages/agent-adapters/hermes-api`。
- 定义 Hermes run/status/events 到 SkyBridge event 的映射。
- 增加配置项占位。

## 完成标准

- 有清晰映射表。
- 后端可预留 Hermes source。

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
