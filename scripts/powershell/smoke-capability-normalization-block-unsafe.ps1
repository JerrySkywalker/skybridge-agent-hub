[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$config = [pscustomobject]@{
  capabilities = @("codex", "git", "gh", "node", "pnpm", "powershell", "windows", "laptop")
  allowed_task_types = @("docs", "local-smoke")
  blocked_task_types = @("deploy", "production", "secret", "github-settings", "branch-protection", "server-config", "server-root-config")
}

$unsafeTypeTask = [pscustomobject]@{
  task_id = "smoke-unsafe-server-root"
  task_type = "server-root-config"
  title = "Change OpenResty root config"
  required_capabilities = @("codex", "git", "gh")
  expected_files = @("docs/dev/UNSAFE.md")
}
$unsafeSmokeTask = [pscustomobject]@{
  task_id = "smoke-unsafe-local-smoke"
  task_type = "local-smoke"
  title = "Add deploy smoke"
  body = "Run docker compose up against production and write secrets."
  required_capabilities = @("powershell", "windows")
  expected_files = @("scripts/powershell/smoke-unsafe.ps1")
}

$unsafeType = Test-TaskCompatible -Task $unsafeTypeTask -Config $config
$unsafeSmoke = Test-TaskCompatible -Task $unsafeSmokeTask -Config $config
if ($unsafeType.compatible) { throw "Expected server-root-config task to be blocked." }
if ($unsafeType.blocked_reason -ne "blocked_task_type:server-root-config") { throw "Expected blocked task type reason." }
if ($unsafeSmoke.compatible) { throw "Expected unsafe local-smoke task to be blocked." }
if ($unsafeSmoke.blocked_reason -ne "unsafe_local_smoke") { throw "Expected unsafe_local_smoke reason." }

$summary = [pscustomobject]@{
  ok = $true
  unsafe_type_reason = $unsafeType.reason
  unsafe_smoke_reason = $unsafeSmoke.reason
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
