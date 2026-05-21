# Goal 015: Build Images

## 背景

main/tag 后需要构建可部署镜像。

## 任务

- 完善 `.github/workflows/build-image.yml`。
- 构建 server/web 镜像。
- 推送到 GHCR。
- tag 使用 sha 与版本标签。

## 完成标准

- GitHub Actions 能构建镜像。
- 镜像名和 deploy compose 一致。

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
