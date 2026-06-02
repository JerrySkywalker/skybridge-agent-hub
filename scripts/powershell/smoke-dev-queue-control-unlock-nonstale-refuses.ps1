$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runnerRoot = Join-Path $repoRoot ".agent\campaign-runners"
$lockDir = Join-Path $runnerRoot "locks"
$lockPath = Join-Path $lockDir "skybridge-agent-hub__dev-queue-189-200.lock.json"
try {
  New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
  @{
    schema = "skybridge.campaign_runner_lock.v1"
    campaign_lock_id = "lock_188g_active"
    campaign_id = "dev-queue-189-200"
    project_id = "skybridge-agent-hub"
    lock_owner = "smoke-active-runner"
    lock_status = "active"
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    heartbeat_at = (Get-Date).ToUniversalTime().ToString("o")
    expires_at = "2099-01-01T00:00:00Z"
    release_reason = $null
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $lockPath -Encoding UTF8
  $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command unlock-stale-runner -Reason "188G smoke refuse active" -Apply -Json 2>&1
  if ($LASTEXITCODE -eq 0) { throw "Expected active non-stale runner unlock to fail." }
  if (($output -join "`n") -notmatch "Refusing to unlock active non-stale runner lock") { throw "Expected active lock refusal." }
  $lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
  if ($lock.lock_status -ne "active") { throw "Active lock must remain active." }
} finally {
  if (Test-Path -LiteralPath $runnerRoot) { Remove-Item -LiteralPath $runnerRoot -Recurse -Force }
}
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-unlock-nonstale-refuses"; token_printed = $false } | ConvertTo-Json -Compress
