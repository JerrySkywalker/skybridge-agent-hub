# Local Install Runbook

This runbook covers local preview setup only.

1. Validate repository state:

```powershell
git status -sb
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate
```

2. Install dependencies:

```powershell
corepack pnpm install
```

3. Preview Web and Desktop builds:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-launch.ps1 -Command web-preview
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-launch.ps1 -Command desktop-preview
```

4. Inspect diagnostics:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-diagnostics.ps1 -Command report
```

Keep execution disabled by default. Do not run `start-all`, `start-queue`, `resume -Apply`, generic bounded queue apply, Codex worker execution or unbounded worker loops.

token_printed=false
