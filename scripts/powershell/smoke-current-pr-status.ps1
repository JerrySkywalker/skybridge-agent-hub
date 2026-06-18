[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmp = Join-Path $RepoRoot ".agent\tmp\goal-305-smoke"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$fixture = @([pscustomobject]@{
  number = 305
  url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/305"
  headRefName = "ai/goal-305-cloud-autodeploy-operator-scripts"
  isDraft = $false
  mergeStateStatus = "CLEAN"
  statusCheckRollup = @(
    [pscustomobject]@{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" },
    [pscustomobject]@{ name = "Docker build (server)"; status = "COMPLETED"; conclusion = "SUCCESS" }
  )
})
$fixturePath = Join-Path $tmp "current-pr.json"
$fixture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixturePath -Encoding utf8

$result = Invoke-JsonScript "skybridge-current-pr-status.ps1" @(
  "-Repo", "JerrySkywalker/skybridge-agent-hub",
  "-Branch", "ai/goal-305-cloud-autodeploy-operator-scripts",
  "-FixturePrListFile", $fixturePath
)
Assert-True $result.ok "current pr ok"
Assert-False $result.draft "draft"
Assert-TokenPrintedFalse $result
if ($result.check_state -ne "green") { throw "Expected green check_state." }

if ($Json) { $result | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "current-pr-status" }
