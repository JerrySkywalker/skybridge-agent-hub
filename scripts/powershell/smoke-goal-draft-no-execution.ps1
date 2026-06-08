[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | ConvertFrom-Json
foreach ($field in @("executed", "task_created", "worker_loop_started")) {
  if ($result.$field) { throw "Unexpected execution side effect: $field" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-no-execution"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
