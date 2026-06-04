$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$lib = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

if ($lib -notmatch [regex]::Escape('run_worker_status(&["-Command", "register-heartbeat", "-Json"])')) {
  throw "Heartbeat Now must call only skybridge-worker-status.ps1 -Command register-heartbeat -Json."
}
if ($lib -notmatch [regex]::Escape("heartbeat-only register-heartbeat requested")) {
  throw "Heartbeat log entry must label the mutation as heartbeat-only."
}

foreach ($forbidden in @(
  "start-one",
  "start-all",
  "execute-step",
  "run-until-complete",
  "run-until-hold",
  "run-next",
  "skybridge-edge-worker.ps1",
  "create PR",
  "campaign-step task creation"
)) {
  if ($lib -match [regex]::Escape($forbidden)) {
    throw "Heartbeat implementation contains forbidden execution command/text: $forbidden"
  }
}

[pscustomobject]@{ ok = $true; scenario = "desktop-heartbeat-only"; token_printed = $false } | ConvertTo-Json -Compress
