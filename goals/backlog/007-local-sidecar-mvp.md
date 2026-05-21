# Goal 007: Local Sidecar MVP

## 背景

本地 sidecar 用于未来本地缓存和云端上报。

## 任务

- 完善 `apps/sidecar`。
- 提供 `POST /v1/local/events`。
- 将事件转发到 `SKYBRIDGE_CLOUD_URL`。
- 转发失败时先记录日志，后续再做 spool。

## 完成标准

- sidecar 只监听 127.0.0.1。
- 可以接收 hook 事件并转发 server。

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
