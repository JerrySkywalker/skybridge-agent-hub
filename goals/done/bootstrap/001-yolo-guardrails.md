# Goal 001: YOLO Guardrails

## 背景

先建立 AI 托管开发的硬边界，避免答辩期无人值守时发生破坏性操作。

## 任务

- 完善 `AGENTS.md` 的禁止项与完成标准。
- 检查 `scripts/powershell/codex-guard-hook.ps1` 的危险命令拦截规则。
- 更新 `docs/codex/HOOKS.md`，说明如何启用 hook。
- 增加一个最小测试或脚本检查，确认项目基础命令可运行。

## 完成标准

- `AGENTS.md` 明确 YOLO 规则。
- guard hook 覆盖 destructive command、secrets、force push 等情况。
- 文档说明清晰。

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
