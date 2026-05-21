# Goal 003: Event Schema v1

## 背景

SkyBridge 的核心是统一事件模型，需要优先稳定 `skybridge.agent_event.v1`。

## 任务

- 完善 `packages/event-schema`。
- 增加 run/session/turn/tool/approval/notification 的 TypeScript 类型。
- 增加 zod schema 与测试。
- 更新 `ARCHITECTURE.md` 中的事件类型说明。

## 完成标准

- schema 能表达 Codex hook、OpenCode plugin、Hermes run 三类来源。
- 测试覆盖常用事件类型。
- 类型能被 server/client 引用。

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
