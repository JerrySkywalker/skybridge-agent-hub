# Sandboxed Upgrade Rollback

The sandbox upgrade model rehearses a local package replacement without touching the host OS.

Directories:

- `.agent/tmp/install-sandbox/current/`
- `.agent/tmp/install-sandbox/previous/`
- `.agent/tmp/install-sandbox/rollback/`
- `.agent/tmp/install-sandbox/staging/`

Commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-upgrade-rollback-sandbox.ps1 -Command upgrade-plan
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-upgrade-rollback-sandbox.ps1 -Command upgrade-sandbox
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-upgrade-rollback-sandbox.ps1 -Command rollback-plan
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-upgrade-rollback-sandbox.ps1 -Command rollback-sandbox
```

Upgrade copies `current` to `previous`, extracts the package to `staging`, then replaces `current` from `staging`. Rollback copies the current install to `rollback` and restores `previous` to `current`.

All writes are confined to `.agent/tmp/install-sandbox/`. There is no network update, binary download, GitHub release action, registry mutation, service mutation, scheduled task creation, Startup folder write, PATH mutation or powercfg mutation. `token_printed=false`.

Reports:

- `.agent/tmp/install-sandbox/upgrade-sandbox-report.json`
- `.agent/tmp/install-sandbox/rollback-sandbox-report.json`
- `.agent/tmp/install-sandbox/upgrade-rollback-sandbox-report.md`
