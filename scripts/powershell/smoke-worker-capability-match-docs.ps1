[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$config = [pscustomobject]@{
  capabilities = @("codex", "git", "gh", "node", "pnpm", "powershell", "windows", "laptop")
  allowed_task_types = @("docs", "local-smoke")
  blocked_task_types = @("deploy", "production", "secret", "github-settings", "branch-protection", "server-config", "server-root-config")
}
$task = [pscustomobject]@{
  task_id = "smoke-worker-docs-match"
  task_type = "docs"
  title = "Document worker status filters"
  required_capabilities = @("docs")
  expected_files = @("docs/orchestrator/WORKER_PROFILE_RUNBOOK.md")
}

$match = Test-TaskCompatible -Task $task -Config $config
if (-not $match.compatible) { throw "Expected laptop capabilities to match normalized docs task: $($match.reason)" }
if (@($match.missing_normalized_capabilities).Count -ne 0) { throw "Expected no missing normalized capabilities." }

$summary = [pscustomobject]@{
  ok = $true
  compatible = $match.compatible
  original_required_capabilities = @($match.original_required_capabilities)
  normalized_required_capabilities = @($match.normalized_required_capabilities)
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
