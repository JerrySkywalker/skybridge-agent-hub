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
  [string]$FixtureHygieneFile
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
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -ne 0 -and -not $AllowNonZero) {
    throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)"
  }
  if ($null -ne $parsed) { return $parsed }
  if ($exitCode -ne 0) {
    return [pscustomobject]@{ ok = $false; error_summary = ConvertTo-SafeText -Text $text; token_printed = $false }
  }
  throw "Command did not return JSON: pwsh $($Arguments -join ' ')"
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
  $workers = Get-Prop -Object (Get-Prop -Object $readiness -Name "control_plane") -Name "workers"
  $projectControl = Get-Prop -Object (Get-Prop -Object $readiness -Name "control_plane") -Name "project_control"
  [pscustomobject]@{
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
  [pscustomobject]@{
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
    token_printed = Get-BoolProp -Object $hygiene -Name "token_printed"
    safety = Get-Prop -Object $hygiene -Name "safety"
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
  [bool]$hygiene.token_printed
)

$blockedReasons = [System.Collections.Generic.List[string]]::new()
if ([string]$local.branch -ne "main") { $blockedReasons.Add("not_on_main") }
if (-not [bool]$local.clean) { $blockedReasons.Add("worktree_dirty") }
if (-not [bool]$version.available) { $blockedReasons.Add("cloud_version_unavailable") }
if (-not $commitAligned) { $blockedReasons.Add("cloud_commit_mismatch") }
if (-not $routeParityOk) { $blockedReasons.Add("route_parity_failed") }
foreach ($blocker in @($readiness.blockers)) {
  if (-not [string]::IsNullOrWhiteSpace($blocker) -and -not $blockedReasons.Contains($blocker)) { $blockedReasons.Add($blocker) }
}
if ($RefreshHeartbeat -and -not [bool]$heartbeat.refreshed) { $blockedReasons.Add("heartbeat_refresh_failed") }
if ($unsafeMutation) { $blockedReasons.Add("unsafe_mutation_flag_detected") }
if ($tokenPrinted) { $blockedReasons.Add("token_printed_detected") }

$workerOnline = ([int]$readiness.workers_online -ge 1 -or [bool]$heartbeat.worker_online_after)
$status = if ($blockedReasons.Count -gt 0) {
  "blocked"
} elseif (@($readiness.warnings).Count -gt 0 -or $hygiene.failed_unrecovered -gt 0 -or $hygiene.blocked -gt 0 -or $hygiene.needs_evidence -gt 0) {
  "partial"
} elseif ($commitAligned -and $workerOnline -and -not $unsafeMutation -and -not $tokenPrinted) {
  "pass"
} else {
  "blocked"
}

$nextAction = if ($status -eq "blocked") {
  "Fix convergence blockers before any self-bootstrap execution-class command."
} elseif ($status -eq "partial") {
  "Keep project_control paused and prepare Goal 317 preview/apply repair for evidence metadata and blocked-task archive/keep decisions; do not requeue or execute tasks."
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
  }
  forbidden_actions = $forbidden
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
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
