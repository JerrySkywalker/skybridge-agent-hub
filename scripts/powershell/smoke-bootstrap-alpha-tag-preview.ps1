$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tagName = "v0.1.0-bootstrap-alpha-rc1"
$expectedCommit = "4473257548bd0fc26e05002d968f8525b37bac8b"
$expectedImageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b"
$before = @(& git tag --list $tagName 2>$null)
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1") -Command tag-preview -ApiBase "" -TokenFile "" -ExpectedCommit $expectedCommit -ExpectedImageRef $expectedImageRef -Json
if ($LASTEXITCODE -ne 0) { throw "RC tag preview failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)
$after = @(& git tag --list $tagName 2>$null)

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc_gate.v1") { throw "Unexpected RC tag preview schema." }
if ([string]$result.tag_name_preview -ne $tagName) { throw "Unexpected tag name preview." }
Assert-False $result.tag_created "tag_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.deploy_mutation_performed "deploy_mutation_performed"
Assert-False $result.token_printed "token_printed"
if (($before -join "`n") -ne ($after -join "`n")) { throw "Tag preview changed local tags." }

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-tag-preview"
  tag_name_preview = [string]$result.tag_name_preview
  tag_created = $false
  token_printed = $false
} | ConvertTo-Json
