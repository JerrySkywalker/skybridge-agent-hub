# Goal 011: Message Center ntfy

## 背景

通知中台第一阶段以 ntfy 为出口。

## 任务

- 实现 ntfy notification provider。
- 增加 `/v1/notifications/send`。
- 增加规则：run.failed、approval.requested、deploy.failed 触发通知。
- 通知只发送摘要和链接。

## 完成标准

- 可以通过 API 发送 ntfy。
- 不上传完整日志或敏感信息。

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
