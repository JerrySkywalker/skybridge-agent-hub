[CmdletBinding()]
param(
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$Repo,
  [string]$MainRef = "origin/main",
  [string]$CampaignId,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [int]$TimeoutSeconds = 30,
  [int]$DeployVerifyTimeoutSeconds = 180,
  [int]$DeployVerifyPollSeconds = 15,
  [switch]$Json,
  [string]$OutputFile,
  [string]$FixtureGitFile,
  [string]$FixtureVersionFile,
  [string]$FixtureParityFile,
  [string]$FixtureDeployEvidenceFile,
  [string]$FixtureStatusFile,
  [string]$FixtureHermesHealthFile,
  [string]$FixtureAdminEscalationFile,
  [string]$FixtureNotificationsFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

$ApiBase = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
$fixtureMode = ($FixtureGitFile -or $FixtureVersionFile -or $FixtureParityFile -or $FixtureDeployEvidenceFile -or $FixtureStatusFile -or $FixtureHermesHealthFile -or $FixtureAdminEscalationFile -or $FixtureNotificationsFile)
Assert-SkybridgeApiBaseUsable -ApiBase $ApiBase -AllowPlaceholder $fixtureMode
if (-not $fixtureMode) {
  Assert-SkybridgeApiBaseService -ApiBase $ApiBase -TimeoutSeconds $TimeoutSeconds | Out-Null
} elseif ($FixtureVersionFile) {
  Assert-SkybridgeVersionService -Version (Get-Content -Raw -LiteralPath $FixtureVersionFile | ConvertFrom-Json)
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-IntProp {
  param($Object, [string]$Name)
  $value = Get-Prop -Object $Object -Name $Name -Default 0
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return 0 }
  return [int]$value
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 220)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?i)HERMES_API_KEY", "HERMES_KEY_VAR"
  $safe = $safe -replace "(?i)SKYBRIDGE_WORKER_TOKEN", "SKYBRIDGE_WORKER_VAR"
  $safe = $safe -replace "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function ConvertTo-EndpointSummary {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  try {
    $uri = [Uri]$Value
    return "$($uri.Scheme)://[redacted-host]"
  } catch {
    return "[redacted-endpoint]"
  }
}

function Invoke-GitText {
  param([string[]]$Arguments)
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
  return (($output | Out-String).Trim())
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
  if ($exitCode -ne 0) { throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)" }
  throw "Command did not return JSON: pwsh $($Arguments -join ' ')"
}

function New-ProbeFailure {
  param([string]$Name, [string]$Message)
  [pscustomobject]@{
    available = $false
    ok = $false
    name = $Name
    error_summary = ConvertTo-SafeText -Text $Message
    token_printed = $false
  }
}

function Get-RepoFromRemote {
  if ($Repo) { return $Repo }
  try {
    $remote = Invoke-GitText @("remote", "get-url", "origin")
    if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
      return "$($Matches[1])/$($Matches[2])"
    }
  } catch {}
  return $null
}

function Get-GitReadiness {
  if ($FixtureGitFile) {
    $fixture = Read-JsonFile -Path $FixtureGitFile
    return [pscustomobject]@{
      branch = [string](Get-Prop -Object $fixture -Name "branch" -Default "")
      clean = [bool](Get-Prop -Object $fixture -Name "clean" -Default $false)
      head_commit = [string](Get-Prop -Object $fixture -Name "head_commit" -Default "")
      main_ref = [string](Get-Prop -Object $fixture -Name "main_ref" -Default $MainRef)
      main_commit = [string](Get-Prop -Object $fixture -Name "main_commit" -Default "")
      source = "fixture"
    }
  }

  $branch = ""
  $head = ""
  $main = ""
  $clean = $false
  try { $branch = Invoke-GitText @("branch", "--show-current") } catch {}
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "HEAD" }
  try { $head = Invoke-GitText @("rev-parse", "HEAD") } catch {}
  try { $main = Invoke-GitText @("rev-parse", "--verify", $MainRef) } catch {
    try { $main = Invoke-GitText @("rev-parse", "--verify", "main") } catch {}
  }
  try { $clean = [string]::IsNullOrWhiteSpace((Invoke-GitText @("status", "--short"))) } catch {}
  return [pscustomobject]@{
    branch = $branch
    clean = $clean
    head_commit = $head
    main_ref = $MainRef
    main_commit = $main
    source = "git"
  }
}

