# Goal 002: Monorepo Bootstrap

## 背景

建立 TypeScript/pnpm monorepo 的基本工程能力。

## 任务

- 检查并完善 `package.json`、`pnpm-workspace.yaml`、`tsconfig.base.json`。
- 确保 `apps/server`、`apps/web`、`apps/sidecar`、`packages/*` 可以被 pnpm workspace 识别。
- 补齐必要的 lint/typecheck/test/build 脚本。

## 完成标准

- `pnpm install` 成功。
- `pnpm typecheck` 可运行。
- `pnpm test` 可运行。
- `pnpm build` 可运行。

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
