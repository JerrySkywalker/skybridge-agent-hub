# Goal 017: SQLite Persistence

## 背景

MVP 内存存储够用，但需要可恢复历史。

## 任务

- 为 server 增加 SQLite 存储。
- 持久化 events、runs、notifications。
- 保留内存 fallback 或简单迁移。
- 增加数据目录配置。

## 完成标准

- 重启 server 后事件历史仍可查询。
- 测试覆盖基本读写。

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
