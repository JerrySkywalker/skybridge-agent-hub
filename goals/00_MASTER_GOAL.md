# MASTER GOAL: SkyBridge Agent Hub

## 背景

本项目用于建设一个长期可维护、全开源的个人 Agent 控制与遥测底座，服务 Jerry 的本地 Codex、OpenCode、Hermes Agent 与未来自研遥控 APP。

工程名称已经从临时 starter / YOLO 命名收束为：

```text
SkyBridge Agent Hub
repo: skybridge-agent-hub
schema: skybridge.agent_event.v1
```

## 总目标

构建一个可自托管的 Agent Hub：

1. 接收 Codex / OpenCode / Hermes / 自研 Agent 的运行事件；
2. 统一转换为 `skybridge.agent_event.v1`；
3. 聚合 session / run / turn / tool / approval / notification 状态；
4. 提供实时 SSE/WebSocket 流；
5. 提供可嵌入前端控件；
6. 基于 ntfy 实现第一版消息中台；
7. 为后续手机遥控 APP、local sidecar、远程审批和多推送渠道预留接口。

## 当前阶段策略

由于近期重点是论文答辩，开发策略采用：

```text
高自治开发 + 低打扰通知 + 自动测试修复 + 生产边界硬保护
```

也就是：

- Codex 可以高自治完成分支开发；
- 普通 lint/type/test/build 失败允许自动修复；
- 低风险改动可以自动 PR；
- staging 可以自动部署；
- 生产密钥、服务器根配置、破坏性命令必须硬阻断；
- 通知只推送失败、卡住、审批、回滚等关键事件。

## 阶段路线

1. YOLO 护栏与工程规范；
2. monorepo 基础工程；
3. `skybridge.agent_event.v1` 事件模型；
4. server MVP；
5. SSE 实时流；
6. Codex hook adapter；
7. local sidecar MVP；
8. dashboard compact view；
9. React widgets；
10. Web Component embed；
11. ntfy-first Message Center；
12. Docker dev/test/prod；
13. GitHub PR CI；
14. AI branch auto-repair runner；
15. image build and GHCR publishing；
16. cloud staging deploy；
17. SQLite persistence；
18. OpenCode adapter；
19. Hermes adapter；
20. remote node WSS plan；
21. mobile app readiness.

## 完成定义

项目初步完成时应具备：

- 本地 Codex hook 能上报事件；
- Web Dashboard 能显示当前 Agent 状态与 timeline；
- Message Center 能通过 ntfy 推送关键通知；
- Docker dev/test/prod 能运行；
- GitHub CI 能验证 PR；
- 云服务器可部署 staging；
- 后续可扩展到 OpenCode/Hermes/远程 APP。
