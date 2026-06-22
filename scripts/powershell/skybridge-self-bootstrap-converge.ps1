[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [switch]$RefreshHeartbeat,
  [switch]$WaitDeploy,
  [string]$OutputJsonFile,
  [string]$OutputMarkdownFile,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureLocalFile,
  [string]$FixtureVersionFile,
  [string]$FixtureRouteParityFile,
  [string]$FixtureDeployEvidenceFile,
  [string]$FixtureHeartbeatFile,
  [string]$FixtureReadinessFile,
  [string]$FixtureHygieneFile,
  [string]$FixtureHygieneApplyFile,
  [string]$FixtureNotificationReadinessFile,
  [string]$FixtureExecutionSecondGateFile,
  [string]$FixtureStartOnePreviewFile,
  [string]$FixturePilotSeedFile,
  [string]$FixtureStartOneApplyPilotFile,
  [string]$FixtureStartOneHoldReportFile,
  [string]$FixtureRunUntilHoldPilotSeedFile,
  [string]$FixtureRunUntilHoldBoundedFile,
  [string]$FixtureRunUntilHoldReportFile,
  [string]$FixtureCampaignTaskCompilerFile,
  [string]$FixtureCampaignPolicyReportFile,
  [string]$FixtureOperatorReportFile,
  [string]$FixtureOperatorNotificationReadinessFile,
  [string]$FixtureReviewGateFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

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

function Get-CountProp {
  param($Object, [string]$Name)
  $value = Get-Prop -Object $Object -Name $Name -Default 0
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return 0 }
  return [int]$value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 260)
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

function Invoke-GitText {
  param([string[]]$Arguments)
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
  (($output | Out-String).Trim())
}

function Invoke-ChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
  $attempt = 0
  while ($true) {
    $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = (($output | Out-String).Trim())
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      try { $parsed = $text | ConvertFrom-Json } catch {}
    }
    if ($exitCode -eq 0 -and $null -ne $parsed) { return $parsed }
    if ($exitCode -eq 0) { throw "Command did not return JSON: pwsh $($Arguments -join ' ')" }
    $safe = ConvertTo-SafeText -Text $text
    if ($attempt -lt 2 -and $safe -match "(?i)(ssl|tls|connection|timeout|temporarily|reset|eof|handshake)") {
      Start-Sleep -Seconds ([Math]::Min(2 + $attempt, 5))
      $attempt += 1
      continue
    }
    if (-not $AllowNonZero) {
      throw "Command failed: pwsh $($Arguments -join ' '): $safe"
    }
    if ($null -ne $parsed) { return $parsed }
    return [pscustomobject]@{ ok = $false; error_summary = $safe; token_printed = $false }
  }
}

function New-ProbeFailure {
  param([string]$Name, [string]$Message)
  [pscustomobject]@{
    ok = $false
    available = $false
    name = $Name
    error_summary = ConvertTo-SafeText -Text $Message
    token_printed = $false
  }
}

function Get-RepoFromRemote {
  try {
    $remote = Invoke-GitText @("remote", "get-url", "origin")
    if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
      return "$($Matches[1])/$($Matches[2])"
    }
  } catch {}
  return $null
}

function Get-LocalState {
  if ($FixtureLocalFile) { return Read-JsonFile -Path $FixtureLocalFile }
  $branch = ""
  $head = ""
  $main = ""
  $clean = $false
  try { $branch = Invoke-GitText @("branch", "--show-current") } catch {}
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "HEAD" }
  try { $head = Invoke-GitText @("rev-parse", "HEAD") } catch {}
  try { $main = Invoke-GitText @("rev-parse", "--verify", "origin/main") } catch {
    try { $main = Invoke-GitText @("rev-parse", "--verify", "main") } catch {}
  }
  try { $clean = [string]::IsNullOrWhiteSpace((Invoke-GitText @("status", "--short"))) } catch {}
  [pscustomobject]@{
    branch = $branch
    clean = $clean
    head_commit = $head
    main_commit = $main
  }
}

function Get-VersionProbe {
  if ($FixtureVersionFile) {
    $version = Read-JsonFile -Path $FixtureVersionFile
    return [pscustomobject]@{
      available = $true
      ok = [bool](Get-Prop -Object $version -Name "ok" -Default $true)
      commit_sha = Get-Prop -Object $version -Name "commit_sha"
      image_ref = Get-Prop -Object $version -Name "image_ref"
      token_printed = Get-BoolProp -Object $version -Name "token_printed"
    }
  }
  try {
    $resolved = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
    Assert-SkybridgeApiBaseUsable -ApiBase $resolved
    Assert-SkybridgeApiBaseService -ApiBase $resolved -TimeoutSeconds $TimeoutSeconds | Out-Null
    $version = Invoke-RestMethod -Method GET -Uri "$($resolved.TrimEnd('/'))/v1/version" -TimeoutSec $TimeoutSeconds
    Assert-SkybridgeVersionService -Version $version
    [pscustomobject]@{
      available = $true
      ok = $true
      commit_sha = Get-Prop -Object $version -Name "commit_sha"
      image_ref = Get-Prop -Object $version -Name "image_ref"
      token_printed = Get-BoolProp -Object $version -Name "token_printed"
    }
  } catch {
    New-ProbeFailure -Name "cloud_version" -Message $_.Exception.Message
  }
}

