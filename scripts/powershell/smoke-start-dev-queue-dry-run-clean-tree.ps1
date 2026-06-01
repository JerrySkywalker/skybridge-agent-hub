[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$before = (git status --short --untracked-files=all | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($before)) {
  throw "Clean-tree smoke requires a clean working tree before it runs."
}

$runnerDir = Join-Path ".agent" "campaign-runners"
New-Item -ItemType Directory -Path (Join-Path $runnerDir "locks") -Force | Out-Null
@{ schema = "skybridge.campaign_runner_lock.v1"; campaign_id = "dev-queue-189-200"; lock_status = "fixture" } |
  ConvertTo-Json -Depth 5 |
  Set-Content -LiteralPath (Join-Path $runnerDir "locks\dry-run-clean-tree-smoke.lock.json") -Encoding UTF8

$after = (git status --short --untracked-files=all | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($after)) {
  throw ".agent/campaign-runners is not ignored; git status changed: $after"
}

$summary = [pscustomobject]@{ ok = $true; clean_tree_preserved = $true; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
