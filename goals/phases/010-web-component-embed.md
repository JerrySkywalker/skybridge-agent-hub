# Goal 010: Web Component Embed

## 背景

为 Glance/Halo/普通 HTML 提供可嵌入控件。

## 任务

- 完善 `packages/web-components`。
- 实现 `<agent-status-card>` MVP。
- 提供 `/embed/compact` 页面或文档示例。

## 完成标准

- 能用一行 HTML 嵌入状态卡片。
- 不要求功能完整，但架构清楚。

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
