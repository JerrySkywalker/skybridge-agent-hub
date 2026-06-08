[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-fixture -Fixture safe -Apply -Json | ConvertFrom-Json
if (-not $result.ok -or -not $result.wrote) { throw "Fixture draft was not written." }
if ([string]$result.proposed_markdown_path -notlike "goals/proposed/*") { throw "Draft path escaped goals/proposed." }
if ($result.imported -or $result.executed -or $result.task_created -or $result.worker_loop_started) { throw "Draft generation caused import/execution side effects." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-fixture-generate"; path = $result.proposed_markdown_path; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
