[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$workflow = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\.github\workflows\deploy-cloud.yml")
$dockerWorkflow = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\.github\workflows\build-image.yml")
foreach ($needle in @("workflow_run:", "workflows: [""Docker Images""]", "github.event.workflow_run.conclusion == 'success'", "github.event.workflow_run.head_branch == 'main'", "workflow_dispatch:", "missing_required_configuration", "SKYBRIDGE_PUBLIC_API_BASE", "cloud-deploy-report", "deploy-skybridge-server.sh", "deploy/docker-compose.skybridge.yml", "/tmp/docker-compose.skybridge.yml", "--compose-source /tmp/docker-compose.skybridge.yml", 'owner="${GITHUB_REPOSITORY_OWNER,,}"', 'image_ref="ghcr.io/$owner/skybridge-agent-hub-server:$expected_tag"')) {
  if ($workflow -notmatch [regex]::Escape($needle)) { throw "Deploy workflow contract missing: $needle" }
}
if ($dockerWorkflow -notmatch [regex]::Escape("type=sha,prefix=sha-,format=long")) { throw "Docker workflow must publish long SHA tags for deploy parity." }
$summary = [pscustomobject]@{ ok = $true; scenario = "deploy-workflow-contract"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
