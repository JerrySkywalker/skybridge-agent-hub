# Goal 016: Cloud Staging Deploy

## 背景

main 合并后部署 staging，但生产先不要冒进。

## 任务

- 完善 `deploy/scripts/deploy.sh`、`healthcheck.sh`、`rollback.sh`。
- 编写云端 `/opt/skybridge` 部署说明。
- staging 使用镜像拉取部署，不在服务器构建源码。

## 完成标准

- staging 可通过手动脚本部署。
- 失败能 rollback。

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
