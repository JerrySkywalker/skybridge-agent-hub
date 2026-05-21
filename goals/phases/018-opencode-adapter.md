# Goal 018: OpenCode Adapter

## 背景

为未来备用 agent 接入预留能力。

## 任务

- 完善 `packages/agent-adapters/opencode-plugin`。
- 定义 OpenCode event 到 SkyBridge event 的映射。
- 写插件示例或文档。

## 完成标准

- 有清晰映射表。
- 不要求完全接入运行。

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
