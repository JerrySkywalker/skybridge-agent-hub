# Goal 005: SSE Stream

## 背景

Dashboard 和未来 APP 需要实时事件流。

## 任务

- 为 server 完善 `GET /v1/stream` SSE。
- 确保新事件会广播给订阅客户端。
- 添加最小测试或手动测试文档。
- 前端 client 能消费 SSE。

## 完成标准

- 浏览器/脚本可以订阅事件流。
- 新 POST 的事件能实时显示。

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