function Get-RouteParityProbe {
  if ($FixtureRouteParityFile) {
    $parity = Read-JsonFile -Path $FixtureRouteParityFile
  } else {
    try {
      $args = @("-File", (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1"), "-Json")
      if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
      $parity = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return New-ProbeFailure -Name "cloud_route_parity" -Message $_.Exception.Message
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $parity -Name "ok" -Default $false)
    deployment_parity_status = [string](Get-Prop -Object $parity -Name "deployment_parity_status" -Default (Get-Prop -Object $parity -Name "status" -Default "unknown"))
    missing_routes = @((Get-Prop -Object $parity -Name "missing_routes" -Default @()) | ForEach-Object { [string]$_ })
    token_printed = Get-BoolProp -Object $parity -Name "token_printed"
  }
}

function Get-DeployEvidenceProbe {
  param([string]$Commit)
  if ($FixtureDeployEvidenceFile) {
    $deploy = Read-JsonFile -Path $FixtureDeployEvidenceFile
  } else {
    if ([string]::IsNullOrWhiteSpace($Commit)) { return New-ProbeFailure -Name "deploy_evidence" -Message "local head commit unavailable" }
    $repo = Get-RepoFromRemote
    if ([string]::IsNullOrWhiteSpace($repo)) { return New-ProbeFailure -Name "deploy_evidence" -Message "repository remote unavailable" }
    try {
      $deployTimeout = if ($WaitDeploy) { [Math]::Max($TimeoutSeconds, 180) } else { $TimeoutSeconds }
      $args = @(
        "-File", (Join-Path $PSScriptRoot "skybridge-verify-cloud-autodeploy.ps1"),
        "-Repo", $repo,
        "-Commit", $Commit,
        "-TimeoutSeconds", [string]$deployTimeout,
        "-PollSeconds", "5",
        "-Json"
      )
      if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
      $deploy = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return New-ProbeFailure -Name "deploy_evidence" -Message $_.Exception.Message
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $deploy -Name "ok" -Default $false)
    commit_sha = Get-Prop -Object $deploy -Name "commit_sha"
    version_image_ref = Get-Prop -Object $deploy -Name "version_image_ref"
    deploy_report_status = Get-Prop -Object $deploy -Name "deploy_report_status"
    triggered_deploy = Get-BoolProp -Object $deploy -Name "triggered_deploy"
    mutated_server = Get-BoolProp -Object $deploy -Name "mutated_server"
    created_tag = Get-BoolProp -Object $deploy -Name "created_tag"
    token_printed = Get-BoolProp -Object $deploy -Name "token_printed"
  }
}

function Get-HeartbeatProbe {
  if (-not $RefreshHeartbeat) {
    return [pscustomobject]@{
      requested = $false
      refreshed = $false
      worker_id = $null
      heartbeat_sent = $false
      worker_online_after = $false
      tasks_claimed = $false
      codex_run_called = $false
      queue_apply_called = $false
      campaign_metadata_advanced = $false
      start_one_called = $false
      run_until_hold_called = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  if ($FixtureHeartbeatFile) {
    $proof = Read-JsonFile -Path $FixtureHeartbeatFile
  } else {
    try {
      $args = @(
        "-File", (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-proof.ps1"),
        "-HeartbeatOnly",
        "-ProjectId", $ProjectId,
        "-TimeoutSeconds", [string]$TimeoutSeconds,
        "-Json"
      )
      if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
      if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
      if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
      $proof = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      $proof = New-ProbeFailure -Name "heartbeat" -Message $_.Exception.Message
    }
  }
  [pscustomobject]@{
    requested = $true
    refreshed = ([bool](Get-Prop -Object $proof -Name "ok" -Default $false) -and [bool](Get-Prop -Object $proof -Name "heartbeat_sent" -Default $false) -and [bool](Get-Prop -Object $proof -Name "worker_online_after" -Default $false))
    worker_id = Get-Prop -Object $proof -Name "worker_id"
    heartbeat_sent = Get-BoolProp -Object $proof -Name "heartbeat_sent"
    worker_online_after = Get-BoolProp -Object $proof -Name "worker_online_after"
    tasks_claimed = Get-BoolProp -Object $proof -Name "tasks_claimed"
    codex_run_called = Get-BoolProp -Object $proof -Name "codex_run_called"
    queue_apply_called = Get-BoolProp -Object $proof -Name "queue_apply_called"
    campaign_metadata_advanced = Get-BoolProp -Object $proof -Name "campaign_metadata_advanced"
    start_one_called = Get-BoolProp -Object $proof -Name "start_one_called"
    run_until_hold_called = Get-BoolProp -Object $proof -Name "run_until_hold_called"
    project_control_unpaused = Get-BoolProp -Object $proof -Name "project_control_unpaused"
    token_printed = Get-BoolProp -Object $proof -Name "token_printed"
  }
}

function Get-ReadinessProbe {
  if ($FixtureReadinessFile) {
    $readiness = Read-JsonFile -Path $FixtureReadinessFile
  } else {
    $deployVerifyTimeout = if ($WaitDeploy) { [Math]::Max($TimeoutSeconds, 180) } else { $TimeoutSeconds }
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-self-bootstrap-readiness.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-DeployVerifyTimeoutSeconds", [string]$deployVerifyTimeout,
      "-DeployVerifyPollSeconds", "5",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    $readiness = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-BoolProp -Object $readiness -Name "ok" -Default $false) -and -not (Get-Prop -Object $readiness -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      status = "unavailable"
      blockers = @("self_bootstrap_readiness_unavailable")
      warnings = @()
      workers_online = 0
      online_worker_ids = @()
      project_control_state = "unknown"
      can_start_one = $false
      can_run_until_hold = $false
      allow_worker_heartbeat = $false
      allow_start_one = $false
      allow_run_until_hold = $false
      token_printed = Get-BoolProp -Object $readiness -Name "token_printed"
    }
  }
  $workers = Get-Prop -Object (Get-Prop -Object $readiness -Name "control_plane") -Name "workers"
  $projectControl = Get-Prop -Object (Get-Prop -Object $readiness -Name "control_plane") -Name "project_control"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $readiness -Name "ok" -Default $true
    status = [string](Get-Prop -Object $readiness -Name "status" -Default "unknown")
    blockers = @((Get-Prop -Object $readiness -Name "blockers" -Default @()) | ForEach-Object { [string]$_ })
    warnings = @((Get-Prop -Object $readiness -Name "warnings" -Default @()) | ForEach-Object { [string]$_ })
    workers_online = Get-CountProp -Object $workers -Name "online"
    online_worker_ids = @((Get-Prop -Object $workers -Name "online_worker_ids" -Default @()) | ForEach-Object { [string]$_ })
    project_control_state = [string](Get-Prop -Object $projectControl -Name "state" -Default "unknown")
    can_start_one = Get-BoolProp -Object $readiness -Name "can_start_one"
    can_run_until_hold = Get-BoolProp -Object $readiness -Name "can_run_until_hold"
    allow_worker_heartbeat = Get-BoolProp -Object $readiness -Name "allow_worker_heartbeat"
    allow_start_one = Get-BoolProp -Object $readiness -Name "allow_start_one"
    allow_run_until_hold = Get-BoolProp -Object $readiness -Name "allow_run_until_hold"
    token_printed = Get-BoolProp -Object $readiness -Name "token_printed"
  }
}

function Get-HygieneProbe {
  if ($FixtureHygieneFile) {
    $hygiene = Read-JsonFile -Path $FixtureHygieneFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-task-hygiene-report.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    $hygiene = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-BoolProp -Object $hygiene -Name "ok" -Default $false) -and -not (Get-Prop -Object $hygiene -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      total_tasks = 0
      failed_unrecovered = 0
      blocked = 0
      needs_evidence = 0
      stale_leases = 0
      stale_claims = 0
      safe_requeue_candidates_count = 0
      evidence_repair_candidates_count = 0
      archive_or_keep_blocked_candidates_count = 0
      unsafe_to_requeue_candidates_count = 0
      expected_active_pilot_task = $false
      active_task_id = $null
      active_task_allowed_for_goal_319_pilot = $false
      token_printed = Get-BoolProp -Object $hygiene -Name "token_printed"
      safety = Get-Prop -Object $hygiene -Name "safety"
    }
  }
  $pilotClassification = @((Get-Prop -Object $hygiene -Name "task_classifications" -Default @()) | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq "start-one-apply-pilot-docs-001" } | Select-Object -First 1)
  $pilotStatus = if ($pilotClassification) { [string](Get-Prop -Object $pilotClassification[0] -Name "status" -Default "") } else { "" }
  $pilotHygieneStatus = if ($pilotClassification) { [string](Get-Prop -Object $pilotClassification[0] -Name "hygiene_status" -Default "") } else { "" }
  $pilotClass = if ($pilotClassification) { [string](Get-Prop -Object $pilotClassification[0] -Name "classification" -Default "") } else { "" }
  $expectedActivePilot = ($pilotStatus -eq "queued" -and $pilotHygieneStatus -eq "active_ok" -and $pilotClass -eq "not-residue")
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $hygiene -Name "ok" -Default $true
    total_tasks = Get-CountProp -Object $hygiene -Name "total_tasks"
    failed_unrecovered = Get-CountProp -Object $hygiene -Name "failed_unrecovered"
    blocked = Get-CountProp -Object $hygiene -Name "blocked"
    needs_evidence = Get-CountProp -Object $hygiene -Name "needs_evidence"
    stale_leases = Get-CountProp -Object $hygiene -Name "stale_leases"
    stale_claims = Get-CountProp -Object $hygiene -Name "stale_claims"
    safe_requeue_candidates_count = @((Get-Prop -Object $hygiene -Name "safe_requeue_candidates" -Default @())).Count
    evidence_repair_candidates_count = @((Get-Prop -Object $hygiene -Name "evidence_repair_candidates" -Default @())).Count
    archive_or_keep_blocked_candidates_count = @((Get-Prop -Object $hygiene -Name "archive_or_keep_blocked_candidates" -Default @())).Count
    unsafe_to_requeue_candidates_count = @((Get-Prop -Object $hygiene -Name "unsafe_to_requeue_candidates" -Default @())).Count
    expected_active_pilot_task = $expectedActivePilot
    active_task_id = if ($expectedActivePilot) { "start-one-apply-pilot-docs-001" } else { $null }
    active_task_allowed_for_goal_319_pilot = $expectedActivePilot
    token_printed = Get-BoolProp -Object $hygiene -Name "token_printed"
    safety = Get-Prop -Object $hygiene -Name "safety"
  }
}

function Get-HygieneApplyProbe {
  if ($FixtureHygieneApplyFile) {
    $apply = Read-JsonFile -Path $FixtureHygieneApplyFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-task-hygiene-apply.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($FixtureHygieneFile) { $args += @("-FixtureHygieneFile", $FixtureHygieneFile) }
    $apply = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-BoolProp -Object $apply -Name "ok" -Default $false) -and -not (Get-Prop -Object $apply -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      mode = "preview"
      evidence_repair_actions_count = 0
      archive_or_keep_blocked_actions_count = 0
      unsafe_to_requeue_exclusion_actions_count = 0
      residual_warnings = @("task_hygiene_apply_preview_unavailable")
      token_printed = Get-BoolProp -Object $apply -Name "token_printed"
      safety = Get-Prop -Object $apply -Name "safety"
    }
  }
  $planned = Get-Prop -Object $apply -Name "planned_actions"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $apply -Name "ok" -Default $true
    mode = [string](Get-Prop -Object $apply -Name "mode" -Default "preview")
    evidence_repair_actions_count = @((Get-Prop -Object $planned -Name "evidence_repair_actions" -Default @())).Count
    archive_or_keep_blocked_actions_count = @((Get-Prop -Object $planned -Name "archive_or_keep_blocked_actions" -Default @())).Count
    unsafe_to_requeue_exclusion_actions_count = @((Get-Prop -Object $planned -Name "unsafe_to_requeue_exclusion_actions" -Default @())).Count
    residual_warnings = @((Get-Prop -Object $apply -Name "residual_warnings" -Default @()) | ForEach-Object { [string]$_ })
    recommended_next_safe_action = [string](Get-Prop -Object $apply -Name "recommended_next_safe_action" -Default "")
    token_printed = Get-BoolProp -Object $apply -Name "token_printed"
    safety = Get-Prop -Object $apply -Name "safety"
  }
}

function Get-NotificationDryRunProbe {
  if ($FixtureNotificationReadinessFile) {
    $notification = Read-JsonFile -Path $FixtureNotificationReadinessFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-notification-readiness.ps1"),
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-DryRun",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    $notification = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-Prop -Object $notification -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      status = "unavailable"
      dry_run = $true
      blocker_notice_supported = $false
      real_provider_count = 0
      real_ready_provider_count = 0
      dry_run_safe_provider_count = 0
      provider_configuration_status = "unavailable"
      bootstrap_dry_run_available = $false
      real_send_performed = $false
      raw_notification_payload_included = $false
      credential_values_exposed = $false
      token_printed = Get-BoolProp -Object $notification -Name "token_printed"
    }
  }
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $notification -Name "ok" -Default $false
    status = [string](Get-Prop -Object $notification -Name "status" -Default "unknown")
    dry_run = Get-BoolProp -Object $notification -Name "dry_run" -Default $true
    provider_count = Get-CountProp -Object $notification -Name "provider_count"
    ready_provider_count = Get-CountProp -Object $notification -Name "ready_provider_count"
    real_provider_count = Get-CountProp -Object $notification -Name "real_provider_count"
    real_ready_provider_count = Get-CountProp -Object $notification -Name "real_ready_provider_count"
    dry_run_safe_provider_count = Get-CountProp -Object $notification -Name "dry_run_safe_provider_count"
    provider_configuration_status = [string](Get-Prop -Object $notification -Name "provider_configuration_status" -Default "unknown")
    bootstrap_dry_run_available = Get-BoolProp -Object $notification -Name "bootstrap_dry_run_available"
    blocker_notice_supported = Get-BoolProp -Object $notification -Name "blocker_notice_supported"
    real_send_performed = Get-BoolProp -Object $notification -Name "real_send_performed"
    raw_notification_payload_included = Get-BoolProp -Object $notification -Name "raw_notification_payload_included"
    credential_values_exposed = Get-BoolProp -Object $notification -Name "credential_values_exposed"
    token_printed = Get-BoolProp -Object $notification -Name "token_printed"
  }
}

