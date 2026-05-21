# Goal 021: Mobile App Readiness

## 背景

提前为移动端遥控 APP 预留 API。

## 任务

- 增加 device registration API 草案。
- 增加 notification deep link 设计。
- 增加 approval queue API 草案。
- 写文档，不急于实现原生 APP。

## 完成标准

- API 草案能支持未来 FCM/小米 Push。
- 明确 app 打开后通过 Agent Hub 拉取真实状态。

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