function Get-VersionReadiness {
  if ($FixtureVersionFile) {
    $version = Read-JsonFile -Path $FixtureVersionFile
    return [pscustomobject]@{
      available = $true
      ok = $true
      commit_sha = Get-Prop -Object $version -Name "commit_sha"
      image_tag = Get-Prop -Object $version -Name "image_tag"
      image_ref = Get-Prop -Object $version -Name "image_ref"
      token_printed = $false
    }
  }
  try {
    $version = Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))/v1/version" -TimeoutSec $TimeoutSeconds
    Assert-SkybridgeVersionService -Version $version
    return [pscustomobject]@{
      available = $true
      ok = $true
      commit_sha = Get-Prop -Object $version -Name "commit_sha"
      image_tag = Get-Prop -Object $version -Name "image_tag"
      image_ref = Get-Prop -Object $version -Name "image_ref"
      token_printed = $false
    }
  } catch {
    return New-ProbeFailure -Name "cloud_version" -Message $_.Exception.Message
  }
}

function Get-ParityReadiness {
  if ($FixtureParityFile) {
    $parity = Read-JsonFile -Path $FixtureParityFile
  } else {
    try {
      $parity = Invoke-ChildJson -Arguments @(
        "-File", (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1"),
        "-ApiBase", $ApiBase,
        "-Json"
      ) -AllowNonZero
    } catch {
      return New-ProbeFailure -Name "cloud_route_parity" -Message $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $parity -Name "ok" -Default $false)
    deployment_parity_status = [string](Get-Prop -Object $parity -Name "deployment_parity_status" -Default (Get-Prop -Object $parity -Name "status" -Default "unknown"))
    server_online = [bool](Get-Prop -Object $parity -Name "server_online" -Default $false)
    manual_task_routes_available = [bool](Get-Prop -Object $parity -Name "manual_task_routes_available" -Default $false)
    missing_routes = @((Get-Prop -Object $parity -Name "missing_routes" -Default @()) | ForEach-Object { [string]$_ })
    recommended_action = [string](Get-Prop -Object $parity -Name "recommended_action" -Default "")
    token_printed = $false
  }
}

function Get-DeployEvidenceReadiness {
  param([string]$MainCommit)
  if ($FixtureDeployEvidenceFile) {
    $deploy = Read-JsonFile -Path $FixtureDeployEvidenceFile
  } else {
    if ([string]::IsNullOrWhiteSpace($MainCommit)) {
      return New-ProbeFailure -Name "deploy_evidence" -Message "main commit unavailable"
    }
    $repoName = Get-RepoFromRemote
    if ([string]::IsNullOrWhiteSpace($repoName)) {
      return New-ProbeFailure -Name "deploy_evidence" -Message "repository remote unavailable"
    }
    try {
      $deploy = Invoke-ChildJson -Arguments @(
        "-File", (Join-Path $PSScriptRoot "skybridge-verify-cloud-autodeploy.ps1"),
        "-Repo", $repoName,
        "-Commit", $MainCommit,
        "-ApiBase", $ApiBase,
        "-TimeoutSeconds", [string]$DeployVerifyTimeoutSeconds,
        "-PollSeconds", [string]$DeployVerifyPollSeconds,
        "-Json"
      )
    } catch {
      return New-ProbeFailure -Name "deploy_evidence" -Message $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $deploy -Name "ok" -Default $false)
    commit_sha = Get-Prop -Object $deploy -Name "commit_sha"
    docker_images_run_id = Get-Prop -Object $deploy -Name "docker_images_run_id"
    deploy_cloud_run_id = Get-Prop -Object $deploy -Name "deploy_cloud_run_id"
    deploy_report_status = Get-Prop -Object $deploy -Name "deploy_report_status"
    deploy_report_reason = Get-Prop -Object $deploy -Name "deploy_report_reason"
    cloud_parity_status = Get-Prop -Object $deploy -Name "cloud_parity_status"
    version_commit_sha = Get-Prop -Object $deploy -Name "version_commit_sha"
    version_image_ref = Get-Prop -Object $deploy -Name "version_image_ref"
    rollback_status = Get-Prop -Object $deploy -Name "rollback_status"
    triggered_deploy = [bool](Get-Prop -Object $deploy -Name "triggered_deploy" -Default $false)
    mutated_server = [bool](Get-Prop -Object $deploy -Name "mutated_server" -Default $false)
    created_tag = [bool](Get-Prop -Object $deploy -Name "created_tag" -Default $false)
    token_printed = $false
  }
}

function Get-StatusReadiness {
  if ($FixtureStatusFile) {
    $status = Read-JsonFile -Path $FixtureStatusFile
  } else {
    try {
      $args = @(
        "-File", (Join-Path $PSScriptRoot "skybridge-status.ps1"),
        "-ApiBase", $ApiBase,
        "-ProjectId", $ProjectId,
        "-ShowCampaigns",
        "-ShowCampaignSteps",
        "-Hygiene",
        "-ShowLeases",
        "-ShowProposals",
        "-ReconcileProposals",
        "-ShowAll",
        "-TimeoutSeconds", [string]$TimeoutSeconds,
        "-ColorMode", "Never",
        "-Json"
      )
      if ($CampaignId) { $args += @("-CampaignId", $CampaignId) }
      if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
      if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
      $status = Invoke-ChildJson -Arguments $args
    } catch {
      return New-ProbeFailure -Name "control_plane_status" -Message $_.Exception.Message
    }
  }

  $task = Get-Prop -Object $status -Name "task_summary"
  $campaign = Get-Prop -Object $status -Name "campaign_summary"
  $control = Get-Prop -Object $status -Name "control_summary" -Default (Get-Prop -Object $status -Name "control")
  $workers = @((Get-Prop -Object $status -Name "workers" -Default @()) | Where-Object { $null -ne $_ })
  $onlineWorkers = @($workers | Where-Object { [string](Get-Prop -Object $_ -Name "status") -eq "online" })
  $staleWorkers = @($workers | Where-Object { [string](Get-Prop -Object $_ -Name "status") -eq "stale" })
  $offlineWorkers = @($workers | Where-Object { [string](Get-Prop -Object $_ -Name "status") -eq "offline" })

  return [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $status -Name "ok" -Default $true)
    project_control = [pscustomobject]@{
      available = ($null -ne $control)
      state = [string](Get-Prop -Object $control -Name "state" -Default "unknown")
      stop_requested = [bool](Get-Prop -Object $control -Name "stop_requested" -Default $false)
      stop_reason = Get-Prop -Object $control -Name "stop_reason"
      degraded_reason = Get-Prop -Object $control -Name "degraded_reason"
    }
    tasks = [pscustomobject]@{
      available = ($null -ne $task)
      total = Get-IntProp -Object $task -Name "total"
      active = Get-IntProp -Object $task -Name "active"
      queued = Get-IntProp -Object $task -Name "queued"
      claimed = Get-IntProp -Object $task -Name "claimed"
      running = Get-IntProp -Object $task -Name "running"
      stale_leases = Get-IntProp -Object $task -Name "stale_leases"
      stale_claims = Get-IntProp -Object $task -Name "stale_claims"
      stale_running = Get-IntProp -Object $task -Name "stale_running"
      missing_leases = Get-IntProp -Object $task -Name "missing_leases"
      failed_unrecovered = Get-IntProp -Object $task -Name "failed_unrecovered"
      blocked = Get-IntProp -Object $task -Name "blocked"
      needs_evidence = Get-IntProp -Object $task -Name "needs_evidence"
    }
    workers = [pscustomobject]@{
      available = ($workers.Count -gt 0)
      total = $workers.Count
      online = $onlineWorkers.Count
      stale = $staleWorkers.Count
      offline = $offlineWorkers.Count
      online_worker_ids = @($onlineWorkers | ForEach-Object { [string](Get-Prop -Object $_ -Name "worker_id") })
    }
    campaign_queue = [pscustomobject]@{
      available = ($null -ne $campaign)
      total = Get-IntProp -Object $campaign -Name "total"
      ready = Get-IntProp -Object $campaign -Name "ready"
      running = Get-IntProp -Object $campaign -Name "running"
      paused = Get-IntProp -Object $campaign -Name "paused"
      held = Get-IntProp -Object $campaign -Name "held"
      failed = Get-IntProp -Object $campaign -Name "failed"
      completed = Get-IntProp -Object $campaign -Name "completed"
      aborted = Get-IntProp -Object $campaign -Name "aborted"
    }
    warnings = @((Get-Prop -Object $status -Name "warnings" -Default @()) | ForEach-Object { ConvertTo-SafeText -Text ([string]$_) })
    token_printed = $false
  }
}

