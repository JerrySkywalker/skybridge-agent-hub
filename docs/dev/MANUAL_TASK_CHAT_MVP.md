# Manual Task Chat MVP

Goal 293/294 adds a local Manual Task Chat and Manual Task Queue MVP for human testing.

The MVP is local-only:

- Web and Desktop show a Manual Task Chat panel.
- The PowerShell queue stores sanitized `input_preview`, `input_hash`, lifecycle metadata and `result_preview`.
- The only provider is `provider_id=mock`.
- The mock provider is deterministic and performs no network calls.
- Hermes live calls remain disabled.
- Worker execution, workunit creation, task claim, task PR creation and queue apply remain disabled.
- `token_printed=false`.

## CLI

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-queue.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-queue.ps1 -Command add-question -Question "What should I inspect next?" -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-queue.ps1 -Command run-next-mock -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-queue.ps1 -Command clear-completed -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-queue.ps1 -Command report -Json
```

Reports are written under `.agent/tmp/manual-task/`.

## UI

The Web and Desktop controls are local manual controls:

- input box
- Add to queue
- Run next mock
- Clear completed
- task list contract
- result preview contract
- disabled Hermes/live provider status

The panels do not expose worker apply, start, claim, task PR, queue apply, remote execution or arbitrary command controls.
