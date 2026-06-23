[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$desktopBridge = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src-tauri\src\lib.rs")
$identityScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-identity.ps1")
$liveHeartbeatScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-live-heartbeat.ps1")

foreach ($needle in @(
  "Worker name",
  "Worker provider",
  "Worker identity status",
  "Identity preview",
  "Identity apply available",
  "Live heartbeat preview",
  "Live heartbeat apply available",
  "Live heartbeat last result",
  "Identity setup preview",
  "Identity apply unavailable in Desktop",
  "Live heartbeat apply unavailable in Desktop",
  "MG331 identity and live heartbeat apply are PowerShell exact-confirmation only",
  "claim_enabled=false",
  "execute_enabled=false",
  "Codex execution disabled",
  "MATLAB execution disabled"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) { throw "Desktop worker identity heartbeat missing text: $needle" }
}

foreach ($needle in @(
  "worker_name",
  "worker_provider",
  "worker_identity_status",
  "identity_setup_preview_available",
  "identity_apply_available",
  "live_heartbeat_preview_available",
  "live_heartbeat_apply_available",
  "live_heartbeat_last_result",
  "identity_setup: true",
  "live_heartbeat: true",
  "worker_id_not_configured",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) { throw "Client worker identity fixture missing text: $needle" }
}

foreach ($needle in @(
  "worker_name",
  "worker_provider",
  "worker_identity_status",
  "identity_setup_preview_available",
  "live_heartbeat_preview_available",
  "live_heartbeat_last_result",
  "worker_id_not_configured"
)) {
  if ($desktopBridge -notmatch [regex]::Escape($needle)) { throw "Desktop bridge worker identity fallback missing text: $needle" }
}

foreach ($needle in @(
  "I_UNDERSTAND_CONFIGURE_LOCAL_WORKER_IDENTITY_NO_TASK_EXECUTION",
  "SKYBRIDGE_WORKER_ID",
  "SKYBRIDGE_WORKER_NAME",
  "SKYBRIDGE_WORKER_PROVIDER",
  "claim_enabled = `$false",
  "execute_enabled = `$false",
  "worker_loop_started = `$false",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "token_printed = `$false"
)) {
  if ($identityScript -notmatch [regex]::Escape($needle)) { throw "Worker identity script missing safety text: $needle" }
}

foreach ($needle in @(
  "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM",
  "/v1/workers/register",
  "/v1/workers/",
  "mg331_live_heartbeat_only_no_task_claim_no_execution",
  "worker_registered",
  "heartbeat_sent",
  "cloud_worker_seen",
  "claim_created = `$false",
  "execution_started = `$false",
  "worker_loop_started = `$false",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($liveHeartbeatScript -notmatch [regex]::Escape($needle)) { throw "Worker live heartbeat script missing safety text: $needle" }
}

foreach ($forbidden in @(
  "Start Worker Loop",
  "Codex run button",
  "MATLAB run button",
  "shell box"
)) {
  if ($desktopSource -match [regex]::Escape($forbidden)) { throw "Desktop worker identity heartbeat includes forbidden text: $forbidden" }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-worker-identity-heartbeat"
  desktop_live_apply_enabled = $false
  identity_apply_powerShell_only = $true
  live_heartbeat_apply_powerShell_only = $true
  claim_enabled = $false
  execute_enabled = $false
  worker_loop_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
