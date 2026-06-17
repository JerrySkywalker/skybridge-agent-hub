# Manual Task Hermes Provider Preview

Goal 295/296 adds a Hermes DeepSeek provider preview for the local Manual Task Queue.

Default behavior remains `mock`. Hermes DeepSeek is present as a disabled-by-default provider option and does not make network calls in preview mode.

## Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command provider-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command provider-check -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command run-next-mock -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command run-next-hermes-preview -Json
```

`run-next-hermes-preview` consumes one queued manual task and records a safe preview result. It sets `live_call_performed=false`, `remote_llm_inference_enabled=false`, `raw_request_persisted=false`, `raw_response_persisted=false` and `token_printed=false`.

## Reports

- `.agent/tmp/manual-task/manual-task-provider-report.json`
- `.agent/tmp/manual-task/manual-task-hermes-preview-report.json`
- `.agent/tmp/manual-task/manual-task-hermes-live-optin-report.json` only when live opt-in is attempted

The reports store provider status, safe result previews, hashes, durations and safe error summaries only.