function Get-ExecutionSecondGateProbe {
  if ($FixtureExecutionSecondGateFile) {
    $gate = Read-JsonFile -Path $FixtureExecutionSecondGateFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-execution-second-gate-readiness.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    $gate = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-Prop -Object $gate -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      status = "unavailable"
      allowed_preview_only = $false
      allowed_execution = $false
      project_control_state = "unknown"
      hermes_tool_execution_risk = $true
      second_gate_configured = $false
      execution_forbidden = $true
      token_printed = Get-BoolProp -Object $gate -Name "token_printed"
    }
  }
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $gate -Name "ok" -Default $true
    status = [string](Get-Prop -Object $gate -Name "status" -Default "unknown")
    allowed_preview_only = Get-BoolProp -Object $gate -Name "allowed_preview_only"
    allowed_execution = Get-BoolProp -Object $gate -Name "allowed_execution"
    project_control_state = [string](Get-Prop -Object $gate -Name "project_control_state" -Default "unknown")
    hermes_tool_execution_risk = Get-BoolProp -Object $gate -Name "hermes_tool_execution_risk"
    second_gate_configured = Get-BoolProp -Object $gate -Name "second_gate_configured"
    preview_blockers = @((Get-Prop -Object $gate -Name "preview_blockers" -Default @()) | ForEach-Object { [string]$_ })
    execution_forbidden = (-not (Get-BoolProp -Object $gate -Name "allowed_execution"))
    recommended_next_safe_action = [string](Get-Prop -Object $gate -Name "recommended_next_safe_action" -Default "")
    token_printed = Get-BoolProp -Object $gate -Name "token_printed"
  }
}

function Get-StartOnePreviewProbe {
  if ($FixtureStartOnePreviewFile) {
    $preview = Read-JsonFile -Path $FixtureStartOnePreviewFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-start-one-preview.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    if ($FixtureHygieneFile) { $args += @("-FixtureHygieneFile", $FixtureHygieneFile) }
    if ($FixtureExecutionSecondGateFile) { $args += @("-FixtureSecondGateFile", $FixtureExecutionSecondGateFile) }
    $preview = Invoke-ChildJson -Arguments $args -AllowNonZero
  }
  if (-not (Get-Prop -Object $preview -Name "schema")) {
    return [pscustomobject]@{
      available = $false
      ok = $false
      status = "unavailable"
      selected_candidate = $null
      would_claim = $false
      would_run_codex = $false
      would_unpause_project_control = $false
      token_printed = Get-BoolProp -Object $preview -Name "token_printed"
    }
  }
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $preview -Name "ok" -Default $true
    status = [string](Get-Prop -Object $preview -Name "status" -Default "unknown")
    selected_candidate = Get-Prop -Object $preview -Name "selected_candidate"
    candidate_pool_summary = Get-Prop -Object $preview -Name "candidate_pool_summary"
    excluded_tasks_summary = Get-Prop -Object $preview -Name "excluded_tasks_summary"
    would_claim = Get-BoolProp -Object $preview -Name "would_claim"
    would_run_codex = Get-BoolProp -Object $preview -Name "would_run_codex"
    would_unpause_project_control = Get-BoolProp -Object $preview -Name "would_unpause_project_control"
    recommended_next_safe_action = [string](Get-Prop -Object $preview -Name "recommended_next_safe_action" -Default "")
    token_printed = Get-BoolProp -Object $preview -Name "token_printed"
  }
}

function Get-PilotSeedProbe {
  if ($FixturePilotSeedFile) {
    $seed = Read-JsonFile -Path $FixturePilotSeedFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-seed-start-one-pilot-task.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $seed = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        mode = "preview"
        pilot_task_id = "start-one-apply-pilot-docs-001"
        pilot_task_exists = $false
        would_create_task = $false
        token_printed = $false
      }
    }
  }
  $created = Get-Prop -Object $seed -Name "created_task"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $seed -Name "ok" -Default $true
    status = [string](Get-Prop -Object $seed -Name "status" -Default "unknown")
    mode = [string](Get-Prop -Object $seed -Name "mode" -Default "preview")
    pilot_task_id = [string](Get-Prop -Object $seed -Name "pilot_task_id" -Default "start-one-apply-pilot-docs-001")
    pilot_task_exists = ($null -ne $created -and [string](Get-Prop -Object $created -Name "status" -Default "") -in @("existing_safe_pilot_task", "existing_completed_pilot_task"))
    pilot_task_completed = ([string](Get-Prop -Object $created -Name "status" -Default "") -eq "existing_completed_pilot_task" -or [string](Get-Prop -Object $created -Name "task_status" -Default "") -eq "completed")
    would_create_task = Get-BoolProp -Object $seed -Name "would_create_task"
    token_printed = Get-BoolProp -Object $seed -Name "token_printed"
  }
}

function Get-StartOneApplyPilotProbe {
  if ($FixtureStartOneApplyPilotFile) {
    $applyPilot = Read-JsonFile -Path $FixtureStartOneApplyPilotFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-start-one-apply-pilot.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $applyPilot = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        mode = "preview"
        selected_task_id = $null
        pilot_task_exists = $false
        pilot_task_completed = $false
        old_residue_remains_excluded = $false
        token_printed = $false
      }
    }
  }
  $selected = Get-Prop -Object $applyPilot -Name "selected_candidate"
  $oldResidue = Get-Prop -Object $applyPilot -Name "old_residue_exclusion"
  $finalStatus = [string](Get-Prop -Object $applyPilot -Name "final_task_status" -Default "")
  $lookup = Get-Prop -Object $applyPilot -Name "pilot_task_lookup"
  $lookupTaskId = [string](Get-Prop -Object $lookup -Name "task_id" -Default "")
  $lookupStatus = [string](Get-Prop -Object $lookup -Name "status" -Default "")
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $applyPilot -Name "ok" -Default $true
    status = [string](Get-Prop -Object $applyPilot -Name "status" -Default "unknown")
    mode = [string](Get-Prop -Object $applyPilot -Name "mode" -Default "preview")
    selected_task_id = Get-Prop -Object $applyPilot -Name "selected_task_id"
    selected_candidate = $selected
    pilot_task_exists = ($null -ne $selected -or [string](Get-Prop -Object $applyPilot -Name "selected_task_id" -Default "") -eq "start-one-apply-pilot-docs-001" -or $lookupTaskId -eq "start-one-apply-pilot-docs-001")
    pilot_task_completed = ($finalStatus -eq "completed" -or $lookupStatus -eq "completed")
    pilot_task_terminal_status = if ($lookupStatus) { $lookupStatus } else { $finalStatus }
    old_residue_remains_excluded = Get-BoolProp -Object $oldResidue -Name "no_old_residue_eligible" -Default $false
    unsafe_to_requeue_tasks_excluded = Get-CountProp -Object $oldResidue -Name "unsafe_to_requeue_tasks_excluded"
    blocked_historical_tasks_excluded = Get-CountProp -Object $oldResidue -Name "blocked_historical_tasks_excluded"
    remote_docs_exec_pilot_001_excluded = Get-BoolProp -Object $oldResidue -Name "remote_docs_exec_pilot_001_excluded"
    would_claim = Get-BoolProp -Object (Get-Prop -Object $applyPilot -Name "claim_result") -Name "would_claim"
    codex_run_called = Get-BoolProp -Object (Get-Prop -Object $applyPilot -Name "execution_result") -Name "codex_run_called"
    project_control_unpaused = Get-BoolProp -Object (Get-Prop -Object $applyPilot -Name "project_control") -Name "project_control_unpaused"
    run_until_hold_called = Get-BoolProp -Object (Get-Prop -Object $applyPilot -Name "forbidden_actions") -Name "run_until_hold_called"
    token_printed = Get-BoolProp -Object $applyPilot -Name "token_printed"
  }
}

function Get-StartOneHoldReportProbe {
  if ($FixtureStartOneHoldReportFile) {
    $hold = Read-JsonFile -Path $FixtureStartOneHoldReportFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-start-one-hold-report.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $hold = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        latest_pilot_execution_terminal_state = "not_reported"
        latest_hold_reason = "hold_report_unavailable"
        evidence_present = $false
        token_printed = $false
      }
    }
  }
  $evidence = Get-Prop -Object $hold -Name "evidence_summary"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $hold -Name "ok" -Default $true
    status = [string](Get-Prop -Object $hold -Name "current_status" -Default "unknown")
    task_id = [string](Get-Prop -Object $hold -Name "task_id" -Default "start-one-apply-pilot-docs-001")
    latest_pilot_execution_terminal_state = [string](Get-Prop -Object $hold -Name "terminal_state" -Default "not_reported")
    latest_hold_reason = [string](Get-Prop -Object $hold -Name "hold_reason" -Default "")
    evidence_present = Get-BoolProp -Object $hold -Name "evidence_present"
    evidence_safety_summary = [pscustomobject]@{
      schema = [string](Get-Prop -Object $evidence -Name "schema" -Default "not_reported")
      files_changed = @((Get-Prop -Object $evidence -Name "files_changed" -Default @()) | ForEach-Object { [string]$_ })
      prompt_content_included = Get-BoolProp -Object $evidence -Name "prompt_content_included"
      log_content_included = Get-BoolProp -Object $evidence -Name "log_content_included"
      credential_values_included = Get-BoolProp -Object $evidence -Name "credential_values_included"
    }
    old_residue_stayed_excluded = (-not (Get-BoolProp -Object $hold -Name "old_residue_selected"))
    project_control_stayed_paused = (-not (Get-BoolProp -Object $hold -Name "project_control_unpaused"))
    run_until_hold_stayed_unavailable = (-not (Get-BoolProp -Object $hold -Name "run_until_hold_called"))
    manual_operator_review_needed = Get-BoolProp -Object $hold -Name "manual_operator_review_needed"
    recommended_next_safe_action = [string](Get-Prop -Object $hold -Name "recommended_next_safe_action" -Default "")
    token_printed = Get-BoolProp -Object $hold -Name "token_printed"
  }
}