function Get-HermesReadiness {
  if ($FixtureHermesHealthFile) {
    $health = Read-JsonFile -Path $FixtureHermesHealthFile
  } else {
    try {
      $args = @(
        "-File", (Join-Path $PSScriptRoot "skybridge-hermes-health.ps1"),
        "-TimeoutSeconds", [string]$TimeoutSeconds,
        "-Json"
      )
      if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
      if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
      $health = Invoke-ChildJson -Arguments $args
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        direct_https = $false
        endpoint = $null
        platform = $null
        model = $null
        runtime_mode = $null
        tool_execution = $null
        responses_api = $null
        runs = $null
        error_summary = ConvertTo-SafeText -Text $_.Exception.Message
        token_printed = $false
      }
    }
  }

  $runtime = Get-Prop -Object $health -Name "runtime"
  $features = Get-Prop -Object $health -Name "features"
  return [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $health -Name "ok" -Default $false)
    direct_https = [bool](Get-Prop -Object $health -Name "direct_https" -Default $false)
    endpoint = ConvertTo-EndpointSummary -Value ([string](Get-Prop -Object $health -Name "api_base"))
    platform = Get-Prop -Object $health -Name "platform"
    model = Get-Prop -Object $health -Name "model"
    runtime_mode = Get-Prop -Object $runtime -Name "mode"
    tool_execution = Get-Prop -Object $runtime -Name "tool_execution"
    responses_api = Get-Prop -Object $features -Name "responses_api"
    runs = Get-Prop -Object $features -Name "runs"
    token_printed = $false
  }
}

