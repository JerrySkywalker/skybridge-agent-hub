# Goal 013: GitHub PR CI

## 背景

公开仓库需要安全的 GitHub-hosted PR CI。

## 任务

- 完善 `.github/workflows/pr-ci.yml`。
- 确保不使用 secrets。
- 增加 lint/typecheck/test/build。
- 更新 CONTRIBUTING 说明 public repo runner 安全边界。

## 完成标准

- PR CI 可运行。
- 不触发自托管 runner。

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