function Get-RunUntilHoldPilotSeedProbe {
  if ($FixtureRunUntilHoldPilotSeedFile) {
    $seed = Read-JsonFile -Path $FixtureRunUntilHoldPilotSeedFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-seed-run-until-hold-pilot-tasks.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $seed = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        mode = "preview"
        would_create_count = 0
        pilot_task_count = 0
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $seed -Name "ok" -Default $true
    status = if (@((Get-Prop -Object $seed -Name "blockers" -Default @())).Count -gt 0) { "blocked" } elseif (@((Get-Prop -Object $seed -Name "created_tasks" -Default @())).Count -gt 0) { "existing_or_created" } else { "preview_ready" }
    mode = [string](Get-Prop -Object $seed -Name "mode" -Default "preview")
    would_create_count = @((Get-Prop -Object $seed -Name "would_create" -Default @())).Count
    pilot_task_count = @((Get-Prop -Object $seed -Name "created_tasks" -Default @())).Count
    token_printed = Get-BoolProp -Object $seed -Name "token_printed"
  }
}

function Get-RunUntilHoldBoundedProbe {
  if ($FixtureRunUntilHoldBoundedFile) {
    $bounded = Read-JsonFile -Path $FixtureRunUntilHoldBoundedFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-run-until-hold-bounded.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $bounded = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        selected_candidate_count = 0
        executed_task_count = 0
        latest_stop_reason = "bounded_run_until_hold_unavailable"
        latest_hold_reason = "bounded_run_until_hold_unavailable"
        evidence_present = $false
        old_residue_excluded = $false
        project_control_stayed_paused = $false
        run_until_hold_bounded = $false
        token_printed = $false
      }
    }
  }
  $oldResidue = Get-Prop -Object $bounded -Name "old_residue_exclusion"
  $projectControl = Get-Prop -Object $bounded -Name "project_control"
  $forbiddenActions = Get-Prop -Object $bounded -Name "forbidden_actions"
  $evidence = Get-Prop -Object $bounded -Name "evidence_summary"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $bounded -Name "ok" -Default $true
    status = [string](Get-Prop -Object $bounded -Name "stop_reason" -Default "unknown")
    selected_candidate_count = @((Get-Prop -Object $bounded -Name "selected_candidates" -Default @())).Count
    executed_task_count = [int](Get-Prop -Object $bounded -Name "executed_task_count" -Default 0)
    latest_stop_reason = [string](Get-Prop -Object $bounded -Name "stop_reason" -Default "unknown")
    latest_hold_reason = [string](Get-Prop -Object $bounded -Name "hold_reason" -Default "")
    evidence_present = Get-BoolProp -Object $evidence -Name "evidence_present" -Default $true
    old_residue_excluded = (Get-BoolProp -Object $oldResidue -Name "no_old_residue_eligible" -Default $true)
    project_control_stayed_paused = (-not (Get-BoolProp -Object $projectControl -Name "project_control_unpaused"))
    run_until_hold_bounded = (-not (Get-BoolProp -Object $forbiddenActions -Name "daemon_implemented") -and -not (Get-BoolProp -Object $forbiddenActions -Name "recursive_run_until_hold"))
    token_printed = Get-BoolProp -Object $bounded -Name "token_printed"
  }
}

function Get-RunUntilHoldReportProbe {
  if ($FixtureRunUntilHoldReportFile) {
    $report = Read-JsonFile -Path $FixtureRunUntilHoldReportFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-run-until-hold-report.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $report = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        latest_bounded_run_status = "unavailable"
        stop_reason = "run_until_hold_report_unavailable"
        hold_reason = "run_until_hold_report_unavailable"
        evidence_present = $false
        old_residue_excluded = $false
        project_control_stayed_paused = $false
        run_until_hold_stayed_bounded = $false
        token_printed = $false
      }
    }
  }
  $proof = Get-Prop -Object $report -Name "unsafe_selection_proof"
  $evidence = Get-Prop -Object $report -Name "evidence_summary"
  [pscustomobject]@{
    available = $true
    ok = Get-BoolProp -Object $report -Name "ok" -Default $true
    latest_bounded_run_status = [string](Get-Prop -Object $report -Name "latest_bounded_run_status" -Default "unknown")
    stop_reason = [string](Get-Prop -Object $report -Name "stop_reason" -Default "unknown")
    hold_reason = [string](Get-Prop -Object $report -Name "hold_reason" -Default "")
    evidence_present = Get-BoolProp -Object $evidence -Name "evidence_present" -Default $true
    old_residue_excluded = (Get-BoolProp -Object $proof -Name "no_old_residue_eligible" -Default $true)
    project_control_stayed_paused = Get-BoolProp -Object $report -Name "project_control_stayed_paused" -Default $true
    run_until_hold_stayed_bounded = Get-BoolProp -Object $report -Name "run_until_hold_stayed_bounded" -Default $true
    recommended_next_safe_action = [string](Get-Prop -Object $report -Name "recommended_next_safe_action" -Default "")
    token_printed = Get-BoolProp -Object $report -Name "token_printed"
  }
}

function Get-CampaignTaskCompilerProbe {
  if ($FixtureCampaignTaskCompilerFile) {
    $compiler = Read-JsonFile -Path $FixtureCampaignTaskCompilerFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-compile-campaign-tasks.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Preview",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $compiler = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        campaign_id = "campaign-policy-compiler-pilot-001"
        generated_task_count = 0
        rejected_unsafe_item_count = 0
        old_residue_excluded = $false
        project_control_stayed_paused = $false
        recommended_next_safe_action = "Fix campaign compiler probe before generating campaign tasks."
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $compiler -Name "ok" -Default $false)
    status = if ([bool](Get-Prop -Object $compiler -Name "ok" -Default $false)) { "preview_ready" } else { "blocked" }
    campaign_id = [string](Get-Prop -Object $compiler -Name "campaign_id" -Default "campaign-policy-compiler-pilot-001")
    generated_task_count = [int](Get-Prop -Object $compiler -Name "generated_task_count" -Default @((Get-Prop -Object $compiler -Name "generated_tasks" -Default @())).Count)
    rejected_unsafe_item_count = @((Get-Prop -Object $compiler -Name "rejected_items" -Default @())).Count
    old_residue_excluded = -not [bool](Get-Prop -Object (Get-Prop -Object $compiler -Name "old_residue_exclusion") -Name "old_residue_selected" -Default $false)
    project_control_stayed_paused = -not [bool](Get-Prop -Object (Get-Prop -Object $compiler -Name "forbidden_actions") -Name "project_control_unpaused" -Default $false)
    recommended_next_safe_action = "Compile safe campaign tasks only, then use bounded run-until-hold with the campaign selector."
    token_printed = [bool](Get-Prop -Object $compiler -Name "token_printed" -Default $false)
  }
}

function Get-CampaignPolicyReportProbe {
  if ($FixtureCampaignPolicyReportFile) {
    $policy = Read-JsonFile -Path $FixtureCampaignPolicyReportFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-campaign-policy-report.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $policy = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        campaign_status = "unavailable"
        safe_task_count = 0
        rejected_task_count = 0
        evidence_present = $false
        old_residue_excluded = $false
        project_control_stayed_paused = $false
        run_until_hold_stayed_bounded = $false
        recommended_next_safe_action = "Fix campaign policy report probe before continuing."
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $policy -Name "ok" -Default $false)
    campaign_status = [string](Get-Prop -Object $policy -Name "campaign_status" -Default "unknown")
    safe_task_count = [int](Get-Prop -Object $policy -Name "safe_task_count" -Default 0)
    rejected_task_count = [int](Get-Prop -Object $policy -Name "rejected_task_count" -Default 0)
    evidence_present = [bool](Get-Prop -Object (Get-Prop -Object $policy -Name "evidence_state") -Name "evidence_present" -Default $true)
    old_residue_excluded = [bool](Get-Prop -Object $policy -Name "old_residue_excluded" -Default (-not [bool](Get-Prop -Object $policy -Name "old_residue_selected" -Default $false)))
    project_control_stayed_paused = [bool](Get-Prop -Object $policy -Name "project_control_stayed_paused" -Default $true)
    run_until_hold_stayed_bounded = [bool](Get-Prop -Object $policy -Name "run_until_hold_stayed_bounded" -Default $true)
    recommended_next_safe_action = [string](Get-Prop -Object $policy -Name "recommended_next_safe_action" -Default "Use bounded run-until-hold with the campaign selector; keep project_control paused.")
    token_printed = [bool](Get-Prop -Object $policy -Name "token_printed" -Default $false)
  }
}

