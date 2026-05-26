param([int]$Port = 0)

$ErrorActionPreference = "Stop"

if ($Port -le 0) { $Port = Get-Random -Minimum 28001 -Maximum 32000 }
$ApiBase = "http://127.0.0.1:$Port"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-offline-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$configFile = Join-Path $tempDir "edge-worker.json"

@{
  worker_id = "smoke-offline-worker"
  name = "Smoke Offline Worker"
  project_id = "smoke-offline-project"
  repo_path = (Resolve-Path ".").Path
  api_base = $ApiBase
  poll_interval_seconds = 1
  capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
  allowed_task_types = @("docs")
  blocked_task_types = @("deploy", "secrets", "production")
  codex_command = "codex"
  codex_sandbox = "danger-full-access"
  max_task_runtime_minutes = 5
  auto_merge_enabled = $false
  notification_enabled = $false
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configFile -Encoding UTF8

$output = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -Loop -DryRun -PollIntervalSeconds 1 -IdleTimeoutSeconds 1 -Json
$results = @($output | Where-Object { $_ -match "^\s*\{" } | ForEach-Object { $_ | ConvertFrom-Json })
$final = $results[-1]

if (-not $final.loop) { throw "Expected final loop result." }
if ($final.stop_reason -notmatch "degraded:skybridge_server_unavailable") {
  throw "Expected server-unavailable degraded stop, got $($final.stop_reason)."
}
if (-not (Test-Path -LiteralPath $final.log_dir -PathType Container)) { throw "Expected offline loop log directory." }
$log = Get-Content -Raw -LiteralPath (Join-Path $final.log_dir "loop.jsonl")
if ($log -notmatch "degraded" -or $log -notmatch "skybridge_server_unavailable") {
  throw "Expected degraded offline log entry."
}

[pscustomobject]@{
  ApiBase = $ApiBase
  StopReason = $final.stop_reason
  LogDir = $final.log_dir
  CodexExecuted = $false
  ServerRequired = $true
} | Format-List
