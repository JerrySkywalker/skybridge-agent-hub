$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command completed-run-registry -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.self_bootstrap_completed_run.v1") { throw "Unexpected registry schema." }
$goals = @($result.completed_runs | ForEach-Object { [string]$_.goal })
foreach ($goal in @("214", "216", "217", "218", "219", "220", "221", "223", "224", "225", "226")) {
  if ($goals -notcontains $goal) { throw "Missing completed goal $goal." }
}
foreach ($number in @(171, 175, 176)) {
  $pr = @($result.completed_task_prs | Where-Object { $_.number -eq $number })
  if ($pr.Count -ne 1 -or $pr[0].merged -ne $true) { throw "Required task PR #$number is not recorded as merged." }
}
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-completed-run-registry"; token_printed = $false } | ConvertTo-Json