function Get-OperatorNotificationReadinessProbe {
  if ($FixtureOperatorNotificationReadinessFile) {
    $notification = Read-JsonFile -Path $FixtureOperatorNotificationReadinessFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-operator-notification-readiness.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-DryRun",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $notification = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        status = "unavailable"
        dry_run = $true
        report_delivery_supported = $false
        review_gate_supported = $false
        real_provider_configured = $false
        bootstrap_dry_run_available = $false
        real_send_performed = $false
        raw_notification_payload_included = $false
        credential_values_exposed = $false
        recommended_next_safe_action = "Fix operator notification readiness before continuing."
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $notification -Name "ok" -Default $false)
    status = [string](Get-Prop -Object $notification -Name "status" -Default "unknown")
    dry_run = Get-BoolProp -Object $notification -Name "dry_run" -Default $true
    provider_count = Get-CountProp -Object $notification -Name "provider_count"
    ready_provider_count = Get-CountProp -Object $notification -Name "ready_provider_count"
    real_ready_provider_count = Get-CountProp -Object $notification -Name "real_ready_provider_count"
    dry_run_safe_provider_count = Get-CountProp -Object $notification -Name "dry_run_safe_provider_count"
    report_delivery_supported = Get-BoolProp -Object $notification -Name "report_delivery_supported"
    review_gate_supported = Get-BoolProp -Object $notification -Name "review_gate_supported"
    real_provider_configured = Get-BoolProp -Object $notification -Name "real_provider_configured"
    bootstrap_dry_run_available = Get-BoolProp -Object $notification -Name "bootstrap_dry_run_available"
    real_send_performed = Get-BoolProp -Object $notification -Name "real_send_performed"
    raw_notification_payload_included = Get-BoolProp -Object $notification -Name "raw_notification_payload_included"
    credential_values_exposed = Get-BoolProp -Object $notification -Name "credential_values_exposed"
    recommended_next_safe_action = [string](Get-Prop -Object $notification -Name "recommended_next_safe_action" -Default "Use dry-run operator report delivery.")
    token_printed = [bool](Get-Prop -Object $notification -Name "token_printed" -Default $false)
  }
}

function Get-ReviewGateProbe {
  if ($FixtureReviewGateFile) {
    $gate = Read-JsonFile -Path $FixtureReviewGateFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-review-gate.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $gate = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        gate_status = "blocked"
        allowed_preview = $false
        allowed_bounded_run = $false
        allowed_unbounded_run = $false
        allowed_daemon = $false
        needs_operator_review = $true
        notification_available = $false
        old_residue_excluded = $false
        project_control_paused = $false
        recommended_next_safe_action = "Fix review gate probe before continuing."
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $gate -Name "ok" -Default $false)
    gate_status = [string](Get-Prop -Object $gate -Name "gate_status" -Default "unknown")
    allowed_preview = Get-BoolProp -Object $gate -Name "allowed_preview"
    allowed_bounded_run = Get-BoolProp -Object $gate -Name "allowed_bounded_run"
    allowed_unbounded_run = Get-BoolProp -Object $gate -Name "allowed_unbounded_run"
    allowed_daemon = Get-BoolProp -Object $gate -Name "allowed_daemon"
    needs_operator_review = Get-BoolProp -Object $gate -Name "needs_operator_review"
    notification_available = Get-BoolProp -Object $gate -Name "notification_available"
    old_residue_excluded = Get-BoolProp -Object $gate -Name "old_residue_excluded"
    project_control_paused = Get-BoolProp -Object $gate -Name "project_control_paused"
    recommended_next_safe_action = [string](Get-Prop -Object $gate -Name "recommended_next_safe_action" -Default "")
    token_printed = [bool](Get-Prop -Object $gate -Name "token_printed" -Default $false)
  }
}

function Get-OperatorReportProbe {
  if ($FixtureOperatorReportFile) {
    $operator = Read-JsonFile -Path $FixtureOperatorReportFile
  } else {
    $args = @(
      "-File", (Join-Path $PSScriptRoot "skybridge-operator-report.ps1"),
      "-ProjectId", $ProjectId,
      "-TimeoutSeconds", [string]$TimeoutSeconds,
      "-IncludeCampaign",
      "-IncludeBoundedRun",
      "-IncludeHold",
      "-Json"
    )
    if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    try {
      $operator = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        report_kind = "current-state"
        campaign_included = $false
        bounded_run_included = $false
        hold_included = $false
        evidence_present = $false
        old_residue_excluded = $false
        project_control_unpaused = $true
        run_until_hold_recursive = $true
        recommended_next_safe_action = "Fix operator report probe before continuing."
        token_printed = $false
      }
    }
  }
  $campaignSummary = Get-Prop -Object $operator -Name "campaign_summary"
  $boundedSummary = Get-Prop -Object $operator -Name "bounded_run_summary"
  $holdSummary = Get-Prop -Object $operator -Name "hold_summary"
  $evidence = Get-Prop -Object $operator -Name "evidence_summary"
  $oldResidue = Get-Prop -Object $operator -Name "old_residue_summary"
  $safety = Get-Prop -Object $operator -Name "safety_summary"
  [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $operator -Name "ok" -Default $false)
    report_kind = [string](Get-Prop -Object $operator -Name "report_kind" -Default "current-state")
    campaign_included = Get-BoolProp -Object $campaignSummary -Name "included"
    bounded_run_included = Get-BoolProp -Object $boundedSummary -Name "included"
    hold_included = Get-BoolProp -Object $holdSummary -Name "included"
    evidence_present = Get-BoolProp -Object $evidence -Name "evidence_present"
    old_residue_excluded = Get-BoolProp -Object $oldResidue -Name "old_residue_excluded"
    project_control_unpaused = Get-BoolProp -Object $safety -Name "project_control_unpaused"
    run_until_hold_recursive = Get-BoolProp -Object $safety -Name "run_until_hold_recursive"
    recommended_next_safe_action = [string](Get-Prop -Object $operator -Name "recommended_next_safe_action" -Default "")
    token_printed = [bool](Get-Prop -Object $operator -Name "token_printed" -Default $false)
  }
}

function Test-AnyTrueFlag {
  param($Object, [string[]]$Names)
  if ($null -eq $Object) { return $false }
  foreach ($name in $Names) {
    if (Get-BoolProp -Object $Object -Name $name) { return $true }
  }
  $safety = Get-Prop -Object $Object -Name "safety"
  if ($null -ne $safety) {
    foreach ($name in $Names) {
      if (Get-BoolProp -Object $safety -Name $name) { return $true }
    }
  }
  return $false
}

function New-MarkdownReport {
  param($Report)
  $blockers = if (@($Report.readiness.blockers).Count -gt 0) { @($Report.readiness.blockers) -join ", " } else { "none" }
  $warnings = if (@($Report.readiness.warnings).Count -gt 0) { @($Report.readiness.warnings) -join ", " } else { "none" }
  $forbidden = @($Report.forbidden_actions.PSObject.Properties | Where-Object { $_.Value -eq $false } | ForEach-Object { "$($_.Name)=false" }) -join ", "
  @(
    "# Self-Bootstrap Convergence"
    ""
    "- status: $($Report.status)"
    "- blockers: $blockers"
    "- warnings: $warnings"
    "- local: branch=$($Report.local.branch), clean=$($Report.local.clean), head=$($Report.local.head_commit)"
    "- cloud: commit=$($Report.cloud.commit_sha), aligned=$($Report.cloud.commit_aligned), route_parity_ok=$($Report.cloud.route_parity_ok), deploy_evidence_ok=$($Report.cloud.deploy_evidence_ok)"
    "- worker: heartbeat_requested=$($Report.heartbeat.requested), refreshed=$($Report.heartbeat.refreshed), online=$($Report.heartbeat.worker_online_after), workers_online=$($Report.readiness.workers_online)"
    "- hygiene: total=$($Report.hygiene.total_tasks), failed_unrecovered=$($Report.hygiene.failed_unrecovered), blocked=$($Report.hygiene.blocked), needs_evidence=$($Report.hygiene.needs_evidence), safe_requeue=$($Report.hygiene.safe_requeue_candidates_count), evidence_repair=$($Report.hygiene.evidence_repair_candidates_count), archive_or_keep_blocked=$($Report.hygiene.archive_or_keep_blocked_candidates_count), unsafe_requeue=$($Report.hygiene.unsafe_to_requeue_candidates_count)"
    "- hygiene_apply_preview: available=$($Report.hygiene_apply_preview.available), mode=$($Report.hygiene_apply_preview.mode), evidence=$($Report.hygiene_apply_preview.evidence_repair_actions_count), blocked=$($Report.hygiene_apply_preview.archive_or_keep_blocked_actions_count), excluded=$($Report.hygiene_apply_preview.unsafe_to_requeue_exclusion_actions_count)"
    "- notification_readiness: available=$($Report.notification_readiness.available), status=$($Report.notification_readiness.status), dry_run=$($Report.notification_readiness.dry_run), real_send_performed=$($Report.notification_readiness.real_send_performed)"
    "- execution_second_gate: available=$($Report.execution_second_gate.available), status=$($Report.execution_second_gate.status), preview_only=$($Report.execution_second_gate.allowed_preview_only), execution=$($Report.execution_second_gate.allowed_execution), project_control=$($Report.execution_second_gate.project_control_state)"
    "- start_one_preview: available=$($Report.start_one_preview.available), status=$($Report.start_one_preview.status), selected_candidate=$(if ($Report.start_one_preview.selected_candidate) { $Report.start_one_preview.selected_candidate.task_id } else { 'none' }), would_claim=$($Report.start_one_preview.would_claim), would_run_codex=$($Report.start_one_preview.would_run_codex)"
    "- pilot_seed: available=$($Report.pilot_seed.available), status=$($Report.pilot_seed.status), exists=$($Report.pilot_seed.pilot_task_exists), would_create=$($Report.pilot_seed.would_create_task)"
    "- start_one_apply_pilot: available=$($Report.start_one_apply_pilot.available), status=$($Report.start_one_apply_pilot.status), selected=$($Report.start_one_apply_pilot.selected_task_id), completed=$($Report.start_one_apply_pilot.pilot_task_completed), old_residue_excluded=$($Report.start_one_apply_pilot.old_residue_remains_excluded)"
    "- start_one_failure_semantics: available=$($Report.start_one_failure_semantics.available), terminal=$($Report.start_one_failure_semantics.latest_pilot_execution_terminal_state), hold_reason=$($Report.start_one_failure_semantics.latest_hold_reason), evidence_present=$($Report.start_one_failure_semantics.evidence_present), manual_review=$($Report.start_one_failure_semantics.manual_operator_review_needed)"
    "- bounded_pilot_seed: available=$($Report.bounded_pilot_seed.available), status=$($Report.bounded_pilot_seed.status), would_create=$($Report.bounded_pilot_seed.would_create_count), pilot_tasks=$($Report.bounded_pilot_seed.pilot_task_count)"
    "- bounded_run_until_hold: available=$($Report.bounded_run_until_hold.available), stop=$($Report.bounded_run_until_hold.latest_stop_reason), hold=$($Report.bounded_run_until_hold.latest_hold_reason), selected=$($Report.bounded_run_until_hold.selected_candidate_count), executed=$($Report.bounded_run_until_hold.executed_task_count), evidence=$($Report.bounded_run_until_hold.evidence_present), old_residue_excluded=$($Report.bounded_run_until_hold.old_residue_excluded), bounded=$($Report.bounded_run_until_hold.run_until_hold_bounded)"
    "- bounded_run_until_hold_report: available=$($Report.bounded_run_until_hold_report.available), status=$($Report.bounded_run_until_hold_report.latest_bounded_run_status), evidence=$($Report.bounded_run_until_hold_report.evidence_present), project_control_paused=$($Report.bounded_run_until_hold_report.project_control_stayed_paused)"
    "- campaign_task_compiler: available=$($Report.campaign_task_compiler.available), status=$($Report.campaign_task_compiler.status), campaign=$($Report.campaign_task_compiler.campaign_id), generated=$($Report.campaign_task_compiler.generated_task_count), rejected=$($Report.campaign_task_compiler.rejected_unsafe_item_count), old_residue_excluded=$($Report.campaign_task_compiler.old_residue_excluded)"
    "- campaign_policy_report: available=$($Report.campaign_policy_report.available), status=$($Report.campaign_policy_report.campaign_status), safe_tasks=$($Report.campaign_policy_report.safe_task_count), rejected=$($Report.campaign_policy_report.rejected_task_count), evidence=$($Report.campaign_policy_report.evidence_present), bounded=$($Report.campaign_policy_report.run_until_hold_stayed_bounded)"
    "- operator_report: available=$($Report.operator_report.available), ok=$($Report.operator_report.ok), campaign_included=$($Report.operator_report.campaign_included), bounded_included=$($Report.operator_report.bounded_run_included), evidence=$($Report.operator_report.evidence_present)"
    "- operator_notification_readiness: available=$($Report.operator_notification_readiness.available), status=$($Report.operator_notification_readiness.status), dry_run=$($Report.operator_notification_readiness.dry_run), report_delivery=$($Report.operator_notification_readiness.report_delivery_supported), bootstrap=$($Report.operator_notification_readiness.bootstrap_dry_run_available), real_provider=$($Report.operator_notification_readiness.real_provider_configured)"
    "- review_gate: available=$($Report.review_gate.available), status=$($Report.review_gate.gate_status), preview=$($Report.review_gate.allowed_preview), bounded=$($Report.review_gate.allowed_bounded_run), operator_review=$($Report.review_gate.needs_operator_review)"
    "- execution_forbidden: $($Report.execution_forbidden)"
    "- can_start_one_false_reason: $($Report.can_start_one_false_reason)"
    "- deferred_execution_blockers: $(if ($Report.deferred_execution_blockers.Count -gt 0) { $Report.deferred_execution_blockers -join ', ' } else { 'none' })"
    "- forbidden_actions: $forbidden"
    "- next_safe_action: $($Report.recommended_next_safe_action)"
    "- token_printed: false"
    ""
  ) -join "`n"
}