function Get-AdminEscalationReadiness {
  if ($FixtureAdminEscalationFile) {
    $admin = Read-JsonFile -Path $FixtureAdminEscalationFile
  } else {
    try {
      $args = @(
        "-File", (Join-Path $PSScriptRoot "skybridge-admin-escalation-readiness.ps1"),
        "-TimeoutSeconds", [string]$TimeoutSeconds,
        "-Json"
      )
      if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
      if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
      $admin = Invoke-ChildJson -Arguments $args -AllowNonZero
    } catch {
      return [pscustomobject]@{
        available = $false
        ok = $false
        primary_current = "hermes-wechat"
        long_term_primary = "skybridge-notify-gateway"
        fallback = "bootstrap-notifier"
        hermes_available = $false
        hermes_direct_https = $false
        hermes_platform = $null
        hermes_runtime_mode = $null
        hermes_responses_api = $false
        wechat_escalation_configured = $false
        can_send_blocker_notice = $false
        dry_run_supported = $true
        real_send_performed = $false
        credential_values_exposed = $false
        raw_response_included = $false
        error_summary = ConvertTo-SafeText -Text $_.Exception.Message
        token_printed = $false
      }
    }
  }

  return [pscustomobject]@{
    available = $true
    ok = [bool](Get-Prop -Object $admin -Name "ok" -Default $false)
    primary_current = [string](Get-Prop -Object $admin -Name "primary_current" -Default "hermes-wechat")
    long_term_primary = [string](Get-Prop -Object $admin -Name "long_term_primary" -Default "skybridge-notify-gateway")
    fallback = [string](Get-Prop -Object $admin -Name "fallback" -Default "bootstrap-notifier")
    hermes_available = [bool](Get-Prop -Object $admin -Name "hermes_available" -Default $false)
    hermes_direct_https = [bool](Get-Prop -Object $admin -Name "hermes_direct_https" -Default $false)
    hermes_platform = Get-Prop -Object $admin -Name "hermes_platform"
    hermes_runtime_mode = Get-Prop -Object $admin -Name "hermes_runtime_mode"
    hermes_responses_api = [bool](Get-Prop -Object $admin -Name "hermes_responses_api" -Default $false)
    wechat_escalation_configured = [bool](Get-Prop -Object $admin -Name "wechat_escalation_configured" -Default $false)
    can_send_blocker_notice = [bool](Get-Prop -Object $admin -Name "can_send_blocker_notice" -Default $false)
    dry_run_supported = [bool](Get-Prop -Object $admin -Name "dry_run_supported" -Default $true)
    real_send_performed = [bool](Get-Prop -Object $admin -Name "real_send_performed" -Default $false)
    credential_values_exposed = [bool](Get-Prop -Object $admin -Name "credential_values_exposed" -Default $false)
    raw_response_included = [bool](Get-Prop -Object $admin -Name "raw_response_included" -Default $false)
    token_printed = [bool](Get-Prop -Object $admin -Name "token_printed" -Default $false)
  }
}

