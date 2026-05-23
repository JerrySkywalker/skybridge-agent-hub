# Hermes Cloud Run Smoke

`scripts/powershell/smoke-hermes-cloud-run.ps1` submits one harmless prompt through the local Hermes API tunnel and reports only redacted metadata.

Prompt:

```text
Return exactly one sentence: SkyBridge Hermes supervisor connectivity is healthy. Do not call tools. Do not access files.
```

The script tries `/v1/responses` first, then falls back to `/v1/chat/completions` when the responses request is incompatible. It requests `tools=[]` and `tool_choice=none` where supported. It does not print the API key, prompt body, response body or model value.

Safe dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-run.ps1 -DryRun -Json
```

Real local tunnel smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-run.ps1 -Json
```

Configuration is loaded through `scripts/powershell/load-hermes-env.ps1`, normally from `$HOME\.skybridge\hermes.env.ps1`. Keep that file outside Git.