$local = Get-LocalState
$version = Get-VersionProbe
$routeParity = Get-RouteParityProbe
$deployEvidence = Get-DeployEvidenceProbe -Commit ([string]$local.head_commit)
$heartbeat = Get-HeartbeatProbe
$readiness = Get-ReadinessProbe
$hygiene = Get-HygieneProbe
$hygieneApplyPreview = Get-HygieneApplyProbe
$notificationDryRun = Get-NotificationDryRunProbe
$executionSecondGate = Get-ExecutionSecondGateProbe
$startOnePreview = Get-StartOnePreviewProbe
$pilotSeed = Get-PilotSeedProbe
$startOneApplyPilot = Get-StartOneApplyPilotProbe
$startOneFailureSemantics = Get-StartOneHoldReportProbe
$boundedPilotSeed = Get-RunUntilHoldPilotSeedProbe
$boundedRunUntilHold = Get-RunUntilHoldBoundedProbe
$boundedRunUntilHoldReport = Get-RunUntilHoldReportProbe
$campaignTaskCompiler = Get-CampaignTaskCompilerProbe
$campaignPolicyReport = Get-CampaignPolicyReportProbe
$operatorNotificationReadiness = Get-OperatorNotificationReadinessProbe
$reviewGate = Get-ReviewGateProbe
$operatorReport = Get-OperatorReportProbe

$cloudCommit = [string](Get-Prop -Object $version -Name "commit_sha")
$commitAligned = (-not [string]::IsNullOrWhiteSpace($cloudCommit) -and -not [string]::IsNullOrWhiteSpace([string]$local.head_commit) -and $cloudCommit -eq [string]$local.head_commit)
$routeParityOk = ([bool]$routeParity.ok -and [string]$routeParity.deployment_parity_status -eq "ok")
$deployEvidenceOk = [bool]$deployEvidence.ok

$forbidden = [pscustomobject]@{
  tasks_claimed = $false
  tasks_requeued = $false
  tasks_cancelled = $false
  tasks_archived = $false
  evidence_written = $false
  codex_run_called = $false
  queue_apply_called = $false
  campaign_metadata_advanced = $false
  project_control_unpaused = $false
  start_one_called = $false
  run_until_hold_called = $false
}

$unsafeFlagNames = @("tasks_claimed", "tasks_requeued", "tasks_cancelled", "tasks_archived", "evidence_written", "codex_run_called", "queue_apply_called", "campaign_metadata_advanced", "project_control_unpaused", "start_one_called", "run_until_hold_called", "mutated_server", "triggered_deploy", "created_tag")
$unsafeMutation = (
  (Test-AnyTrueFlag -Object $heartbeat -Names $unsafeFlagNames) -or
  (Test-AnyTrueFlag -Object $hygiene -Names $unsafeFlagNames) -or
  (Test-AnyTrueFlag -Object $deployEvidence -Names $unsafeFlagNames)
)

$tokenPrinted = (
  [bool]$version.token_printed -or
  [bool]$routeParity.token_printed -or
  [bool]$deployEvidence.token_printed -or
  [bool]$heartbeat.token_printed -or
  [bool]$readiness.token_printed -or
  [bool]$hygiene.token_printed -or
  [bool]$hygieneApplyPreview.token_printed -or
  [bool]$notificationDryRun.token_printed -or
  [bool]$executionSecondGate.token_printed -or
  [bool]$startOnePreview.token_printed -or
  [bool]$pilotSeed.token_printed -or
  [bool]$startOneApplyPilot.token_printed -or
  [bool]$startOneFailureSemantics.token_printed -or
  [bool]$boundedPilotSeed.token_printed -or
  [bool]$boundedRunUntilHold.token_printed -or
  [bool]$boundedRunUntilHoldReport.token_printed -or
  [bool]$campaignTaskCompiler.token_printed -or
  [bool]$campaignPolicyReport.token_printed -or
  [bool]$operatorNotificationReadiness.token_printed -or
  [bool]$reviewGate.token_printed -or
  [bool]$operatorReport.token_printed
)

