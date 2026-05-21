# Goal 014: AI Branch Auto Repair Runner

## 背景

答辩期需要 CI 失败自动修复能力。

## 任务

- 完善 `scripts/powershell/yolo-runner.ps1`。
- 支持 MaxRepairRounds。
- 支持失败后移动 goal 到 failed。
- 支持成功后移动到 done。

## 完成标准

- 单个 goal 可以自动执行、检查、修复、提交。
- 失败后有明确日志。

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
