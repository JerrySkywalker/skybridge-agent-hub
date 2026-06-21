[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureReadinessFile,
  [string]$FixtureHermesExposureFile,
  [string]$FixtureNotificationReadinessFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-BoolProp {
  param($Object, [string]$Name, [bool]$Default = $false)
  $value = Get-Prop -Object $Object -Name $Name -Default $Default
  if ($null -eq $value) { return $Default }
  return [bool]$value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 240)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Invoke-ChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -eq 0 -and $null -ne $parsed) { return $parsed }
  if ($AllowNonZero -and $null -ne $parsed) { return $parsed }
  throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)"
}

function Get-Readiness {
  if ($FixtureReadinessFile) { return Read-JsonFile -Path $FixtureReadinessFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-self-bootstrap-readiness.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

function Get-HermesExposure {
  if ($FixtureHermesExposureFile) { return Read-JsonFile -Path $FixtureHermesExposureFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-hermes-exposure-readiness.ps1"),
    "-RequireSecondGate",
    "-AllowServerToolExecution",
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

function Get-NotificationReadiness {
  if ($FixtureNotificationReadinessFile) { return Read-JsonFile -Path $FixtureNotificationReadinessFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-notification-readiness.ps1"),
    "-DryRun",
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

$readiness = Get-Readiness
$hermesExposure = Get-HermesExposure
$notification = Get-NotificationReadiness

$controlPlane = Get-Prop -Object $readiness -Name "control_plane"
$projectControl = Get-Prop -Object $controlPlane -Name "project_control"
$workers = Get-Prop -Object $controlPlane -Name "workers"
$cloud = Get-Prop -Object $readiness -Name "cloud"
$version = Get-Prop -Object $cloud -Name "version"
$deploy = Get-Prop -Object $cloud -Name "deploy_evidence"
$repo = Get-Prop -Object $readiness -Name "repo"

$projectControlState = [string](Get-Prop -Object $projectControl -Name "state" -Default "unknown")
$cloudVersionCommit = [string](Get-Prop -Object $version -Name "commit_sha" -Default "")
$mainCommit = [string](Get-Prop -Object $repo -Name "main_commit" -Default "")
$cloudCommitAligned = (-not [string]::IsNullOrWhiteSpace($cloudVersionCommit) -and -not [string]::IsNullOrWhiteSpace($mainCommit) -and $cloudVersionCommit -eq $mainCommit)
if (-not $cloudCommitAligned -and (Get-BoolProp -Object $deploy -Name "ok")) { $cloudCommitAligned = $true }

$workerOnline = (([int](Get-Prop -Object $workers -Name "online" -Default 0)) -ge 1)
$notificationSupported = Get-BoolProp -Object $notification -Name "blocker_notice_supported"
$notificationUnsafe = (Get-BoolProp -Object $notification -Name "real_send_performed") -or (Get-BoolProp -Object $notification -Name "credential_values_exposed") -or (Get-BoolProp -Object $notification -Name "raw_notification_payload_included")

$hermes = Get-Prop -Object $hermesExposure -Name "hermes"
$toolExecution = [string](Get-Prop -Object $hermes -Name "tool_execution" -Default "unknown")
$hermesWarnings = @((Get-Prop -Object $hermesExposure -Name "warnings" -Default @()) | ForEach-Object { [string]$_ })
$hermesBlockers = @((Get-Prop -Object $hermesExposure -Name "blockers" -Default @()) | ForEach-Object { [string]$_ })
$toolRisk = ($toolExecution -ne "disabled" -and $toolExecution -ne "unknown") -or ($hermesWarnings -contains "hermes_server_tool_execution_enabled") -or ($hermesBlockers -contains "hermes_second_gate_required_for_server_tool_execution")
$secondGate = Get-Prop -Object $hermesExposure -Name "second_gate"
$secondGateConfigured = Get-BoolProp -Object $secondGate -Name "configured"

$previewBlockers = [System.Collections.Generic.List[string]]::new()
if (-not (Get-BoolProp -Object $readiness -Name "ok" -Default $false)) { $previewBlockers.Add("self_bootstrap_readiness_unavailable") }
if ($projectControlState -ne "paused") { $previewBlockers.Add("project_control_not_paused") }
if (-not $cloudCommitAligned) { $previewBlockers.Add("cloud_commit_not_aligned") }
if (-not $notificationSupported) { $previewBlockers.Add("notification_blocker_notice_unavailable") }
if ($notificationUnsafe) { $previewBlockers.Add("notification_readiness_unsafe") }
if (Get-BoolProp -Object $readiness -Name "token_printed") { $previewBlockers.Add("readiness_token_printed") }
if (Get-BoolProp -Object $hermesExposure -Name "token_printed") { $previewBlockers.Add("hermes_exposure_token_printed") }
if (Get-BoolProp -Object $notification -Name "token_printed") { $previewBlockers.Add("notification_token_printed") }

$allowedPreviewOnly = ($previewBlockers.Count -eq 0)
$allowedExecution = $false
if ($allowedPreviewOnly -and -not $toolRisk -and (Get-BoolProp -Object $readiness -Name "can_start_one") -and (Get-BoolProp -Object $readiness -Name "can_run_until_hold")) {
  $allowedExecution = $true
}
if ($toolRisk -and -not $secondGateConfigured) { $allowedExecution = $false }
if ($projectControlState -eq "paused") { $allowedExecution = $false }
if (-not $workerOnline) { $allowedExecution = $false }

$status = if (-not $allowedPreviewOnly) {
  "blocked"
} elseif ($allowedExecution) {
  "ready"
} else {
  "preview_ready"
}

$recommended = if (-not $allowedPreviewOnly) {
  "Fix preview blockers with read-only or explicitly authorized metadata-only actions; do not call start-one."
} elseif (-not $secondGateConfigured -and $toolRisk) {
  "Run start-one preview only. Keep project_control paused and configure a documented execution second gate before any apply pilot."
} else {
  "Run start-one preview only. Goal 318 does not authorize task claim, Codex execution, or project_control unpause."
}

$report = [pscustomobject]@{
  schema = "skybridge.execution_second_gate_readiness.v1"
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  status = $status
  project_id = $ProjectId
  project_control_state = $projectControlState
  cloud_commit_aligned = $cloudCommitAligned
  worker_online = $workerOnline
  notification_blocker_notice_supported = $notificationSupported
  hermes_exposure_status = [string](Get-Prop -Object $hermesExposure -Name "status" -Default "unknown")
  hermes_tool_execution_risk = [bool]$toolRisk
  second_gate_configured = [bool]$secondGateConfigured
  allowed_preview_only = [bool]$allowedPreviewOnly
  allowed_execution = [bool]$allowedExecution
  preview_blockers = @($previewBlockers.ToArray())
  forbidden_actions = [pscustomobject]@{
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    codex_run_called = $false
    queue_apply_called = $false
    project_control_unpaused = $false
    start_one_called = $false
    run_until_hold_called = $false
    real_notifications_sent = $false
  }
  recommended_next_safe_action = $recommended
  safety = [pscustomobject]@{
    read_only = $true
    preview_only = $true
    raw_hermes_response_included = $false
    raw_logs_included = $false
    credential_values_exposed = $false
    token_printed = $false
  }
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 24
} else {
  "Schema:       $($report.schema)"
  "Status:       $($report.status)"
  "Project:      $($report.project_id)"
  "Control:      $($report.project_control_state)"
  "CloudAligned: $($report.cloud_commit_aligned)"
  "WorkerOnline: $($report.worker_online)"
  "HermesRisk:   $($report.hermes_tool_execution_risk)"
  "SecondGate:   $($report.second_gate_configured)"
  "PreviewOnly:  $($report.allowed_preview_only)"
  "Execution:    $($report.allowed_execution)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