$deferredExecutionBlockers = [System.Collections.Generic.List[string]]::new()
$nonBlockingPreviewBlockers = @("not_on_main", "worktree_dirty", "admin_escalation_unavailable")
$blockedReasons = [System.Collections.Generic.List[string]]::new()
if ([string]$local.branch -ne "main") { $deferredExecutionBlockers.Add("not_on_main") }
if (-not [bool]$local.clean) { $deferredExecutionBlockers.Add("worktree_dirty") }
if (-not [bool]$version.available) { $blockedReasons.Add("cloud_version_unavailable") }
if (-not $commitAligned) { $blockedReasons.Add("cloud_commit_mismatch") }
if (-not $routeParityOk) { $blockedReasons.Add("route_parity_failed") }
foreach ($blocker in @($readiness.blockers)) {
  if ([string]::IsNullOrWhiteSpace($blocker)) { continue }
  if ([string]$blocker -eq "active_tasks_present" -and [bool]$hygiene.active_task_allowed_for_goal_319_pilot) {
    continue
  }
  if ($nonBlockingPreviewBlockers -contains [string]$blocker) {
    if (-not $deferredExecutionBlockers.Contains($blocker)) { $deferredExecutionBlockers.Add($blocker) }
    continue
  }
  if (-not $blockedReasons.Contains($blocker)) { $blockedReasons.Add($blocker) }
}
if (-not [bool]$readiness.available -or [string]$readiness.status -eq "unknown" -or [string]$readiness.status -eq "unavailable") {
  if (-not $blockedReasons.Contains("self_bootstrap_readiness_unavailable")) { $blockedReasons.Add("self_bootstrap_readiness_unavailable") }
}
if (-not [bool]$hygiene.available) {
  if (-not $blockedReasons.Contains("task_hygiene_report_unavailable")) { $blockedReasons.Add("task_hygiene_report_unavailable") }
}
if (-not [bool]$hygieneApplyPreview.available) {
  if (-not $blockedReasons.Contains("task_hygiene_apply_preview_unavailable")) { $blockedReasons.Add("task_hygiene_apply_preview_unavailable") }
}
if (-not [bool]$notificationDryRun.available) {
  if (-not $blockedReasons.Contains("notification_readiness_unavailable")) { $blockedReasons.Add("notification_readiness_unavailable") }
}
if (-not [bool]$executionSecondGate.available) {
  if (-not $blockedReasons.Contains("execution_second_gate_unavailable")) { $blockedReasons.Add("execution_second_gate_unavailable") }
}
if (-not [bool]$startOnePreview.available) {
  if (-not $blockedReasons.Contains("start_one_preview_unavailable")) { $blockedReasons.Add("start_one_preview_unavailable") }
}
if ([bool]$notificationDryRun.real_send_performed -or [bool]$notificationDryRun.raw_notification_payload_included -or [bool]$notificationDryRun.credential_values_exposed) {
  if (-not $blockedReasons.Contains("notification_readiness_unsafe")) { $blockedReasons.Add("notification_readiness_unsafe") }
}
if ([bool]$startOnePreview.would_claim -or [bool]$startOnePreview.would_run_codex -or [bool]$startOnePreview.would_unpause_project_control) {
  if (-not $blockedReasons.Contains("start_one_preview_unsafe")) { $blockedReasons.Add("start_one_preview_unsafe") }
}
if ([bool]$startOneApplyPilot.project_control_unpaused -or [bool]$startOneApplyPilot.run_until_hold_called) {
  if (-not $blockedReasons.Contains("start_one_apply_pilot_unsafe")) { $blockedReasons.Add("start_one_apply_pilot_unsafe") }
}
if (-not [bool]$startOneFailureSemantics.available) {
  if (-not $blockedReasons.Contains("start_one_hold_report_unavailable")) { $blockedReasons.Add("start_one_hold_report_unavailable") }
}
if (-not [bool]$startOneFailureSemantics.old_residue_stayed_excluded -or -not [bool]$startOneFailureSemantics.project_control_stayed_paused -or -not [bool]$startOneFailureSemantics.run_until_hold_stayed_unavailable) {
  if (-not $blockedReasons.Contains("start_one_failure_semantics_unsafe")) { $blockedReasons.Add("start_one_failure_semantics_unsafe") }
}
if (-not [bool]$boundedPilotSeed.available) {
  if (-not $blockedReasons.Contains("bounded_pilot_seed_unavailable")) { $blockedReasons.Add("bounded_pilot_seed_unavailable") }
}
if (-not [bool]$boundedRunUntilHold.available) {
  if (-not $blockedReasons.Contains("bounded_run_until_hold_unavailable")) { $blockedReasons.Add("bounded_run_until_hold_unavailable") }
}
if (-not [bool]$boundedRunUntilHoldReport.available) {
  if (-not $blockedReasons.Contains("bounded_run_until_hold_report_unavailable")) { $blockedReasons.Add("bounded_run_until_hold_report_unavailable") }
}
if (-not [bool]$boundedRunUntilHold.old_residue_excluded -or -not [bool]$boundedRunUntilHold.project_control_stayed_paused -or -not [bool]$boundedRunUntilHold.run_until_hold_bounded) {
  if (-not $blockedReasons.Contains("bounded_run_until_hold_unsafe")) { $blockedReasons.Add("bounded_run_until_hold_unsafe") }
}
if (-not [bool]$boundedRunUntilHoldReport.old_residue_excluded -or -not [bool]$boundedRunUntilHoldReport.project_control_stayed_paused -or -not [bool]$boundedRunUntilHoldReport.run_until_hold_stayed_bounded) {
  if (-not $blockedReasons.Contains("bounded_run_until_hold_report_unsafe")) { $blockedReasons.Add("bounded_run_until_hold_report_unsafe") }
}
if (-not [bool]$campaignTaskCompiler.available) {
  if (-not $blockedReasons.Contains("campaign_task_compiler_unavailable")) { $blockedReasons.Add("campaign_task_compiler_unavailable") }
}
if (-not [bool]$campaignPolicyReport.available) {
  if (-not $blockedReasons.Contains("campaign_policy_report_unavailable")) { $blockedReasons.Add("campaign_policy_report_unavailable") }
}
if (-not [bool]$campaignTaskCompiler.old_residue_excluded -or -not [bool]$campaignTaskCompiler.project_control_stayed_paused) {
  if (-not $blockedReasons.Contains("campaign_task_compiler_unsafe")) { $blockedReasons.Add("campaign_task_compiler_unsafe") }
}
if (-not [bool]$campaignPolicyReport.old_residue_excluded -or -not [bool]$campaignPolicyReport.project_control_stayed_paused -or -not [bool]$campaignPolicyReport.run_until_hold_stayed_bounded) {
  if (-not $blockedReasons.Contains("campaign_policy_report_unsafe")) { $blockedReasons.Add("campaign_policy_report_unsafe") }
}
if (-not [bool]$operatorNotificationReadiness.available) {
  if (-not $blockedReasons.Contains("operator_notification_readiness_unavailable")) { $blockedReasons.Add("operator_notification_readiness_unavailable") }
}
if (-not [bool]$operatorNotificationReadiness.report_delivery_supported -or -not [bool]$operatorNotificationReadiness.review_gate_supported) {
  if (-not $blockedReasons.Contains("operator_notification_readiness_incomplete")) { $blockedReasons.Add("operator_notification_readiness_incomplete") }
}
if ([bool]$operatorNotificationReadiness.real_send_performed -or [bool]$operatorNotificationReadiness.raw_notification_payload_included -or [bool]$operatorNotificationReadiness.credential_values_exposed) {
  if (-not $blockedReasons.Contains("operator_notification_readiness_unsafe")) { $blockedReasons.Add("operator_notification_readiness_unsafe") }
}
if (-not [bool]$reviewGate.available) {
  if (-not $blockedReasons.Contains("review_gate_unavailable")) { $blockedReasons.Add("review_gate_unavailable") }
}
if ([bool]$reviewGate.allowed_unbounded_run -or [bool]$reviewGate.allowed_daemon -or -not [bool]$reviewGate.project_control_paused -or -not [bool]$reviewGate.old_residue_excluded) {
  if (-not $blockedReasons.Contains("review_gate_unsafe")) { $blockedReasons.Add("review_gate_unsafe") }
}
if (-not [bool]$operatorReport.available) {
  if (-not $blockedReasons.Contains("operator_report_unavailable")) { $blockedReasons.Add("operator_report_unavailable") }
}
if ([bool]$operatorReport.project_control_unpaused -or [bool]$operatorReport.run_until_hold_recursive -or -not [bool]$operatorReport.old_residue_excluded) {
  if (-not $blockedReasons.Contains("operator_report_unsafe")) { $blockedReasons.Add("operator_report_unsafe") }
}
if ($RefreshHeartbeat -and -not [bool]$heartbeat.refreshed) { $blockedReasons.Add("heartbeat_refresh_failed") }
if ($unsafeMutation) { $blockedReasons.Add("unsafe_mutation_flag_detected") }
if ($tokenPrinted) { $blockedReasons.Add("token_printed_detected") }

$workerOnline = ([int]$readiness.workers_online -ge 1 -or [bool]$heartbeat.worker_online_after)
$status = if ($blockedReasons.Count -gt 0) {
  "blocked"
} elseif (@($readiness.warnings).Count -gt 0 -or $hygiene.failed_unrecovered -gt 0 -or $hygiene.blocked -gt 0 -or $hygiene.needs_evidence -gt 0) {
  "partial"
} elseif ([bool]$executionSecondGate.execution_forbidden -or [string]$startOnePreview.status -eq "no_safe_candidate") {
  "partial"
} elseif ($commitAligned -and $workerOnline -and -not $unsafeMutation -and -not $tokenPrinted) {
  "pass"
} else {
  "blocked"
}

$nextAction = if ($status -eq "blocked") {
  "Fix convergence blockers before any self-bootstrap execution-class command."
  } elseif ($status -eq "partial") {
  if ([bool]$hygieneApplyPreview.available -and [bool]$notificationDryRun.available) {
    "Goal 318 preview paths are available. Keep project_control paused; execution remains forbidden until a later explicitly authorized start-one apply pilot."
  } else {
    "Keep project_control paused and prepare Goal 317 preview/apply repair for evidence metadata and blocked-task archive/keep decisions; do not requeue or execute tasks."
  }
} else {
  "Continue with read-only monitoring until an explicit execution-class goal authorizes a separate action."
}