function Get-NotificationReadiness {
  if ($FixtureNotificationsFile) {
    $payload = Read-JsonFile -Path $FixtureNotificationsFile
  } else {
    try {
      $providers = Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))/v1/notifications/providers" -TimeoutSec $TimeoutSeconds
      $summary = $null
      try { $summary = Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))/v1/notifications/summary" -TimeoutSec $TimeoutSeconds } catch {}
      $payload = [pscustomobject]@{
        providers = @($providers.providers)
        summary = $summary
      }
    } catch {
      return New-ProbeFailure -Name "notifications" -Message $_.Exception.Message
    }
  }

  $providers = @((Get-Prop -Object $payload -Name "providers" -Default @()) | Where-Object { $null -ne $_ })
  $readyStatuses = @("ok", "ready", "configured", "enabled", "active", "sent")
  $readyProviders = @($providers | Where-Object { $readyStatuses -contains ([string](Get-Prop -Object $_ -Name "status")).ToLowerInvariant() })
  return [pscustomobject]@{
    available = $true
    ok = ($readyProviders.Count -gt 0)
    total = $providers.Count
    ready = $readyProviders.Count
    providers = @($providers | ForEach-Object {
      [pscustomobject]@{
        provider = [string](Get-Prop -Object $_ -Name "provider")
        status = [string](Get-Prop -Object $_ -Name "status" -Default "unknown")
        credential_values_exposed = [bool](Get-Prop -Object $_ -Name "credential_values_exposed" -Default $false)
      }
    })
    token_printed = $false
  }
}

function Add-Blocker {
  param([System.Collections.Generic.List[string]]$List, [string]$Value)
  if (-not $List.Contains($Value)) { $List.Add($Value) }
}

function Add-Warning {
  param([System.Collections.Generic.List[string]]$List, [string]$Value)
  if (-not $List.Contains($Value)) { $List.Add($Value) }
}

