$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$control = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "scripts\powershell\skybridge-dev-queue-control.ps1")
foreach ($forbidden in @("start-one -Apply", "start-all -Apply", "resume -Apply", "execute-step", "worker_loop_started=true", "Worker loop started true")) {
  if (($web + "`n" + $desktop) -match [regex]::Escape($forbidden)) { throw "Attention UI contains execution control text: $forbidden" }
}
foreach ($required in @("start_one_apply", "start_queue_apply", "start_all", "no_execution_enablement_in_goal_196")) {
  if ($control -notmatch [regex]::Escape($required)) { throw "Queue control execution blocker missing: $required" }
}

[pscustomobject]@{
  ok = $true
  scenario = "attention-no-execution-controls"
  can_start_one = $false
  can_start_queue = $false
  can_resume = $false
  token_printed = $false
} | ConvertTo-Json -Compress
