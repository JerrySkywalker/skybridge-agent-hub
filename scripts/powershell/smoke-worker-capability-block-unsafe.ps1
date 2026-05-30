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
  task_id = "smoke-worker-unsafe-block"
  task_type = "production"
  title = "Deploy production service"
  required_capabilities = @("codex", "git", "gh")
  expected_files = @("docs/dev/DEPLOY.md")
}

$match = Test-TaskCompatible -Task $task -Config $config
if ($match.compatible) { throw "Expected production task to be blocked." }
if ($match.blocked_reason -ne "blocked_task_type:production") { throw "Expected production blocked reason." }

$summary = [pscustomobject]@{
  ok = $true
  compatible = $match.compatible
  reason = $match.reason
  blocked_reason = $match.blocked_reason
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
