# Goal 006: Codex Hook Adapter

## 背景

接入本地 Codex hook 是第一阶段的核心。

## 任务

- 完善 `scripts/powershell/codex-dashboard-hook.ps1`。
- 将 Codex 原始 hook JSON 转换为 `skybridge.agent_event.v1`。
- 增加脱敏策略：默认不上传完整 command/stdout/stderr。
- 更新 `config/codex/hooks.example.json`。

## 完成标准

- Codex SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/PermissionRequest/Stop 能映射到统一事件。
- hook 失败不会阻塞 Codex。

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
