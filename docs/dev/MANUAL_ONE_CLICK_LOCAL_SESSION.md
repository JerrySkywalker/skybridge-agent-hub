# Manual One-click Local Session

The manual local session is a bounded, explicitly invoked preview for non-worker components only.

Preview start:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command start
```

Apply a bounded local session:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command start -Apply -Profile full-local-preview -Bounded
```

Fixture apply for smoke tests:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command start -Apply -Profile full-local-preview -Bounded -Fixture
```

Stop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command stop
```

Status, doctor and cleanup preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command status
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command check
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command cleanup
```

Still disabled: Codex worker, workunit apply, task creation, task claim, task PR creation, generic queue apply, remote execution and arbitrary command dispatch. Do not run `start-all`, `start-queue` or `resume -Apply`. token_printed=false