function Get-HumanAction {
  param([string[]]$Blockers)
  if ($Blockers.Count -eq 0) { return "none" }
  if ($Blockers -contains "not_on_main" -or $Blockers -contains "worktree_dirty") {
    return "Check out a clean main worktree at the deployed commit before starting any worker."
  }
  if ($Blockers -contains "deploy_evidence_unavailable" -or $Blockers -contains "cloud_version_commit_mismatch" -or $Blockers -contains "cloud_route_parity_not_ok") {
    return "Inspect CI/CD and cloud deploy evidence; do not start self-bootstrap until cloud main parity is restored."
  }
  if ($Blockers -contains "active_tasks_present" -or $Blockers -contains "stale_leases_present" -or $Blockers -contains "stale_task_residue_present") {
    return "Inspect queue hygiene, active tasks and stale leases; recover or complete residue through an explicitly authorized operator flow."
  }
  if ($Blockers -contains "worker_offline") {
    return "Bring one authorized local worker online and prove heartbeat before any start-one or run-until-hold attempt."
  }
  if ($Blockers -contains "hermes_unavailable" -or $Blockers -contains "hermes_direct_https_unavailable") {
    return "Restore Hermes direct HTTPS health or hold for manual planning and audit."
  }
  if ($Blockers -contains "admin_escalation_unavailable") {
    return "Restore the Hermes WeChat or WeCom administrator escalation path before any start-one or run-until-hold attempt."
  }
  if ($Blockers -contains "admin_escalation_credentials_exposed") {
    return "Stop and inspect the admin escalation probe for credential exposure; do not run self-bootstrap until outputs are sanitized."
  }
  if ($Blockers -contains "campaign_queue_not_ready") {
    return "Prepare or import a reviewed campaign queue in a separate authorized goal; this audit must not create tasks or advance metadata."
  }
  return "Review blockers and keep the self-bootstrap loop on hold."
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$git = Get-GitReadiness
$version = Get-VersionReadiness
$parity = Get-ParityReadiness
$deploy = Get-DeployEvidenceReadiness -MainCommit $git.main_commit
$statusProbe = Get-StatusReadiness
$hermes = Get-HermesReadiness
$adminEscalation = Get-AdminEscalationReadiness
$notifications = Get-NotificationReadiness

$blockers = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($git.main_commit)) { Add-Blocker $blockers "main_commit_unknown" }
if ($git.branch -ne "main") { Add-Blocker $blockers "not_on_main" }
if (-not $git.clean) { Add-Blocker $blockers "worktree_dirty" }

if (-not $version.available) { Add-Blocker $blockers "cloud_version_unavailable" }
elseif ($version.commit_sha -and $git.main_commit -and [string]$version.commit_sha -ne [string]$git.main_commit) { Add-Blocker $blockers "cloud_version_commit_mismatch" }

if (-not $parity.available) { Add-Blocker $blockers "cloud_route_parity_unavailable" }
elseif (-not $parity.ok -or [string]$parity.deployment_parity_status -ne "ok") { Add-Blocker $blockers "cloud_route_parity_not_ok" }

if (-not $deploy.available) { Add-Blocker $blockers "deploy_evidence_unavailable" }
elseif (-not $deploy.ok) { Add-Blocker $blockers "deploy_evidence_not_ok" }
elseif ($deploy.commit_sha -and $git.main_commit -and [string]$deploy.commit_sha -ne [string]$git.main_commit) { Add-Blocker $blockers "deploy_evidence_commit_mismatch" }
if ($deploy.triggered_deploy -or $deploy.mutated_server -or $deploy.created_tag) { Add-Blocker $blockers "read_only_violation_detected" }

