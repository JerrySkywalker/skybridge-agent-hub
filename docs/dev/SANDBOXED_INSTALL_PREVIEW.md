# Sandboxed Install Preview

SkyBridge sandboxed install is a repository-local rehearsal only. It extracts the portable package under `.agent/tmp/install-sandbox/current/` and never writes host install locations.

Commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-install-sandbox.ps1 -Command plan
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-install-sandbox.ps1 -Command apply-preview
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-install-sandbox.ps1 -Command apply-sandbox
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-install-sandbox.ps1 -Command verify
```

Safety boundary:

- host install is disabled;
- registry, service, scheduled task, Startup folder, PATH and powercfg mutation are disabled;
- package extraction is confined to `.agent/tmp/install-sandbox/current/`;
- launcher validation runs only status, start-preview, doctor, demo and safe-summary modes;
- worker execution, workunit apply, task claim and queue apply remain disabled;
- `token_printed=false`.

Reports:

- `.agent/tmp/install-sandbox/install-sandbox-plan.json`
- `.agent/tmp/install-sandbox/install-sandbox-manifest.json`
- `.agent/tmp/install-sandbox/install-sandbox-verification.json`
- `.agent/tmp/install-sandbox/install-sandbox-report.json`
- `.agent/tmp/install-sandbox/install-sandbox-report.md`
