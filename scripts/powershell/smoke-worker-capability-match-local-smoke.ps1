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
  task_id = "smoke-worker-local-smoke-match"
  task_type = "local-smoke"
  title = "Add worker loop status smoke"
  body = "Create a read-only smoke that checks local tool versions and status query output while redacting token values."
  required_capabilities = @("powershell", "windows")
  expected_files = @("scripts/powershell/smoke-worker-loop-status.ps1")
}

$match = Test-TaskCompatible -Task $task -Config $config
if (-not $match.compatible) { throw "Expected laptop capabilities to match safe local-smoke task: $($match.reason)" }
foreach ($capability in @("codex", "powershell", "windows")) {
  if (@($match.normalized_required_capabilities) -notcontains $capability) { throw "Expected normalized capability $capability." }
}

$summary = [pscustomobject]@{
  ok = $true
  compatible = $match.compatible
  normalized_required_capabilities = @($match.normalized_required_capabilities)
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