if (-not $statusProbe.available) {
  Add-Blocker $blockers "control_plane_status_unavailable"
} else {
  foreach ($warning in @($statusProbe.warnings)) { if ($warning) { Add-Warning $warnings $warning } }
  if (-not $statusProbe.project_control.available -or $statusProbe.project_control.state -eq "unknown") {
    Add-Warning $warnings "project_control_state_unknown"
  } else {
    if ($statusProbe.project_control.state -eq "running") { Add-Blocker $blockers "project_control_running" }
    if ($statusProbe.project_control.stop_requested) { Add-Blocker $blockers "project_control_stop_requested" }
  }
  if (-not $statusProbe.tasks.available) {
    Add-Warning $warnings "task_counts_unavailable"
  } else {
    if ($statusProbe.tasks.active -gt 0 -or $statusProbe.tasks.queued -gt 0 -or $statusProbe.tasks.claimed -gt 0 -or $statusProbe.tasks.running -gt 0) { Add-Blocker $blockers "active_tasks_present" }
    if ($statusProbe.tasks.stale_leases -gt 0) { Add-Blocker $blockers "stale_leases_present" }
    if ($statusProbe.tasks.stale_claims -gt 0 -or $statusProbe.tasks.stale_running -gt 0 -or $statusProbe.tasks.missing_leases -gt 0) { Add-Blocker $blockers "stale_task_residue_present" }
    if ($statusProbe.tasks.failed_unrecovered -gt 0) { Add-Warning $warnings "failed_unrecovered_tasks_present" }
    if ($statusProbe.tasks.blocked -gt 0) { Add-Warning $warnings "blocked_tasks_present" }
    if ($statusProbe.tasks.needs_evidence -gt 0) { Add-Warning $warnings "task_evidence_repair_needed" }
  }
  if (-not $statusProbe.workers.available -or $statusProbe.workers.online -lt 1) { Add-Blocker $blockers "worker_offline" }
  if ($statusProbe.workers.stale -gt 0) { Add-Warning $warnings "stale_workers_present" }
  if (-not $statusProbe.campaign_queue.available) {
    Add-Warning $warnings "campaign_queue_status_unavailable"
  } else {
    $selectableCampaigns = $statusProbe.campaign_queue.ready + $statusProbe.campaign_queue.paused
    if ($statusProbe.campaign_queue.total -lt 1 -or $selectableCampaigns -lt 1) { Add-Blocker $blockers "campaign_queue_not_ready" }
    if ($statusProbe.campaign_queue.running -gt 0) { Add-Blocker $blockers "campaign_already_running" }
    if ($statusProbe.campaign_queue.held -gt 0) { Add-Warning $warnings "held_campaigns_present" }
    if ($statusProbe.campaign_queue.failed -gt 0 -or $statusProbe.campaign_queue.aborted -gt 0) { Add-Warning $warnings "failed_campaigns_present" }
  }
}

if (-not $hermes.available -or -not $hermes.ok) { Add-Blocker $blockers "hermes_unavailable" }
elseif (-not $hermes.direct_https) { Add-Blocker $blockers "hermes_direct_https_unavailable" }
if ($hermes.available -and $hermes.tool_execution -and [string]$hermes.tool_execution -ne "disabled") {
  Add-Warning $warnings "hermes_tool_execution_not_disabled"
}

if (-not $adminEscalation.available -or -not $adminEscalation.ok -or -not $adminEscalation.can_send_blocker_notice) {
  Add-Blocker $blockers "admin_escalation_unavailable"
}
if ($adminEscalation.credential_values_exposed -or $adminEscalation.raw_response_included -or $adminEscalation.token_printed) {
  Add-Blocker $blockers "admin_escalation_credentials_exposed"
}
if ($adminEscalation.real_send_performed) {
  Add-Blocker $blockers "admin_escalation_real_send_performed"
}

