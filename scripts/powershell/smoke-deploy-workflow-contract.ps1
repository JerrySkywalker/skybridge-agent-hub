[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$workflow = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\.github\workflows\deploy-cloud.yml")
foreach ($needle in @("workflow_run:", "workflows: [""Docker Images""]", "github.event.workflow_run.conclusion == 'success'", "github.event.workflow_run.head_branch == 'main'", "workflow_dispatch:", "missing_required_secrets", "cloud-deploy-report", "deploy-skybridge-server.sh")) {
  if ($workflow -notmatch [regex]::Escape($needle)) { throw "Deploy workflow contract missing: $needle" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "deploy-workflow-contract"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
