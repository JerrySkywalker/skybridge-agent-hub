[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$desktopBridge = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src-tauri\src\lib.rs")
$installScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-service-install.ps1")
$repairScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-service-repair.ps1")
$heartbeatScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-heartbeat-pairing-drill.ps1")

foreach ($needle in @(
  "Bootstrap Alpha Worker Setup",
  "MG330 install apply is PowerShell exact-confirmation only",
  "Install apply available",
  "Repair apply available",
  "Heartbeat preview",
  "Heartbeat apply available",
  "Cloud worker registered",
  "Cloud worker status",
  "Service command preview",
  "Install apply unavailable in Desktop",
  "Repair apply unavailable in Desktop",
  "Heartbeat apply unavailable in Desktop",
  "template_runner_enabled=false; worker_loop_started=false; token_printed=false",
  "claim_enabled=false",
  "execute_enabled=false",
  "Codex execution disabled",
  "MATLAB execution disabled"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) { throw "Desktop worker install flow missing text: $needle" }
}

foreach ($needle in @(
  "install_apply_available",
  "repair_apply_available",
  "heartbeat_preview_available",
  "heartbeat_apply_available",
  "cloud_worker_registered",
  "cloud_worker_status",
  "template_runner_enabled: false",
  "codex_run_called: false",
  "matlab_run_called: false",
  "arbitrary_shell_enabled: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) { throw "Client worker install fixture missing text: $needle" }
}

foreach ($needle in @(
  "install_apply_available",
  "heartbeat_apply_available",
  "cloud_worker_registered",
  "template_runner_enabled"
)) {
  if ($desktopBridge -notmatch [regex]::Escape($needle)) { throw "Desktop bridge worker install fallback missing text: $needle" }
}

foreach ($needle in @(
  "I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION",
  "user_level_heartbeat_only_wrapper",
  "claim_enabled = `$false",
  "execute_enabled = `$false",
  "worker_loop_started = `$false",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "token_printed = `$false"
)) {
  if ($installScript -notmatch [regex]::Escape($needle)) { throw "Install script missing safety text: $needle" }
}

foreach ($needle in @(
  "I_UNDERSTAND_REPAIR_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION",
  "reconcile_user_level_heartbeat_only_wrapper",
  "missing_exact_confirmation",
  "claim_enabled = `$false",
  "execute_enabled = `$false",
  "worker_loop_started = `$false",
  "token_printed = `$false"
)) {
  if ($repairScript -notmatch [regex]::Escape($needle)) { throw "Repair script missing safety text: $needle" }
}

foreach ($needle in @(
  "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM",
  "/v1/workers/register",
  "/v1/workers/",
  "mg330_heartbeat_only_no_task_claim_no_execution",
  "claim_created = `$false",
  "execution_started = `$false",
  "worker_loop_started = `$false",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($heartbeatScript -notmatch [regex]::Escape($needle)) { throw "Heartbeat script missing safety text: $needle" }
}

foreach ($forbidden in @(
  "Start Worker Loop",
  "Codex run button",
  "MATLAB run button",
  "shell box"
)) {
  if ($desktopSource -match [regex]::Escape($forbidden)) { throw "Desktop worker install flow includes forbidden text: $forbidden" }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-worker-install-flow"
  desktop_live_apply_enabled = $false
  install_apply_powerShell_only = $true
  heartbeat_pairing_visible = $true
  claim_enabled = $false
  execute_enabled = $false
  worker_loop_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