if (-not $notifications.available) { Add-Warning $warnings "notification_provider_status_unavailable" }
elseif (-not $notifications.ok) {
  if ($adminEscalation.ok) {
    Add-Warning $warnings "skybridge_notification_center_not_ready"
  } else {
    Add-Warning $warnings "notification_provider_unavailable"
  }
}
foreach ($provider in @($notifications.providers)) {
  if ($provider.credential_values_exposed) { Add-Blocker $blockers "notification_credentials_exposed" }
}

$blockerArray = @($blockers.ToArray())
$warningArray = @($warnings.ToArray())
$canStartOne = ($blockerArray.Count -eq 0)
$canRunUntilHold = ($canStartOne -and $hermes.ok -and $hermes.direct_https -and $adminEscalation.ok)
$overallStatus = if ($blockerArray.Count -gt 0) {
  "blocked"
} elseif ($warningArray.Count -gt 0) {
  "partial"
} elseif ($canStartOne -and $canRunUntilHold) {
  "ready"
} else {
  "unknown"
}

$recommended = if ($blockerArray.Count -eq 0) {
  "Readiness is green. The next safe action is an explicitly authorized start-one preview or run-until-hold preview; this audit does not start workers."
} else {
  Get-HumanAction -Blockers $blockerArray
}

$report = [pscustomobject]@{
  schema = "skybridge.self_bootstrap_readiness.v1"
  ok = $true
  generated_at = $generatedAt
  project_id = $ProjectId
  api_base = "configured"
  status = $overallStatus
  can_start_one = $canStartOne
  can_run_until_hold = $canRunUntilHold
  blockers = $blockerArray
  warnings = $warningArray
  required_human_action = Get-HumanAction -Blockers $blockerArray
  recommended_next_safe_action = $recommended
  repo = $git
  cloud = [pscustomobject]@{
    version = $version
    route_parity = $parity
    deploy_evidence = $deploy
  }
  control_plane = if ($statusProbe.available) {
    [pscustomobject]@{
      project_control = $statusProbe.project_control
      tasks = $statusProbe.tasks
      workers = $statusProbe.workers
      campaign_queue = $statusProbe.campaign_queue
    }
  } else { $statusProbe }
  hermes = $hermes
  admin_escalation = $adminEscalation
  notifications = $notifications
  safety = [pscustomobject]@{
    read_only = $true
    codex_run_called = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    deploy_triggered = $false
    tag_or_release_created = $false
    raw_hermes_response_included = $false
    raw_notification_payload_included = $false
    raw_logs_included = $false
    token_printed = $false
  }
  token_printed = $false
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "Status:       $($report.status)"
  "CanStartOne:  $($report.can_start_one)"
  "CanUntilHold: $($report.can_run_until_hold)"
  "Branch:       $($report.repo.branch)"
  "Clean:        $($report.repo.clean)"
  "MainCommit:   $($report.repo.main_commit)"
  "CloudCommit:  $($report.cloud.version.commit_sha)"
  "Parity:       $($report.cloud.route_parity.deployment_parity_status)"
  "Workers:      online=$($report.control_plane.workers.online) stale=$($report.control_plane.workers.stale) offline=$($report.control_plane.workers.offline)"
  "Tasks:        active=$($report.control_plane.tasks.active) queued=$($report.control_plane.tasks.queued) running=$($report.control_plane.tasks.running) stale_leases=$($report.control_plane.tasks.stale_leases)"
  "Hermes:       ok=$($report.hermes.ok) direct_https=$($report.hermes.direct_https) endpoint=$($report.hermes.endpoint)"
  "AdminEsc:     ok=$($report.admin_escalation.ok) current=$($report.admin_escalation.primary_current) can_notice=$($report.admin_escalation.can_send_blocker_notice)"
  "Notify:       ready=$($report.notifications.ready) total=$($report.notifications.total)"
  "Blockers:     $(if ($report.blockers.Count -gt 0) { $report.blockers -join ', ' } else { 'none' })"
  "Warnings:     $(if ($report.warnings.Count -gt 0) { $report.warnings -join ', ' } else { 'none' })"
  "Required:     $($report.required_human_action)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
