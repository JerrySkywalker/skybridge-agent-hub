# Operator Report

Mega Goal 323 adds `skybridge-operator-report.ps1` as a stable, sanitized
human-review summary for self-bootstrap state.

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-operator-report.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -IncludeCampaign `
  -IncludeBoundedRun `
  -IncludeHold `
  -Json
```

The output schema is `skybridge.operator_report.v1`.

The report includes safe summaries only:

- local/cloud commit and deploy evidence booleans;
- readiness and worker counts;
- notification dry-run status;
- campaign generated/completed/rejected counts;
- bounded run selected/executed counts, stop reason and hold reason;
- evidence presence booleans;
- old-residue exclusion proof;
- review gate status and next safe action.

The report never includes raw prompt content, raw Codex logs, stdout/stderr,
raw Hermes responses, credentials, cookies, token values, provider auth
headers, raw notification URLs, proxy profiles or environment dumps.

`token_printed=false` is required in every report.
