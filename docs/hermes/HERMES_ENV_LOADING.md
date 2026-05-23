# Hermes Env Loading

SkyBridge Hermes scripts load local Hermes API settings from:

```text
$HOME\.skybridge\hermes.env.ps1
```

Set `HERMES_ENV_FILE` to override that path for a shell or smoke test. The loader is fail-open: a missing file reports `file_exists=false` and `loaded=false`, but does not fail the caller.

Expected local variables:

- `HERMES_API_BASE`: local SSH tunnel or trusted private endpoint.
- `HERMES_API_KEY`: local API key. Never print or commit it.
- `HERMES_MODEL`: optional safe default model for run smoke tests.

Create a local file from `config/hermes.env.example.ps1` and replace the placeholder values outside Git. The loader reports variable presence only and always uses `value_included=false` for secret-bearing fields.

Validate without exposing values:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-hermes-env.ps1 -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-env-loading.ps1
```
