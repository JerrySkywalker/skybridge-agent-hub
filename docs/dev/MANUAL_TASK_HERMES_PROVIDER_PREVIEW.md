# Manual Task Hermes Provider Preview

Goal 295/296 added a Hermes DeepSeek provider preview for the local Manual Task Queue. Goal 297/298 deprecates that local-direct path in favor of server-mediated Hermes.

Default behavior remains `mock`. `hermes_deepseek` is present as a deprecated preview-only provider option and does not make network calls. Use `skybridge_server_hermes` for server-mediated Hermes.

## Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command provider-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command provider-check -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command run-next-mock -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command run-next-skybridge-hermes -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-manual-task-provider.ps1 -Command run-next-hermes-preview -Json
```

`run-next-hermes-preview` consumes one queued manual task and records a deprecated no-network preview result. It sets `live_call_performed=false`, `remote_llm_inference_enabled=false`, `raw_request_persisted=false`, `raw_response_persisted=false` and `token_printed=false`.

## Reports

- `.agent/tmp/manual-task/manual-task-provider-report.json`
- `.agent/tmp/manual-task/server-hermes-provider-report.json`
- `.agent/tmp/manual-task/server-hermes-provider-report.md`
- `.agent/tmp/manual-task/server-hermes-preview-report.json`
- `.agent/tmp/manual-task/manual-task-hermes-preview-report.json`
- `.agent/tmp/manual-task/server-hermes-live-optin-report.json` only when server-mediated live opt-in is attempted

The reports store provider status, safe result previews, hashes, durations and safe error summaries only.
