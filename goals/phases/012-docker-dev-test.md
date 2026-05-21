# Goal 012: Docker Dev/Test

## 背景

让 AI 和 CI 都能使用统一的 Docker 环境。

## 任务

- 完善 `deploy/docker-compose.dev.yml`。
- 完善 `deploy/docker-compose.test.yml`。
- 完善 Dockerfile。
- 更新 DEVELOPMENT 文档。

## 完成标准

- dev compose 可以启动 server/web。
- test compose 可以跑检查。

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
