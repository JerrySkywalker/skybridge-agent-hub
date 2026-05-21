# Goal 020: Remote Node WSS Plan

## 背景

未来自研遥控 APP 需要本地 node 主动连接云端。

## 任务

- 写 `docs/architecture/REMOTE_NODE.md`。
- 设计 node registry、heartbeat、reverse command channel。
- 不实现生产控制，只做设计和接口草案。

## 完成标准

- 文档说明 WSS 反向连接。
- 明确安全边界和审批机制。

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
