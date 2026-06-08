$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-worker-routing.ps1" -Command worker-capability-matrix -Json | ConvertFrom-Json
foreach ($field in @("worker_id", "worker_label", "worker_profile", "os", "tools", "task_type_capabilities", "project_access", "repo_access", "can_claim_tasks", "can_execute_tasks", "token_printed")) {
  if (-not $result.workers[0].PSObject.Properties[$field]) { throw "Capability matrix missing $field." }
}
if (@($result.workers | Where-Object { $_.os -eq "windows" }).Count -lt 1) { throw "Expected windows worker." }
if (@($result.workers | Where-Object { $_.os -eq "linux" }).Count -lt 1) { throw "Expected linux worker." }
if (@($result.workers | Where-Object { $_.can_execute_tasks -ne $false -or $_.can_claim_tasks -ne $false }).Count -gt 0) { throw "Workers must not claim or execute in Goal 197." }
[pscustomobject]@{ ok = $true; scenario = "worker-capability-matrix"; token_printed = $false } | ConvertTo-Json -Compress