$report = [pscustomobject]@{
  schema = "skybridge.self_bootstrap_convergence.v1"
  ok = ($status -in @("pass", "partial"))
  status = $status
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  local = [pscustomobject]@{
    branch = [string]$local.branch
    clean = [bool]$local.clean
    head_commit = [string]$local.head_commit
    main_commit = [string]$local.main_commit
  }
  cloud = [pscustomobject]@{
    version_available = [bool]$version.available
    version_ok = [bool]$version.ok
    commit_sha = $cloudCommit
    image_ref = Get-Prop -Object $version -Name "image_ref"
    route_parity_ok = $routeParityOk
    deploy_evidence_ok = $deployEvidenceOk
    commit_aligned = $commitAligned
  }
  heartbeat = $heartbeat
  readiness = $readiness
  hygiene = [pscustomobject]@{
    total_tasks = $hygiene.total_tasks
    failed_unrecovered = $hygiene.failed_unrecovered
    blocked = $hygiene.blocked
    needs_evidence = $hygiene.needs_evidence
    stale_leases = $hygiene.stale_leases
    stale_claims = $hygiene.stale_claims
    safe_requeue_candidates_count = $hygiene.safe_requeue_candidates_count
    evidence_repair_candidates_count = $hygiene.evidence_repair_candidates_count
    archive_or_keep_blocked_candidates_count = $hygiene.archive_or_keep_blocked_candidates_count
    unsafe_to_requeue_candidates_count = $hygiene.unsafe_to_requeue_candidates_count
    expected_active_pilot_task = $hygiene.expected_active_pilot_task
    active_task_id = $hygiene.active_task_id
    active_task_allowed_for_goal_319_pilot = $hygiene.active_task_allowed_for_goal_319_pilot
  }
  hygiene_apply_preview = $hygieneApplyPreview
  notification_readiness = $notificationDryRun
  execution_second_gate = $executionSecondGate
  start_one_preview = $startOnePreview
  pilot_seed = $pilotSeed
  start_one_apply_pilot = $startOneApplyPilot
  start_one_failure_semantics = $startOneFailureSemantics
  bounded_pilot_seed = $boundedPilotSeed
  bounded_run_until_hold = $boundedRunUntilHold
  bounded_run_until_hold_report = $boundedRunUntilHoldReport
  campaign_task_compiler = $campaignTaskCompiler
  campaign_policy_report = $campaignPolicyReport
  operator_report = $operatorReport
  operator_notification_readiness = $operatorNotificationReadiness
  review_gate = $reviewGate
  execution_forbidden = [bool]$executionSecondGate.execution_forbidden
  can_start_one_false_reason = if (-not [bool]$readiness.can_start_one) {
    "self_bootstrap_readiness_can_start_one_false"
  } elseif ([bool]$executionSecondGate.execution_forbidden) {
    "execution_second_gate_forbids_execution"
  } elseif ([string]$startOnePreview.status -eq "no_safe_candidate") {
    "start_one_preview_no_safe_candidate"
  } else {
    "not_reported"
  }
  forbidden_actions = $forbidden
  residual_task_hygiene_warnings = @(
    if ($hygiene.evidence_repair_candidates_count -gt 0) { "task_evidence_repair_needed" }
    if ($hygiene.archive_or_keep_blocked_candidates_count -gt 0) { "blocked_tasks_present" }
    if ($hygiene.unsafe_to_requeue_candidates_count -gt 0) { "unsafe_to_requeue_tasks_present" }
    if ([bool]$pilotSeed.available -and -not [bool]$pilotSeed.pilot_task_exists) { "start_one_pilot_task_not_seeded" }
    if ([bool]$boundedPilotSeed.available -and [int]$boundedPilotSeed.would_create_count -gt 0) { "bounded_pilot_tasks_not_seeded" }
    if ([bool]$reviewGate.available -and [bool]$reviewGate.needs_operator_review) { "operator_review_required" }
  )
  deferred_execution_blockers = @($deferredExecutionBlockers.ToArray())
  recommended_next_safe_action = $nextAction
  safety = [pscustomobject]@{
    read_only_checks = $true
    heartbeat_refresh_requested = [bool]$RefreshHeartbeat
    heartbeat_only_when_refreshed = [bool]$RefreshHeartbeat
    unsafe_mutation_flag_detected = $unsafeMutation
    token_printed = $false
  }
  blocked_reasons = @($blockedReasons.ToArray())
  token_printed = $false
}

if ($OutputJsonFile) {
  $dir = Split-Path -Parent $OutputJsonFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputJsonFile -Encoding UTF8
}

if ($OutputMarkdownFile) {
  $dir = Split-Path -Parent $OutputMarkdownFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  New-MarkdownReport -Report $report | Set-Content -LiteralPath $OutputMarkdownFile -Encoding UTF8
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "Status:       $($report.status)"
  "OK:           $($report.ok)"
  "Blockers:     $(if ($report.blocked_reasons.Count -gt 0) { $report.blocked_reasons -join ', ' } else { 'none' })"
  "Warnings:     $(if ($report.readiness.warnings.Count -gt 0) { $report.readiness.warnings -join ', ' } else { 'none' })"
  "Local:        branch=$($report.local.branch) clean=$($report.local.clean) head=$($report.local.head_commit)"
  "Cloud:        commit=$($report.cloud.commit_sha) aligned=$($report.cloud.commit_aligned) route=$($report.cloud.route_parity_ok) deploy=$($report.cloud.deploy_evidence_ok)"
  "Heartbeat:    requested=$($report.heartbeat.requested) refreshed=$($report.heartbeat.refreshed) sent=$($report.heartbeat.heartbeat_sent) online=$($report.heartbeat.worker_online_after)"
  "Readiness:    status=$($report.readiness.status) workers_online=$($report.readiness.workers_online) project_control=$($report.readiness.project_control_state) start_one=$($report.readiness.can_start_one) run_until_hold=$($report.readiness.can_run_until_hold)"
  "Hygiene:      total=$($report.hygiene.total_tasks) failed=$($report.hygiene.failed_unrecovered) blocked=$($report.hygiene.blocked) evidence=$($report.hygiene.evidence_repair_candidates_count) archive_or_keep=$($report.hygiene.archive_or_keep_blocked_candidates_count) unsafe_requeue=$($report.hygiene.unsafe_to_requeue_candidates_count)"
  "ApplyPreview: available=$($report.hygiene_apply_preview.available) mode=$($report.hygiene_apply_preview.mode) evidence=$($report.hygiene_apply_preview.evidence_repair_actions_count) archive_or_keep=$($report.hygiene_apply_preview.archive_or_keep_blocked_actions_count) unsafe_requeue=$($report.hygiene_apply_preview.unsafe_to_requeue_exclusion_actions_count)"
  "NotifyDryRun: available=$($report.notification_readiness.available) status=$($report.notification_readiness.status) ready=$($report.notification_readiness.ready_provider_count) total=$($report.notification_readiness.provider_count) real_send=$($report.notification_readiness.real_send_performed)"
  "SecondGate:   available=$($report.execution_second_gate.available) status=$($report.execution_second_gate.status) preview_only=$($report.execution_second_gate.allowed_preview_only) execution=$($report.execution_second_gate.allowed_execution) project_control=$($report.execution_second_gate.project_control_state)"
  "StartPreview: available=$($report.start_one_preview.available) status=$($report.start_one_preview.status) selected=$(if ($report.start_one_preview.selected_candidate) { $report.start_one_preview.selected_candidate.task_id } else { 'none' }) would_claim=$($report.start_one_preview.would_claim) would_codex=$($report.start_one_preview.would_run_codex)"
  "PilotSeed:    available=$($report.pilot_seed.available) status=$($report.pilot_seed.status) exists=$($report.pilot_seed.pilot_task_exists) would_create=$($report.pilot_seed.would_create_task)"
  "ApplyPilot:   available=$($report.start_one_apply_pilot.available) status=$($report.start_one_apply_pilot.status) selected=$(if ($report.start_one_apply_pilot.selected_task_id) { $report.start_one_apply_pilot.selected_task_id } else { 'none' }) completed=$($report.start_one_apply_pilot.pilot_task_completed) old_residue_excluded=$($report.start_one_apply_pilot.old_residue_remains_excluded)"
  "HoldReport:   available=$($report.start_one_failure_semantics.available) terminal=$($report.start_one_failure_semantics.latest_pilot_execution_terminal_state) hold=$(if ($report.start_one_failure_semantics.latest_hold_reason) { $report.start_one_failure_semantics.latest_hold_reason } else { 'none' }) evidence=$($report.start_one_failure_semantics.evidence_present) manual_review=$($report.start_one_failure_semantics.manual_operator_review_needed)"
  "BoundedSeed:  available=$($report.bounded_pilot_seed.available) status=$($report.bounded_pilot_seed.status) would_create=$($report.bounded_pilot_seed.would_create_count) pilot_tasks=$($report.bounded_pilot_seed.pilot_task_count)"
  "BoundedRun:   available=$($report.bounded_run_until_hold.available) stop=$($report.bounded_run_until_hold.latest_stop_reason) hold=$(if ($report.bounded_run_until_hold.latest_hold_reason) { $report.bounded_run_until_hold.latest_hold_reason } else { 'none' }) selected=$($report.bounded_run_until_hold.selected_candidate_count) executed=$($report.bounded_run_until_hold.executed_task_count) evidence=$($report.bounded_run_until_hold.evidence_present) old_residue_excluded=$($report.bounded_run_until_hold.old_residue_excluded) bounded=$($report.bounded_run_until_hold.run_until_hold_bounded)"
  "BoundedRpt:   available=$($report.bounded_run_until_hold_report.available) status=$($report.bounded_run_until_hold_report.latest_bounded_run_status) evidence=$($report.bounded_run_until_hold_report.evidence_present) project_control_paused=$($report.bounded_run_until_hold_report.project_control_stayed_paused)"
  "CampaignCmp: available=$($report.campaign_task_compiler.available) status=$($report.campaign_task_compiler.status) campaign=$($report.campaign_task_compiler.campaign_id) generated=$($report.campaign_task_compiler.generated_task_count) rejected=$($report.campaign_task_compiler.rejected_unsafe_item_count)"
  "CampaignRpt: available=$($report.campaign_policy_report.available) status=$($report.campaign_policy_report.campaign_status) safe_tasks=$($report.campaign_policy_report.safe_task_count) evidence=$($report.campaign_policy_report.evidence_present)"
  "OperatorRpt: available=$($report.operator_report.available) ok=$($report.operator_report.ok) campaign=$($report.operator_report.campaign_included) bounded=$($report.operator_report.bounded_run_included) evidence=$($report.operator_report.evidence_present)"
  "OperatorNtf: available=$($report.operator_notification_readiness.available) status=$($report.operator_notification_readiness.status) dry_run=$($report.operator_notification_readiness.dry_run) report_delivery=$($report.operator_notification_readiness.report_delivery_supported) real_provider=$($report.operator_notification_readiness.real_provider_configured)"
  "ReviewGate:  available=$($report.review_gate.available) status=$($report.review_gate.gate_status) preview=$($report.review_gate.allowed_preview) bounded=$($report.review_gate.allowed_bounded_run) operator_review=$($report.review_gate.needs_operator_review)"
  "ExecBlocked:  $($report.execution_forbidden) reason=$($report.can_start_one_false_reason)"
  "DeferredExec: $(if ($report.deferred_execution_blockers.Count -gt 0) { $report.deferred_execution_blockers -join ', ' } else { 'none' })"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
